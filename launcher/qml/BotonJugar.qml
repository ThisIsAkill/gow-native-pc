import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes

// Main button: a crimson blade with the top-right corner cut, a play triangle and a soft breathing glow when the
// game is ready; dark outline while the game runs.
Button {
    id: raiz
    property bool jugando: false
    property bool listo: true
    readonly property real corte: 18
    implicitWidth: 300
    implicitHeight: 64
    hoverEnabled: true
    enabled: listo || jugando

    contentItem: Item {
        Row {
            anchors.centerIn: parent
            spacing: 16
            Shape {
                // Play triangle (a pulsing dot while playing).
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 18
                visible: !raiz.jugando
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: raiz.enabled ? "white" : "#80ffffff"
                    startX: 0; startY: 0
                    PathLine { x: 16; y: 9 }
                    PathLine { x: 0; y: 18 }
                    PathLine { x: 0; y: 0 }
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: raiz.jugando
                width: 10
                height: 10
                radius: 5
                color: Tema.bien
                SequentialAnimation on opacity {
                    running: raiz.jugando
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700 }
                    NumberAnimation { to: 1.0; duration: 700 }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: raiz.text
                font.family: Tema.fuenteTitulo
                font.pixelSize: raiz.jugando ? 18 : 24
                font.weight: Font.Black
                font.letterSpacing: raiz.jugando ? 3 : 6
                color: raiz.jugando ? Tema.texto : (raiz.enabled ? "white" : "#90ffffff")
            }
        }
    }

    background: Item {
        Rectangle {
            // Glow behind the button.
            id: brillo
            anchors.fill: parent
            anchors.margins: 6
            visible: !raiz.jugando && raiz.enabled
            color: Tema.rojoClaro
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 40
                blur: 1.0
            }
            SequentialAnimation on opacity {
                running: brillo.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0.25; to: 0.6; duration: 1800; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.6; to: 0.25; duration: 1800; easing.type: Easing.InOutSine }
            }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: raiz.jugando ? 1 : 0
                strokeColor: raiz.jugando ? Tema.bordeClaro : "transparent"
                fillGradient: LinearGradient {
                    x1: 0; y1: 0
                    x2: raiz.width; y2: raiz.height
                    GradientStop { position: 0.0; color: raiz.jugando ? Tema.panelClaro : (!raiz.enabled ? "#2a2c32" : raiz.pressed ? "#a3211a" : raiz.hovered ? "#ff4a36" : "#e0352a") }
                    GradientStop { position: 1.0; color: raiz.jugando ? Tema.campo : (!raiz.enabled ? "#1d1f24" : raiz.pressed ? "#6e140f" : raiz.hovered ? "#c42619" : "#a51d15") }
                }
                startX: 0; startY: 0
                PathLine { x: raiz.width - raiz.corte; y: 0 }
                PathLine { x: raiz.width; y: raiz.corte }
                PathLine { x: raiz.width; y: raiz.height }
                PathLine { x: 0; y: raiz.height }
                PathLine { x: 0; y: 0 }
            }
        }
        Rectangle {
            // Thin ash-white line along the bottom edge.
            visible: !raiz.jugando && raiz.enabled
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            color: "#40ffffff"
        }
    }

    scale: pressed ? 0.985 : 1.0
    Behavior on scale { NumberAnimation { duration: 90 } }
}
