import QtQuick

WheelHandler {
    id: root
    required property Flickable flickable
    parent: flickable
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    property real targetY: NaN
    onWheel: function(event) {
        // Wayland touchpads provide small pixel deltas; mouse wheels use angles.
        var delta = event.pixelDelta.x || event.pixelDelta.y ? event.pixelDelta.y * 3 : event.angleDelta.y / 120 * Qt.styleHints.wheelScrollLines * 24;
        if (!delta) return;
        // Accumulate input ahead of the animation; reverse direction immediately.
        if (!flickable.flickingVertically || !isFinite(targetY) || (targetY - flickable.contentY) * delta > 0) targetY = flickable.contentY;
        targetY = Math.max(flickable.originY, Math.min(flickable.originY + Math.max(0, flickable.contentHeight - flickable.height), targetY - delta));
        var distance = targetY - flickable.contentY;
        // Native flicking supplies smooth motion and activates attached scrollbars.
        if (distance) flickable.flick(0, (distance > 0 ? -1 : 1) * Math.sqrt(2 * flickable.flickDeceleration * Math.abs(distance)));
        event.accepted = true;
    }
    property Connections movement: Connections {
        target: root.flickable
        function onMovementEnded() { root.targetY = NaN; }
        function onDraggingChanged() { root.targetY = NaN; }
    }
}
