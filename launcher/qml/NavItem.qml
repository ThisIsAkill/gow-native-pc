import QtQuick
import QtQuick.Controls

// Sidebar entry: icon glyph and label; the active one gets a crimson bar on the left and a lighter fill.
AbstractButton {
    id: root
    property string glyph: ""   // Segoe MDL2 Assets code point
    property bool active: false
    implicitHeight: 44
    hoverEnabled: true

    background: Rectangle {
        radius: 6
        color: root.active ? Tema.panelClaro : (root.hovered ? "#14ffffff" : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            visible: root.active
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height - 16
            radius: 2
            color: Tema.oro
        }
    }

    contentItem: Row {
        leftPadding: 16
        spacing: 14
        Text {
            visible: Tema.hayIconos
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            text: root.glyph
            font.family: Tema.fuenteIconos
            font.pixelSize: 16
            color: root.active ? Tema.oroClaro : (root.hovered ? Tema.texto : Tema.textoTenue)
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: 14
            font.weight: root.active ? Font.DemiBold : Font.Normal
            color: root.active ? "white" : (root.hovered ? Tema.texto : Tema.textoSuave)
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }
}
