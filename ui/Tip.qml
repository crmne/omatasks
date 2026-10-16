import QtQuick
import QtQuick.Controls as C
import qs.Commons
import qs.Commons as Commons

C.ToolTip {
    id: root
    property string fontFamily: Qt.application.font.family
    delay: 600
    padding: Style.space(10)
    // ToolTip centers using implicitWidth, so constrain that too; otherwise
    // long unwrapped text offsets the popup even though its visible width fits.
    // Use the text layout's full width; glyph bounds can omit trailing space
    // needed by the final character. Round up to avoid fractional-pixel wrapping.
    implicitWidth: Math.min(Style.space(340), Math.ceil(preview.implicitWidth) + leftPadding + rightPadding)
    background: Rectangle { color: Commons.Color.tooltip.background; border.color: Commons.Color.tooltip.border; border.width: 1; radius: Style.cornerRadius }
    contentItem: Text {
        id: preview
        text: root.text; textFormat: Text.PlainText
        color: Commons.Color.tooltip.text
        font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap; maximumLineCount: 8; elide: Text.ElideRight
    }
}
