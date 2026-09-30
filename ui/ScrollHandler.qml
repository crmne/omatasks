import QtQuick

WheelHandler {
    id: root
    required property Flickable flickable
    parent: flickable
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) {
        // Wayland touchpads provide small pixel deltas; mouse wheels use angles.
        var delta = event.pixelDelta.x || event.pixelDelta.y ? event.pixelDelta.y * 3 : event.angleDelta.y / 120 * Qt.styleHints.wheelScrollLines * 24;
        if (!delta) return;
        flickable.cancelFlick();
        flickable.contentY = Math.max(flickable.originY, Math.min(flickable.originY + Math.max(0, flickable.contentHeight - flickable.height), flickable.contentY - delta));
        event.accepted = true;
    }
}
