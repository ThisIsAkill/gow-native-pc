#include "installer_backend.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QUrl>

namespace
{
    // The repository: the folder above the launcher that holds games/<id>/game.toml (a release ships the launcher in
    // <repo>/launcher/bin; a development build sits in <repo>/launcher/build).
    QString findRoot()
    {
        QDir dir(QCoreApplication::applicationDirPath());
        for (int i = 0; i < 6; ++i)
        {
            if (QFileInfo::exists(dir.filePath(QStringLiteral("games/gow1/game.toml"))))
                return dir.absolutePath();
            if (!dir.cdUp())
                break;
        }
        return QCoreApplication::applicationDirPath();
    }

    bool onPath(const QString &program)
    {
        return !QStandardPaths::findExecutable(program).isEmpty();
    }
}

InstallerBackend::InstallerBackend(QObject *parent) : QObject(parent), m_root(findRoot()) {}

QString InstallerBackend::python() const
{
    if (onPath(QStringLiteral("python")))
        return QStringLiteral("python");
    return QStringLiteral("py");
}

// the CMake/Ninja build folder: a short path (the runtime's dependencies exceed MAX_PATH under long folders), chosen
// per copy by tools/pipeline/build.ps1 and kept in data/build-root.txt (C:\gow-build, or C:\gow-build-<hash> when
// another copy already uses that one)
QString InstallerBackend::buildRoot() const
{
    QFile file(m_root + QStringLiteral("/data/build-root.txt"));
    if (file.open(QIODevice::ReadOnly | QIODevice::Text))
    {
        const QString path = QString::fromUtf8(file.readAll()).trimmed();
        if (!path.isEmpty())
            return QDir::fromNativeSeparators(path);
    }
    return QStringLiteral("C:/gow-build");
}

QString InstallerBackend::runnerPath() const
{
    const QString exe = buildRoot() + QStringLiteral("/ps2xRuntime/ps2EntryRunner.exe");
    return QFileInfo::exists(exe) ? exe : QString();
}

QVariantMap InstallerBackend::environment() const
{
    const QString vswhere = qEnvironmentVariable("ProgramFiles(x86)") + QStringLiteral("/Microsoft Visual Studio/Installer/vswhere.exe");
    const QString runtimeDir = m_root + QStringLiteral("/engine/runtime");
    return {
        {QStringLiteral("git"), onPath(QStringLiteral("git"))},
        {QStringLiteral("python"), onPath(QStringLiteral("python")) || onPath(QStringLiteral("py"))},
        {QStringLiteral("buildTools"), QFileInfo::exists(vswhere)},
        {QStringLiteral("runtime"), QFileInfo::exists(runtimeDir + QStringLiteral("/PS2Recomp/CMakeLists.txt"))},
        {QStringLiteral("game"), !runnerPath().isEmpty()},
        {QStringLiteral("discs"), !languages().isEmpty()},
        {QStringLiteral("runtimeDir"), runtimeDir},
        {QStringLiteral("runner"), runnerPath()},
        {QStringLiteral("dataDir"), m_root + QStringLiteral("/data")},
    };
}

QVariantList InstallerBackend::languages() const
{
    QFile file(m_root + QStringLiteral("/data/") + m_game + QStringLiteral("/languages.json"));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonObject manifest = QJsonDocument::fromJson(file.readAll()).object();
    QVariantList out;
    for (const QJsonValue &v : manifest.value(QStringLiteral("languages")).toArray())
        if (QFileInfo::exists(v.toObject().value(QStringLiteral("elf")).toString()))
            out << v.toObject().toVariantMap();
    return out;
}

QString InstallerBackend::recompileElf() const
{
    QFile file(m_root + QStringLiteral("/data/") + m_game + QStringLiteral("/languages.json"));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object().value(QStringLiteral("recompile_elf")).toString();
}

void InstallerBackend::identify(const QStringList &paths)
{
    auto *p = new QProcess(this);
    p->setProgram(python());
    p->setArguments(QStringList{QStringLiteral("-I"), m_root + QStringLiteral("/tools/disc/identify.py")} + paths);
    connect(p, &QProcess::finished, this, [this, p](int, QProcess::ExitStatus)
    {
        const QJsonArray list = QJsonDocument::fromJson(p->readAllStandardOutput()).array();
        emit identified(list.toVariantList());
        p->deleteLater();
    });
    p->start();
}

bool InstallerBackend::run(const QString &stages, const QVariantMap &options)
{
    if (m_process)
        return false;
    QStringList args{QStringLiteral("-NoProfile"), QStringLiteral("-ExecutionPolicy"), QStringLiteral("Bypass"),
                     QStringLiteral("-File"), m_root + QStringLiteral("/tools/pipeline/build.ps1"),
                     QStringLiteral("-Game"), m_game, QStringLiteral("-Stages"), stages};
    // no -BuildRoot: build.ps1 picks this copy's build folder and records it in data/build-root.txt
    const QStringList isos = options.value(QStringLiteral("isos")).toStringList();
    if (!isos.isEmpty())
        args << QStringLiteral("-Discs") << isos.join(QLatin1Char('|'));
    const QString config = options.value(QStringLiteral("config"), QStringLiteral("Release")).toString();
    args << QStringLiteral("-Config") << config;
    if (options.value(QStringLiteral("ltcg")).toBool())
        args << QStringLiteral("-Ltcg");
    m_process = new QProcess(this);
    m_process->setProgram(QStringLiteral("powershell.exe"));
    m_process->setArguments(args);
    m_process->setWorkingDirectory(m_root);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_process, &QProcess::readyReadStandardOutput, this, &InstallerBackend::readOutput);
    connect(m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status)
    {
        readOutput();
        if (!m_pending.isEmpty())
            emit logLine(QString::fromLocal8Bit(m_pending));
        m_pending.clear();
        m_process->deleteLater();
        m_process = nullptr;
        emit runningChanged();
        emit finished(status == QProcess::NormalExit && code == 0, code);
    });
    m_process->start();
    emit runningChanged();
    return true;
}

void InstallerBackend::readOutput()
{
    if (!m_process)
        return;
    m_pending += m_process->readAllStandardOutput();
    qsizetype nl;
    while ((nl = m_pending.indexOf('\n')) >= 0)
    {
        QString line = QString::fromLocal8Bit(m_pending.left(nl)).trimmed();
        m_pending.remove(0, nl + 1);
        if (line.isEmpty())
            continue;
        if (line.startsWith(QStringLiteral("@@progress ")))
        {
            const QStringList f = line.mid(11).split(QLatin1Char(' '));
            if (f.size() == 2)
                emit progress(f[0].toInt(), f[1].toInt());
        }
        else if (line.startsWith(QStringLiteral("@@status ")))
            emit statusText(line.mid(9));
        else if (line.startsWith(QStringLiteral("=== ")) && line.endsWith(QStringLiteral(" ===")))
            emit stepChanged(line.mid(4, line.size() - 8));
        else
            emit logLine(line);
    }
}

void InstallerBackend::cancel()
{
    if (!m_process)
        return;
    // the pipeline starts compilers and the game: end the whole process tree
    QProcess::execute(QStringLiteral("taskkill"), {QStringLiteral("/T"), QStringLiteral("/F"), QStringLiteral("/PID"),
                                                   QString::number(m_process->processId())});
}

void InstallerBackend::openRequirementPage(const QString &which) const
{
    static const QVariantMap pages{
        {QStringLiteral("buildTools"), QStringLiteral("https://visualstudio.microsoft.com/visual-cpp-build-tools/")},
        {QStringLiteral("git"), QStringLiteral("https://git-scm.com/download/win")},
        {QStringLiteral("python"), QStringLiteral("https://www.python.org/downloads/windows/")},
    };
    QDesktopServices::openUrl(QUrl(pages.value(which).toString()));
}
