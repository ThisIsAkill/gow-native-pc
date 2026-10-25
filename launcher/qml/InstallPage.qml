import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

// Install tab: requirements, the runtime (PS2Recomp + Tobiichi, downloaded), the game discs (one or more ISOs, their
// language detected) and the build with live progress. Backed by "installer" (src/installer_backend.cpp), which runs
// tools/pipeline/build.ps1.
ScrollView {
    id: root
    contentWidth: availableWidth
    clip: true

    property var env: installer.environment()
    property var discs: []          // identified ISOs: [{path, label, language, kind, compatible, problems}]
    property var languages: installer.languages()
    property string step: ""
    property string status: ""
    property int done: 0
    property int total: 0
    property var log: []
    property bool optimize: true   // the first build records and compiles the native code

    function refresh() {
        env = installer.environment()
        languages = installer.languages()
    }
    function compatibleIsos() {
        var out = []
        for (var i = 0; i < discs.length; ++i)
            if (discs[i].compatible) out.push(discs[i].path)
        return out
    }
    function addLog(line) {
        var l = log.slice(-300)
        l.push(line)
        log = l
    }
    function startBuild(full) {
        log = []; done = 0; total = 0; status = ""
        var stages = full ? "fetch,discs,configure,recomp,sync,build" : "sync,build"
        if (full && compatibleIsos().length === 0 && languages.length > 0)
            stages = "fetch,configure,recomp,sync,build"
        if (optimize) stages += ",optimize"
        installer.run(stages, { isos: compatibleIsos(), config: "Release" })
    }

    Connections {
        target: installer
        function onIdentified(list) {
            var merged = root.discs.slice()
            for (var i = 0; i < list.length; ++i) {
                var dup = false
                for (var j = 0; j < merged.length; ++j) if (merged[j].path === list[i].path) dup = true
                if (!dup) merged.push(list[i])
            }
            root.discs = merged
        }
        function onStepChanged(s) { root.step = s; root.status = ""; root.done = 0; root.total = 0; root.addLog("— " + s) }
        function onProgress(d, t) { root.done = d; root.total = t }
        function onStatusText(t) { root.status = t }
        function onLogLine(l) { root.addLog(l) }
        function onFinished(ok, code) {
            root.step = ok ? Tema.t("instDone") : Tema.tf("instFailed", code)
            root.refresh()
        }
    }

    FileDialog {
        id: isoDialog
        title: Tema.t("instPickIso")
        fileMode: FileDialog.OpenFiles
        nameFilters: ["ISO (*.iso *.ISO)", "* (*)"]
        onAccepted: {
            var paths = []
            for (var i = 0; i < selectedFiles.length; ++i) paths.push(lanzador.rutaDesdeUrl(selectedFiles[i]))
            installer.identify(paths)
        }
    }

    ColumnLayout {
        width: root.availableWidth
        spacing: 18

        // ---------------------------------------------------------------- requirements
        Text { text: Tema.t("instRequirements"); color: Tema.oroClaro; font.pixelSize: 16; font.weight: Font.Medium }
        Repeater {
            model: [
                { key: "buildTools", label: Tema.t("instBuildTools") },
                { key: "git", label: "Git" },
                { key: "python", label: "Python 3" }
            ]
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: (root.env[modelData.key] ? "✔  " : "✖  ") + modelData.label
                    color: root.env[modelData.key] ? Tema.bien : Tema.mal
                    font.pixelSize: 14
                    Layout.fillWidth: true
                }
                BotonSecundario {
                    visible: !root.env[modelData.key]
                    text: Tema.t("instDownload")
                    onClicked: installer.openRequirementPage(modelData.key)
                }
            }
        }

        // ---------------------------------------------------------------- runtime
        Text { text: Tema.t("instRuntime"); color: Tema.oroClaro; font.pixelSize: 16; font.weight: Font.Medium }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Tema.textoSuave
            font.pixelSize: 13
            text: Tema.t("instRuntimeDesc")
        }
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.env.runtime ? "✔  " + Tema.t("instRuntimeOk") : "✖  " + Tema.t("instRuntimeMissing")
                color: root.env.runtime ? Tema.bien : Tema.aviso
                font.pixelSize: 14
                Layout.fillWidth: true
            }
            BotonSecundario {
                text: root.env.runtime ? Tema.t("instRuntimeUpdate") : Tema.t("instRuntimeGet")
                enabled: !installer.running && root.env.git
                onClicked: { root.log = []; installer.run("fetch", {}) }
            }
        }

        // ---------------------------------------------------------------- discs
        Text { text: Tema.t("instDiscs"); color: Tema.oroClaro; font.pixelSize: 16; font.weight: Font.Medium }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Tema.textoSuave
            font.pixelSize: 13
            text: Tema.t("instDiscsDesc")
        }
        Repeater {
            model: root.discs
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: (modelData.compatible ? "✔  " : "✖  ") + (modelData.label || modelData.path)
                    color: modelData.compatible ? Tema.bien : Tema.mal
                    font.pixelSize: 14
                }
                Text {
                    text: modelData.path + (modelData.problems && modelData.problems.length ? " — " + modelData.problems.join("; ") : "")
                    color: Tema.textoTenue
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
            }
        }
        Repeater {
            model: root.languages
            delegate: Text {
                required property var modelData
                text: "●  " + modelData.label + "  (" + Tema.t("instQuality_" + modelData.quality) + ")"
                color: Tema.texto
                font.pixelSize: 13
            }
        }
        RowLayout {
            spacing: 10
            BotonSecundario { text: Tema.t("instAddIso"); enabled: !installer.running; onClicked: isoDialog.open() }
            BotonSecundario {
                text: Tema.t("instClearIso")
                visible: root.discs.length > 0
                enabled: !installer.running
                onClicked: root.discs = []
            }
        }

        // ---------------------------------------------------------------- build
        Text { text: Tema.t("instBuild"); color: Tema.oroClaro; font.pixelSize: 16; font.weight: Font.Medium }
        Fila {
            titulo: Tema.t("instOptimize")
            descripcion: Tema.t("instOptimizeDesc")
            Interruptor { checked: root.optimize; onToggled: root.optimize = checked }
        }
        RowLayout {
            spacing: 10
            BotonSecundario {
                text: root.env.game ? Tema.t("instRebuildAll") : Tema.t("instInstall")
                enabled: !installer.running && root.env.buildTools && root.env.git && root.env.python
                         && (root.compatibleIsos().length > 0 || root.languages.length > 0)
                onClicked: root.startBuild(true)
            }
            BotonSecundario {
                text: Tema.t("instQuick")
                visible: root.env.game
                enabled: !installer.running
                onClicked: root.startBuild(false)
            }
            BotonSecundario {
                text: Tema.t("instNative")
                visible: root.env.game
                enabled: !installer.running
                onClicked: { root.log = []; installer.run("native", { config: "Release" }) }
            }
            BotonSecundario {
                text: Tema.t("instCancel")
                peligro: true
                visible: installer.running
                onClicked: installer.cancel()
            }
        }
        Text {
            visible: root.step.length > 0
            text: root.step + (root.total > 0 ? "  —  " + Math.round(100 * root.done / root.total) + "%" : "")
                  + (root.status.length > 0 ? "  —  " + root.status : "")
            color: Tema.texto
            font.pixelSize: 14
        }
        Rectangle {
            id: trilho
            visible: installer.running || root.total > 0
            Layout.fillWidth: true
            height: 8
            radius: 4
            color: Tema.campo
            border.color: Tema.borde
            clip: true
            // Step with a count: the bar grows from the left edge.
            Rectangle {
                visible: root.total > 0
                x: 0
                width: root.total > 0 ? trilho.width * Math.min(1, root.done / root.total) : 0
                height: parent.height
                radius: 4
                color: Tema.oro
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
            // Step without a count yet: a block sweeping back and forth (its own item, so the bar above always
            // starts at the left edge once the percentages arrive).
            Rectangle {
                id: varredura
                visible: installer.running && root.total === 0
                width: trilho.width * 0.25
                height: parent.height
                radius: 4
                color: Tema.oro
                opacity: 0.8
                SequentialAnimation on x {
                    running: varredura.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: trilho.width - varredura.width; duration: 1200; easing.type: Easing.InOutSine }
                    NumberAnimation { from: trilho.width - varredura.width; to: 0; duration: 1200; easing.type: Easing.InOutSine }
                }
            }
        }
        Rectangle {
            visible: root.log.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            color: Tema.campo
            border.color: Tema.borde
            radius: 4
            ListView {
                id: logView
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                model: root.log
                onCountChanged: positionViewAtEnd()
                delegate: Text {
                    required property var modelData
                    width: logView.width
                    text: modelData
                    color: Tema.textoSuave
                    font.family: "Consolas"
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
        Item { Layout.preferredHeight: 12 }
    }
}
