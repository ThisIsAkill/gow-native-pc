import QtQuick
import QtQuick.Controls

// On/off switch: a crimson pill with a white knob when active.
Switch {
    id: raiz
    hoverEnabled: true
    padding: 0
    implicitWidth: 46
    implicitHeight: 24
    anchors.right: parent ? parent.right : undefined

    indicator: Rectangle {
        implicitWidth: 46
        implicitHeight: 24
        radius: 12
        color: raiz.checked ? Tema.oro : Tema.campo
        border.width: 1
        border.color: raiz.checked ? Tema.oro : (raiz.hovered ? Tema.bordeClaro : Tema.borde)
        Behavior on color { ColorAnimation { duration: 140 } }
        Rectangle {
            width: 18
            height: 18
            radius: 9
            y: 3
            x: raiz.checked ? parent.width - width - 3 : 3
            color: raiz.checked ? "white" : Tema.textoSuave
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }
    contentItem: Item {}
}
