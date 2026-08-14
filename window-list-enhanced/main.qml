/*
    SPDX-FileCopyrightText: 2016 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2022 Carson Black <uhhadd@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    property string lastActiveTaskName: ""
    property /*QIcon*/ var lastActiveTaskIcon: ""
    readonly property int listOrderUngrouped: 0
    readonly property int listOrderSortByApp: 1
    readonly property int listOrderSortByAppDesc: 2
    readonly property int listOrderCustom: 3
    readonly property bool usingCustomOrder: Plasmoid.configuration.windowListOrder === root.listOrderCustom

    property ListModel customTasksModel: ListModel {}

    Plasmoid.constraintHints: Plasmoid.CanFillArea
    compactRepresentation: windowListButton
    fullRepresentation: windowList
    switchWidth: Kirigami.Units.gridUnit * 8
    switchHeight: Kirigami.Units.gridUnit * 6

    readonly property bool inPanel: [
        PlasmaCore.Types.TopEdge,
        PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge,
        PlasmaCore.Types.LeftEdge,
    ].includes(Plasmoid.location)

    TextMetrics {
        id: placeholderMetrics
        font: Kirigami.Theme.defaultFont 
        text: i18nc("@info:placeholder", "No open windows")
    }

    property ListModel noWindowModel: ListModel {
        ListElement {
            display: ""
            decoration: "edit-none"
        }

        Component.onCompleted: {
            noWindowModel.setProperty(0, "display", placeholderMetrics.text)
        }
    }

    TaskManager.VirtualDesktopInfo {
        id: virtualDesktopInfo
    }

    TaskManager.ActivityInfo {
        id: activityInfo
        readonly property string nullUuid: "00000000-0000-0000-0000-000000000000"
    }

    TaskManager.TasksModel {
        id: tasksModel

        screenGeometry: Plasmoid.containment.screenGeometry
        activity: activityInfo.currentActivity

        sortMode: (Plasmoid.configuration.windowListOrder === root.listOrderSortByApp
            || Plasmoid.configuration.windowListOrder === root.listOrderSortByAppDesc)
            ? TaskManager.TasksModel.SortAlpha
            : TaskManager.TasksModel.SortDisabled
        groupMode: TaskManager.TasksModel.GroupDisabled

        filterByVirtualDesktop: Plasmoid.configuration.showOnlyCurrentDesktop
        filterByScreen: Plasmoid.configuration.showOnlyCurrentScreen
        filterByActivity: Plasmoid.configuration.showOnlyCurrentActivity
        filterNotMinimized: Plasmoid.configuration.showOnlyMinimized

        Component.onCompleted: root.applyWindowListOrder()
    }

    property string longestWindowCaption: ""

    TextMetrics {
        id: longestTextMetrics
        elide: Text.ElideRight
    }

    property int fullRepresentationDynamicWidth: 0

    function formatWindowTitle(text) {
        const title = text || ""
        const maxTitleLength = Math.max(1, Number(Plasmoid.configuration.maxTitleLength || 50))

        if (Plasmoid.configuration.enableMaxTitleLength && title.length > maxTitleLength) {
            return title.slice(0, maxTitleLength) + "..."
        }

        return title
    }

    function taskKeyForSourceIndex(sourceIndex) {
        const idx = tasksModel.makeModelIndex(sourceIndex)
        const winIds = tasksModel.data(idx, TaskManager.AbstractTasksModel.WinIdList)

        if (winIds && winIds.length) {
            return "w:" + winIds.join(",")
        }

        const appPid = tasksModel.data(idx, TaskManager.AbstractTasksModel.AppPid)
        const appName = tasksModel.data(idx, TaskManager.AbstractTasksModel.AppName) || ""
        const title = tasksModel.data(idx, 0) || ""
        return "f:" + String(appPid) + ":" + appName + ":" + title
    }

    function parseSavedCustomOrder() {
        const raw = Plasmoid.configuration.customOrderKeys
        if (!raw || raw === "") {
            return []
        }

        try {
            const parsed = JSON.parse(raw)
            return Array.isArray(parsed) ? parsed : []
        } catch (e) {
            return []
        }
    }

    function persistCustomOrderFromModel() {
        const keys = []
        for (let i = 0; i < customTasksModel.count; ++i) {
            keys.push(customTasksModel.get(i).taskKey)
        }

        Plasmoid.configuration.customOrderKeys = JSON.stringify(keys)
    }

    function moveCustomTask(fromRow, toRow) {
        if (fromRow < 0 || toRow < 0 || fromRow === toRow || fromRow >= customTasksModel.count || toRow >= customTasksModel.count) {
            return
        }

        customTasksModel.move(fromRow, toRow, 1)
        persistCustomOrderFromModel()
    }

    function rebuildCustomTasksModel() {
        const items = []

        for (let i = 0; i < tasksModel.count; ++i) {
            const idx = tasksModel.makeModelIndex(i)
            const title = tasksModel.data(idx, 0) || tasksModel.data(idx, TaskManager.AbstractTasksModel.AppName) || ""

            items.push({
                sourceIndex: i,
                taskKey: taskKeyForSourceIndex(i),
                display: title,
                decoration: tasksModel.data(idx, 1 /* decoration role */),
            })
        }

        const savedOrder = parseSavedCustomOrder()
        const ordered = []
        const usedKeys = {}

        for (const key of savedOrder) {
            const match = items.find(item => item.taskKey === key && !usedKeys[item.taskKey])
            if (match) {
                ordered.push(match)
                usedKeys[match.taskKey] = true
            }
        }

        for (const item of items) {
            if (!usedKeys[item.taskKey]) {
                ordered.push(item)
                usedKeys[item.taskKey] = true
            }
        }

        customTasksModel.clear()
        for (const item of ordered) {
            customTasksModel.append(item)
        }

        persistCustomOrderFromModel()
    }

    function sourceIndexForDelegateItem(modelData) {
        if (usingCustomOrder) {
            return modelData.sourceIndex
        }

        return modelData.index
    }

    function isItemInTree(item, treeRoot) {
        let current = item
        while (current) {
            if (current === treeRoot) {
                return true
            }
            current = current.parent
        }

        return false
    }

    function updateLongestWindowTitle() {
        if (!tasksModel || !tasksModel.count) {
            longestWindowCaption = "";

            fullRepresentationDynamicWidth = Math.ceil(placeholderMetrics.width)
                                           + Kirigami.Units.iconSizes.sizeForLabels * 2 + Kirigami.Units.smallSpacing * 2;
            return;
        }

        let maxWidth = 0;
        let longest = "";
        const count = usingCustomOrder ? customTasksModel.count : tasksModel.count

        for (let i = 0; i < count; ++i) {
            if (usingCustomOrder) {
                longestTextMetrics.text = formatWindowTitle(customTasksModel.get(i).display)
            } else {
                let idx = tasksModel.makeModelIndex(i);
                longestTextMetrics.text = formatWindowTitle(tasksModel.data(idx, 0) || tasksModel.data(idx, TaskManager.AbstractTasksModel.AppName) || "");
            }
            
            if (longestTextMetrics.width > maxWidth) {
                maxWidth = longestTextMetrics.width;
                longest = longestTextMetrics.text;
            }
        }

        root.longestWindowCaption = longest;
        fullRepresentationDynamicWidth = Math.ceil(maxWidth) + Kirigami.Units.iconSizes.sizeForLabels * 2 + Kirigami.Units.smallSpacing * 2;
    }

    function applyWindowListOrder() {
        if (usingCustomOrder) {
            rebuildCustomTasksModel()
            return
        }

        if (Plasmoid.configuration.windowListOrder === root.listOrderSortByAppDesc) {
            tasksModel.sort(0, Qt.DescendingOrder)
        } else {
            tasksModel.sort(0, Qt.AscendingOrder)
        }
    }

    Connections {
        target: tasksModel
        function onModelReset() {
            updateLongestWindowTitle();
            root.applyWindowListOrder();
        }
        function onCountChanged() {
            root.applyWindowListOrder();
            root.updateLongestWindowTitle();
        }
    }

    Connections {
        target: Plasmoid.configuration
        function onWindowListOrderChanged() {
            root.applyWindowListOrder();
            root.updateLongestWindowTitle();
        }
        function onEnableMaxTitleLengthChanged() {
            root.updateLongestWindowTitle();
            if (root.usingCustomOrder) {
                root.rebuildCustomTasksModel();
            }
        }
        function onMaxTitleLengthChanged() {
            root.updateLongestWindowTitle();
            if (root.usingCustomOrder) {
                root.rebuildCustomTasksModel();
            }
        }
    }

    Component {
        id: windowList

        ListView {  
            id: windowListView
            property int maxDelegateWidth: 0
            
            clip: true


            // Set preferred size when on desktop containment. 
            // Size set arbitrarily to fit approximately 12-14 items.
            Binding {
                target: windowListView
                property: "Layout.preferredWidth"
                when: !inPanel
                value: Kirigami.Units.gridUnit * 28
            }

            Binding {
                target: windowListView
                property: "Layout.preferredHeight"
                when: !inPanel
                value: Kirigami.Units.gridUnit * 24
            }

            Binding {
                target: windowListView
                property: "Layout.maximumHeight"
                when: inPanel
                value: contentHeight
            }
            Binding {
                target: windowListView
                property: "Layout.minimumHeight"
                when: inPanel
                value: contentHeight
            }
            Binding {
                target: windowListView
                property: "Layout.maximumWidth"
                when: inPanel
                value: root.fullRepresentationDynamicWidth
            }
            Binding {
                target: windowListView
                property: "Layout.minimumWidth"
                when: inPanel
                value: root.fullRepresentationDynamicWidth
            }

            model: inPanel && tasksModel.count === 0 ? noWindowModel : (root.usingCustomOrder ? customTasksModel : tasksModel)
        
            Connections {
                target: root
                function onExpandedChanged(expanded) {
                    if (expanded) {
                        windowListView.currentIndex = -1

                        // Needed for when for expanded with Global Shortcut
                        if (tasksModel.activeTask.valid) {
                            root.lastActiveTaskName = tasksModel.data(tasksModel.activeTask, TaskManager.AbstractTasksModel.AppName) ||
                            tasksModel.data(tasksModel.activeTask, 0 /* display name, window title if app name not present */)
                            root.lastActiveTaskIcon = tasksModel.data(tasksModel.activeTask, 1 /* decorationrole */)
                        } else {
                            root.lastActiveTaskName = ""
                            root.lastActiveTaskIcon = ""
                        }

                        root.updateLongestWindowTitle();
                    }
                }
            }

            Connections {
                target: windowListView.Window.window
                function onActiveChanged() {
                    if (!root.expanded || !windowListView.Window.window) {
                        return
                    }

                    if (!windowListView.Window.window.active) {
                        root.expanded = false
                    }
                }
            }

            // focus is needed to receive key events on desktop containment works in panel without this.
            focus: true
            keyNavigationWraps: true

            highlight: PlasmaExtras.Highlight {
                visible: windowListView.currentItem
                active: windowListView.focus
                pressed: windowListView.currentItem && windowListView.currentItem.pressed
            }

            highlightMoveDuration: 0
            highlightResizeDuration: 0

            Keys.onEnterPressed: {
                if (currentIndex >= 0 && currentIndex < windowListView.count) {
                    const sourceIndex = root.sourceIndexForDelegateItem(windowListView.currentItem.model)
                    tasksModel.requestActivate(tasksModel.makeModelIndex(sourceIndex));
                }
            }

            Keys.onReturnPressed: {
                if (currentIndex >= 0 && currentIndex < windowListView.count) {
                    const sourceIndex = root.sourceIndexForDelegateItem(windowListView.currentItem.model)
                    tasksModel.requestActivate(tasksModel.makeModelIndex(sourceIndex));
                }
            }

            Keys.onTabPressed: {
                incrementCurrentIndex();
            }

            Keys.onBacktabPressed: {
                decrementCurrentIndex();
            }

            // Helps with performance otherwise scrolling is very laggy and stuttery
            // with low fps
            reuseItems: true

            delegate: PlasmaComponents.ItemDelegate {
                id: delegate

                required property var model
                required property var decoration
                readonly property bool hasSourceTask: !(inPanel && tasksModel.count === 0)
                readonly property int sourceIndex: root.sourceIndexForDelegateItem(model)

                width: {
                    if (inPanel) {
                        return root.fullRepresentationDynamicWidth 
                    } else {
                        return ListView.view.width;
                    }
                }
                
                highlighted: ListView.isCurrentItem

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        id: iconItem

                        source: delegate.hasSourceTask
                            ? tasksModel.data(tasksModel.makeModelIndex(delegate.sourceIndex), 1 /* decoration role */)
                            : delegate.decoration
                        visible: source !== "" && iconItem.valid

                        implicitWidth: Kirigami.Units.iconSizes.sizeForLabels
                        implicitHeight: Kirigami.Units.iconSizes.sizeForLabels
                    }
                    // Fall back to a generic icon if the application doesn't provide a valid one
                    Kirigami.Icon {
                        source: "preferences-system-windows"
                        visible: !iconItem.valid

                        implicitWidth: Kirigami.Units.iconSizes.sizeForLabels
                        implicitHeight: Kirigami.Units.iconSizes.sizeForLabels
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: root.formatWindowTitle(delegate.model.display)
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                }

                onHoveredChanged: {
                    if (hovered) {
                        windowListView.currentIndex = model.index
                    }
                }

                QQC2.Menu {
                    id: taskContextMenu

                    function runActionAndClose(action) {
                        action()
                        close()
                        root.expanded = false
                    }

                    Connections {
                        target: root
                        function onExpandedChanged(expanded) {
                            if (!expanded) {
                                taskContextMenu.close()
                            }
                        }
                    }

                    QQC2.MenuItem {
                        text: i18nc("@action:inmenu", "Activate")
                        onTriggered: taskContextMenu.runActionAndClose(function() {
                            const sourceIndex = root.sourceIndexForDelegateItem(delegate.model)
                            tasksModel.requestActivate(tasksModel.makeModelIndex(sourceIndex))
                        })
                    }

                    QQC2.MenuItem {
                        text: i18nc("@action:inmenu", "Open New Window")
                        onTriggered: taskContextMenu.runActionAndClose(function() {
                            const sourceIndex = root.sourceIndexForDelegateItem(delegate.model)
                            tasksModel.requestNewInstance(tasksModel.makeModelIndex(sourceIndex))
                        })
                    }

                    QQC2.MenuSeparator {}

                    QQC2.MenuItem {
                        text: i18nc("@action:inmenu", "Toggle Minimized")
                        onTriggered: taskContextMenu.runActionAndClose(function() {
                            const sourceIndex = root.sourceIndexForDelegateItem(delegate.model)
                            tasksModel.requestToggleMinimized(tasksModel.makeModelIndex(sourceIndex))
                        })
                    }

                    QQC2.MenuItem {
                        text: i18nc("@action:inmenu", "Toggle Maximized")
                        onTriggered: taskContextMenu.runActionAndClose(function() {
                            const sourceIndex = root.sourceIndexForDelegateItem(delegate.model)
                            tasksModel.requestToggleMaximized(tasksModel.makeModelIndex(sourceIndex))
                        })
                    }

                    QQC2.MenuItem {
                        text: i18nc("@action:inmenu", "Move")
                        onTriggered: taskContextMenu.runActionAndClose(function() {
                            const sourceIndex = root.sourceIndexForDelegateItem(delegate.model)
                            tasksModel.requestMove(tasksModel.makeModelIndex(sourceIndex))
                        })
                    }

                    QQC2.MenuItem {
                        text: i18nc("@action:inmenu", "Resize")
                        onTriggered: taskContextMenu.runActionAndClose(function() {
                            const sourceIndex = root.sourceIndexForDelegateItem(delegate.model)
                            tasksModel.requestResize(tasksModel.makeModelIndex(sourceIndex))
                        })
                    }

                    QQC2.MenuSeparator {}

                    QQC2.MenuItem {
                        text: i18nc("@action:inmenu", "Close")
                        onTriggered: taskContextMenu.runActionAndClose(function() {
                            const sourceIndex = root.sourceIndexForDelegateItem(delegate.model)
                            tasksModel.requestClose(tasksModel.makeModelIndex(sourceIndex))
                        })
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: false
                    preventStealing: true

                    property real pressedY: 0
                    property bool dragMoved: false

                    onPressed: function(mouse) {
                        pressedY = mouse.y
                        dragMoved = false
                    }

                    onPositionChanged: function(mouse) {
                        if (!root.usingCustomOrder) {
                            return
                        }

                        if (!dragMoved && Math.abs(mouse.y - pressedY) > Kirigami.Units.smallSpacing * 2) {
                            dragMoved = true
                        }

                        if (!dragMoved) {
                            return
                        }

                        const targetIndex = windowListView.indexAt(width / 2, delegate.y + mouse.y)
                        if (targetIndex >= 0 && targetIndex !== delegate.model.index) {
                            root.moveCustomTask(delegate.model.index, targetIndex)
                            windowListView.currentIndex = targetIndex
                        }
                    }

                    onReleased: function(mouse) {
                        if (!delegate.hasSourceTask) {
                            mouse.accepted = true
                            return
                        }

                        if (dragMoved && root.usingCustomOrder) {
                            mouse.accepted = true
                            return
                        }

                        windowListView.currentIndex = model.index
                        const sourceIndex = delegate.sourceIndex
                        tasksModel.requestActivate(tasksModel.makeModelIndex(sourceIndex))
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    hoverEnabled: false
                    preventStealing: true
                    onClicked: function(mouse) {
                        if (!delegate.hasSourceTask) {
                            mouse.accepted = true
                            return
                        }

                        if (mouse.button === Qt.RightButton) {
                            windowListView.currentIndex = model.index
                            taskContextMenu.popup()
                            mouse.accepted = true
                        }
                    }
                }

            }

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - (Kirigami.Units.largeSpacing * 2)
                visible: !inPanel && windowListView.count === 0
                icon.source: "edit-none"
                text: placeholderMetrics.text
            }


        }
    }

    // Only exists because the default CompactRepresentation doesn't expose the
    // ability to show text below or beside the icon.
    // TODO remove once it gains that feature.
    Component {
        id: windowListButton

        MenuButton {
            id: menuButton

            Layout.minimumWidth: implicitWidth
            Layout.maximumWidth: implicitWidth
            Layout.fillHeight: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
            Layout.fillWidth: Plasmoid.formFactor === PlasmaCore.Types.Vertical

            onClicked: {
                if (tasksModel.activeTask.valid) {
                    root.lastActiveTaskName = tasksModel.data(tasksModel.activeTask, TaskManager.AbstractTasksModel.AppName) ||
                       tasksModel.data(tasksModel.activeTask, 0 /* display name, window title if app name not present */)
                    root.lastActiveTaskIcon = tasksModel.data(tasksModel.activeTask, 1 /* decorationrole */)
                }
                root.expanded = !root.expanded
            }
            down: pressed || root.expanded

            Accessible.name: Plasmoid.title
            Accessible.description: root.toolTipSubText

            text: if (root.expanded && root.lastActiveTaskName !== "") {
                return root.lastActiveTaskName
            } else if (tasksModel.activeTask.valid) {
                return tasksModel.data(tasksModel.activeTask, TaskManager.AbstractTasksModel.AppName) ||
                       tasksModel.data(tasksModel.activeTask, 0 /* display name, window title if app name not present */)
            } else {
                return i18nc("@title:window title shown e.g. for desktop and expanded widgets", "Plasma Desktop")
            }

            iconSource: if (expanded && root.lastActiveTaskIcon) {
                return root.lastActiveTaskIcon
            } else if (tasksModel.activeTask.valid) {
                return tasksModel.data(tasksModel.activeTask, 1 /* decorationrole */)
            } else {
                return "start-here-kde-symbolic"
            }

            Timer {
                id: hoverOpenTimer
                interval: Plasmoid?.configuration?.hoverOpenDelay ?? 300
                repeat: false
                onTriggered: {
                    root.expanded = true
                }
            }

            onHoveredChanged: {
                if (hovered) {
                    if (tasksModel.activeTask.valid) {
                        root.lastActiveTaskName = tasksModel.data(tasksModel.activeTask, TaskManager.AbstractTasksModel.AppName) ||
                       tasksModel.data(tasksModel.activeTask, 0 /* display name, window title if app name not present */)
                       root.lastActiveTaskIcon = tasksModel.data(tasksModel.activeTask, 1 /* decorationrole */)
                    }
                    if (Plasmoid.configuration.openOnHover) {
                        hoverOpenTimer.start()
                    }
                } else {
                    hoverOpenTimer.stop()
                }
            }
        }
    }
}
