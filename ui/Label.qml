import QtQuick
import qs.Commons
import qs.Commons as Commons

Text {
    color: Commons.Color.popups.text
    font.family: Qt.application.font.family
    font.pixelSize: Style.font.body
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    elide: Text.ElideRight
}
