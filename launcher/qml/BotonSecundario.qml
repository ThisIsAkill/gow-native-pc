import QtQuick
import QtQuick.Controls

// Secondary button: graphite fill with a light border, the accent on hover.
Button {
    id: raiz
    property bool peligro: false
    implicitHeight: 36
    implicitWidth: Math.max(88, etiqueta.implicitWidth + 30)
    hoverEnabled: true

    contentItem: Text {
        id: etiqueta
        text: raiz.text
        color: raiz.peligro ? (raiz.hovered ? "white" : Tema.mal) : (raiz.hovered ? "white" : Tema.texto)
        font.pixelSize: 14
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    background: Rectangle {
        radius: 6
        border.width: 1
        border.color: raiz.hovered ? (raiz.peligro ? Tema.mal : Tema.oro) : Tema.bordeClaro
        color: raiz.pressed ? Tema.oroOscuro : raiz.hovered ? (raiz.peligro ? "#5a1812" : "#3a1714") : Tema.panelClaro
        opacity: raiz.enabled ? 1.0 : 0.4
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }
}
