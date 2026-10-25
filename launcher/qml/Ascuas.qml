import QtQuick
import QtQuick.Particles

// Ash drifting down from the top, with a few embers rising from the bottom.
Item {
    id: raiz
    property bool activas: true
    property real intensidad: 1.0

    ParticleSystem {
        id: sistema
        running: raiz.activas && raiz.visible
    }

    ImageParticle {
        system: sistema
        groups: ["ceniza"]
        source: "qrc:///particleresources/fuzzydot.png"
        color: "#c9ccd2"
        alpha: 0.16
        alphaVariation: 0.12
        entryEffect: ImageParticle.Fade
        rotationVariation: 180
    }

    ImageParticle {
        system: sistema
        groups: ["brasa"]
        source: "qrc:///particleresources/glowdot.png"
        color: "#ff5a3a"
        alpha: 0.8
        entryEffect: ImageParticle.Fade
    }

    Emitter {
        system: sistema
        group: "ceniza"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 20
        emitRate: 6 * raiz.intensidad
        lifeSpan: 14000
        lifeSpanVariation: 4000
        size: 4
        sizeVariation: 2
        endSize: 2
        velocity: AngleDirection {
            angle: 100
            angleVariation: 20
            magnitude: 26
            magnitudeVariation: 14
        }
    }

    Emitter {
        system: sistema
        group: "brasa"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 10
        emitRate: 3 * raiz.intensidad
        lifeSpan: 5000
        lifeSpanVariation: 1500
        size: 5
        sizeVariation: 2
        endSize: 1
        velocity: AngleDirection {
            angle: 270
            angleVariation: 20
            magnitude: 55
            magnitudeVariation: 25
        }
    }

    Wander {
        system: sistema
        xVariance: 60
        pace: 20
    }
}
