import QtQuick
import QtQuick.Controls as C
import QtQuick.Layouts
import qs.Commons
import qs.Ui as UI
import "../Model.js" as Model

RowLayout {
    id: root
    required property var service
    required property string view
    property string fontFamily: service.fontFamily
    readonly property var folder: service.viewOptions(view).folder
    readonly property var nodes: Model.folderTree(service.projects)
    readonly property var selected: Model.folderValues(service.projects, folder)
    readonly property bool popupOpen: popup.opened
    readonly property Item rows: list
    readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
    function toggle(id) { service.setOption(view, "folder", Model.toggleFolder(service.projects, folder, id)); }
    function open() { popup.open(); }
    function close() { popup.close(); }
    Label { font.family: root.fontFamily; text: "Folder"; Layout.preferredWidth: Style.space(80) }
    // Same trigger and popup chrome as Omarchy's Dropdown. A checklist needs more than it offers,
    // and MultiSelect embeds a Qt text field, which this plugin never uses.
    Item {
        id: picker
        Layout.fillWidth: true
        implicitHeight: Style.spacing.controlHeight
        UI.BorderSurface {
            id: trigger
            objectName: "folderTrigger"
            anchors.fill: parent
            radius: Style.cornerRadius
            activeFocusOnTab: true
            color: Style.controlFill(trigger.activeFocus, hover.hovered, Color.popups.text, Color.accent)
            borderSpec: Border.controlSpec(trigger.activeFocus ? "focus" : hover.hovered ? "hover-cursor" : "normal", Color.popups.text, Color.accent)
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
                    popup.opened ? popup.close() : popup.open();
                    event.accepted = true;
                }
            }
            HoverHandler { id: hover }
            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: chevron.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
                anchors.rightMargin: trigger.borderRight + Style.spacing.md
                text: Model.folderSummary(root.service.projects, root.folder)
                color: Color.popups.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
            }
            Text {
                id: chevron
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
                text: "󰅀"
                color: Qt.darker(Color.popups.text, 1.2)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { trigger.forceActiveFocus(); popup.opened ? popup.close() : popup.open(); }
            }
            C.Popup {
                id: popup
                objectName: "folderPopup"
                x: 0
                y: trigger.height + Style.spacing.xxs
                width: trigger.width
                implicitHeight: Math.min(list.contentHeight, Style.spacing.popupRowHeight * 8 + 7 * Style.spacing.labelGap) + topPadding + bottomPadding
                padding: Style.spacing.hairline
                topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
                bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
                focus: true
                background: UI.BorderSurface { color: Color.popups.background; borderSpec: root.popupBorderSpec; radius: Style.cornerRadius }
                onOpened: { list.currentIndex = -1; list.forceActiveFocus(); }
                contentItem: ListView {
                    id: list
                    objectName: "folderList"
                    spacing: Style.spacing.labelGap
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.nodes
                    currentIndex: -1
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true; }
                        else if (event.key === Qt.Key_Down || event.text === "j") { currentIndex = Math.min(count - 1, currentIndex + 1); event.accepted = true; }
                        else if (event.key === Qt.Key_Up || event.text === "k") { currentIndex = Math.max(0, currentIndex - 1); event.accepted = true; }
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { if (currentIndex >= 0) root.toggle(root.nodes[currentIndex].id); event.accepted = true; }
                    }
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property string state: Model.folderState(root.service.projects, root.folder, modelData.id)
                        readonly property bool checked: state === "checked"
                        readonly property bool partial: state === "partial"
                        objectName: "folderRow_" + modelData.id
                        width: list.width
                        height: Style.spacing.popupRowHeight
                        color: index === list.currentIndex ? Style.hoverFillFor(Color.popups.text, Color.accent) : checked ? Style.selectedFillFor(Color.popups.text, Color.accent) : "transparent"
                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Style.spacing.controlPaddingX + row.modelData.depth * Style.space(14)
                            anchors.rightMargin: Style.spacing.controlPaddingX
                            spacing: Style.spacing.rowGap
                            UI.BorderSurface {
                                id: box
                                width: Style.space(16)
                                height: width
                                radius: Math.max(2, Style.cornerRadius / 2)
                                anchors.verticalCenter: parent.verticalCenter
                                color: row.checked || row.partial ? Style.selectedFillFor(Color.popups.text, Color.accent) : "transparent"
                                borderSpec: Border.controlSpec(row.checked || row.partial ? "selected" : "normal", Color.popups.text, Color.accent)
                                Text {
                                    anchors.centerIn: parent
                                    visible: row.checked || row.partial
                                    text: row.partial ? "−" : "✓"
                                    color: Style.selectedStateColor(Color.popups.text, Color.accent)
                                    font.family: root.fontFamily
                                    font.pixelSize: Math.round(box.height * 0.85)
                                    font.bold: true
                                }
                            }
                            Text {
                                textFormat: Text.PlainText
                                width: parent.width - box.width - parent.spacing
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.name
                                color: row.index === list.currentIndex ? Style.hoverStateColor(Color.popups.text, Color.accent) : Color.popups.text
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: row.checked || row.partial
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: list.currentIndex = row.index
                            onClicked: root.toggle(row.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
