/*
 *  SPDX-FileCopyrightText: 2022 Nate Graham <nate@kde.org>
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    readonly property string widgetVersion: {
        const fromEnhancedKey = Plasmoid.metaData.value("X-WindowListEnhanced-Version")
        if (fromEnhancedKey) {
            return fromEnhancedKey
        }

        const fromValue = Plasmoid.metaData.value("Version")
        if (fromValue) {
            return fromValue
        }

        if (Plasmoid.metaData.version) {
            return Plasmoid.metaData.version
        }

        return ""
    }

    property bool cfg_showText: Plasmoid.configuration.showText
    property bool cfg_showIcon: Plasmoid.configuration.showIcon
    property alias cfg_openOnHover: openOnHoverCheckbox.checked
    property alias cfg_hoverOpenDelay: hoverDelaySpinBox.value
    property alias cfg_showOnlyCurrentScreen: showOnlyCurrentScreen.checked
    property alias cfg_showOnlyCurrentDesktop: showOnlyCurrentDesktop.checked
    property alias cfg_showOnlyCurrentActivity: showOnlyCurrentActivity.checked
    property alias cfg_showOnlyMinimized: showOnlyMinimized.checked
    property int cfg_windowListOrder: Plasmoid.configuration.windowListOrder

    Kirigami.FormLayout {
        anchors.right: parent.right
        anchors.left: parent.left

        QQC2.ComboBox {
            id: displayModeComboBox

            Kirigami.FormData.label: i18nc("@label:listbox", "For active application, show:")

            enabled: Plasmoid.formFactor === PlasmaCore.Types.Horizontal

            model: [
                i18nc("@item:inlistbox what to show for active application in horizontal panel", "Icon and name"),
                i18nc("@item:inlistbox what to show for active application in horizontal panel", "Icon"),
                i18nc("@item:inlistbox what to show for active application in horizontal panel", "Name")
            ]

            property var mode: 0

            onModeChanged: {
                if (mode === 0) {
                    root.cfg_showIcon = true
                    root.cfg_showText = true
                } else if (mode === 1) {
                    root.cfg_showIcon = true
                    root.cfg_showText = false
                } else if (mode === 2) {
                    root.cfg_showIcon = false
                    root.cfg_showText = true
                }
            }

            onCurrentIndexChanged: mode = currentIndex

            Component.onCompleted: {
                if (root.cfg_showIcon && root.cfg_showText) {
                    mode = 0
                } else if (root.cfg_showIcon && !root.cfg_showText) {
                    mode = 1
                } else if (!root.cfg_showIcon && root.cfg_showText) {
                    mode = 2
                } else {
                    // Invalid state, fallback to icon only
                    mode = 1
                    root.cfg_showIcon = true
                    root.cfg_showText = false
                }
                currentIndex = mode
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            // Arbitrary maximum length to make it wrap earlier, because long
            // unwrapped text is ugly and harder to read.
            Layout.maximumWidth: Kirigami.Units.gridUnit * 25

            visible: !displayModeComboBox.enabled
        
            text: Plasmoid.formFactor === PlasmaCore.Types.Vertical ?
                // On a vertical panel
                i18nc("@info:usagetip display mode for active application", "Only icons can be shown when the Panel is vertical.") :
                // On the desktop
                i18nc("@info:usagetip display mode for active application", "Not applicable when the widget is on the Desktop.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
        }

        Item {
            Kirigami.FormData.isSection: true
        }


        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Kirigami.FormData.label: i18nc("@label:checkbox", "Open on hover:")

            QQC2.CheckBox {
                id: openOnHoverCheckbox

                text: i18nc("@option:check open-on-hover is enabled, with the following delay:", "Enabled, with delay:")
            }

            QQC2.SpinBox {
                id: hoverDelaySpinBox

                from: 0
                to: 1000
                stepSize: 50

                enabled: root.cfg_openOnHover

                textFromValue: function(value, locale) {
                    return i18ncp("@item:valuesuffix, %1 is hover activation delay in ms", "%1 ms", "%1 ms", value)
                }

                validator: IntValidator {
                    bottom: hoverDelaySpinBox.from
                    top: hoverDelaySpinBox.to
                }

                valueFromText: (text, locale) => {
                    return Number.fromLocaleString(locale, text.replace(i18ncp("short for millisecond(s)", "ms", "ms"), ""))
                }

                Accessible.name: i18nc("@label:spinbox accessible %1 is milliseconds", "Hover open delay %1 ms", value)
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: showOnlyCurrentDesktop
            Kirigami.FormData.label: i18nc("@label for checkbox group, completes sentence like: … from current screen", "Show only windows:")
            text: i18nc("@option:check completes sentence: show only windows", "From the current desktop")
        }

        QQC2.CheckBox {
            id: showOnlyCurrentActivity
            text: i18nc("@option:check completes sentence: show only windows", "From the current activity")
        }

        QQC2.CheckBox {
            id: showOnlyCurrentScreen
            text: i18nc("@option:check completes sentence: show only windows", "From the current screen")
        }

        QQC2.CheckBox {
            id: showOnlyMinimized
            text: i18nc("@option:check completes sentence: show only windows", "That are minimized")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: windowListOrder
            Kirigami.FormData.label: i18nc("@label:listbox", "Window List Order:")
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14
            textRole: "text"
            valueRole: "value"
            model: [
                {
                    "text": i18nc("@item:inlistbox", "Ungrouped (by order opened)"),
                    "value": 0
                },
                {
                    "text": i18nc("@item:inlistbox", "Sort by App"),
                    "value": 1
                }
            ]
            onActivated: root.cfg_windowListOrder = currentValue
            Component.onCompleted: currentIndex = indexOfValue(root.cfg_windowListOrder)
        }

        QQC2.Label {
            Kirigami.FormData.label: i18nc("@label", "Version:")
            text: root.widgetVersion !== "" ? root.widgetVersion : i18nc("@label", "Unknown")
        }

    }
}
