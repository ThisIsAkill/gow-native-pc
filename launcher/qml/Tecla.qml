import QtQuick

// A key drawn like a keyboard keycap.
Rectangle {
    id: raiz
    property string texto
    implicitWidth: Math.max(30, etiqueta.implicitWidth + 16)
    implicitHeight: 28
    radius: 4
    border.width: 1
    border.color: Tema.bordeClaro
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#262a32" }
        GradientStop { position: 1.0; color: "#181b21" }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 3
        radius: 3
        color: "#08090b"
    }
    Text {
        id: etiqueta
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -1
        text: raiz.texto
        color: Tema.oroClaro
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }
}
