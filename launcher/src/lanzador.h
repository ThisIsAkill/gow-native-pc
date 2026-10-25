#pragma once

// Play side of the launcher (from the Tobiichi Launcher): detects graphics cards, the display and the game files, and
// starts ps2EntryRunner with the environment variables matching the settings chosen in the interface (QML).

#include <QElapsedTimer>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

class Lanzador : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool jugando READ jugando NOTIFY jugandoCambiado)
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(QString sistema READ sistema CONSTANT)
    Q_PROPERTY(QString carpetaDatos READ carpetaDatos CONSTANT)
    Q_PROPERTY(QString rutaIcono READ rutaIcono CONSTANT)

public:
    explicit Lanzador(QObject *parent = nullptr);
    ~Lanzador() override;

    bool jugando() const;
    QString version() const;
    QString sistema() const;
    QString carpetaDatos() const;
    QString rutaIcono() const;

    // Graphics cards: [{id, nombre, fabricante, tipo ("integrada"/"dedicada"), predeterminada}] (name, vendor, type, default).
    Q_INVOKABLE QVariantList tarjetasGraficas() const;
    // Main display in physical pixels: {ancho, alto, hz} (width, height, refresh).
    Q_INVOKABLE QVariantMap pantalla() const;
    // Paths found next to the launcher or in the repository folder: {elf, iso, ejecutable}.
    Q_INVOKABLE QVariantMap rutasDetectadas() const;
    // {existe, valido, crc, titulo}: valido (valid) when it is the God of War ELF (NTSC-U, SCUS-97399).
    Q_INVOKABLE QVariantMap comprobarJuego(const QString &elf) const;
    // {ok, iso, extraidos}: the disc image used (the chosen one or the one the game would look for) or extracted files.
    Q_INVOKABLE QVariantMap comprobarDatos(const QString &elf, const QString &iso) const;
    // {existe, ejecutable} (exists, executable)
    Q_INVOKABLE QVariantMap comprobarEjecutable(const QString &ruta) const;
    Q_INVOKABLE QString carpetaMemoria(const QString &elf) const;
    Q_INVOKABLE QString rutaDesdeUrl(const QUrl &url) const;
    Q_INVOKABLE QUrl urlDesdeRuta(const QString &ruta) const;

    Q_INVOKABLE bool iniciar(const QVariantMap &ajustes);
    Q_INVOKABLE void detener();
    Q_INVOKABLE void abrirCarpeta(const QString &ruta) const;
    Q_INVOKABLE void abrirRegistro() const;
    // Application menu entry (and, when asked, a desktop shortcut).
    Q_INVOKABLE bool crearAccesoDirecto(bool escritorio) const;
    // Cover image chosen by the user: copied into the data folder (independent of the original); returns the
    // path of the copy, or empty when it is not a readable image.
    Q_INVOKABLE QString guardarPortada(const QString &origen) const;
    Q_INVOKABLE void borrarPortada() const;
    // true when the image is a cut-out (figure on a transparent background): its border is almost all transparent.
    Q_INVOKABLE bool esRecorte(const QString &ruta) const;

signals:
    void jugandoCambiado();
    void juegoTerminado(int codigo, bool fallo, int segundos, const QString &resumen);
    void error(const QString &clave, const QString &detalle);

private:
    QString rutaRegistro() const;
    void aplicarTarjeta(QProcessEnvironment &entorno, const QString &id, const QString &ejecutable) const;
    void terminado(int codigo, QProcess::ExitStatus estado);

    QProcess *m_proceso = nullptr;
    QElapsedTimer m_reloj;
};
