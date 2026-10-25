pragma Singleton
import QtQuick
import "Textos.js" as Textos

// Interface colours, fonts and language. t(clave) (key) is re-evaluated when "idioma" (language) changes.
// gow-native-pc look ("ash and blood"): cold graphite surfaces, ash-white text and one crimson accent, after
// Kratos' ash skin and red tattoo. The oro* names are kept from the Tobiichi Launcher so its pages stay diffable;
// here they hold the accent colour, not gold.
QtObject {
    property string idioma: "en"
    property string fuenteTitulo: Qt.application.font.family
    readonly property string fuenteCuerpo: Qt.application.font.family
    // Icon glyphs (Segoe MDL2 Assets, part of Windows 10/11); elsewhere the icons are hidden.
    readonly property string fuenteIconos: "Segoe MDL2 Assets"
    readonly property bool hayIconos: Qt.platform.os === "windows"

    readonly property color fondo: "#0b0c0f"
    readonly property color fondoAlto: "#14161b"
    readonly property color lateral: "#0f1014"
    readonly property color panel: "#d9121419"
    readonly property color panelClaro: "#1c1f26"
    readonly property color campo: "#15171c"
    readonly property color borde: "#252932"
    readonly property color bordeClaro: "#3a404c"
    readonly property color oro: "#e0402f"
    readonly property color oroClaro: "#ff8a75"
    readonly property color oroOscuro: "#7a1a12"
    readonly property color rojo: "#c62a20"
    readonly property color rojoClaro: "#ff4a36"
    readonly property color rojoOscuro: "#4a0d09"
    readonly property color texto: "#eef0f4"
    readonly property color textoSuave: "#a9afba"
    readonly property color textoTenue: "#6a707c"
    readonly property color bien: "#5fd08a"
    readonly property color aviso: "#f0b44a"
    readonly property color mal: "#ff6450"

    function t(clave) {
        return Textos.texto(clave, idioma)
    }
    // t with %1, %2... substituted.
    function tf(clave, a, b) {
        var s = t(clave)
        if (a !== undefined) s = s.replace("%1", a)
        if (b !== undefined) s = s.replace("%2", b)
        return s
    }
    function duracion(segundos) {
        var h = Math.floor(segundos / 3600)
        var m = Math.floor((segundos % 3600) / 60)
        if (h > 0) return tf("horasMinutos", h, m)
        if (m > 0) return tf("minutos", m)
        return tf("segundos", segundos)
    }
}
