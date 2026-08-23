import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.dsumpter.windscribe"
  ipcTarget: "io.github.dsumpter.windscribe"
  manageIpc: false

  property string focusSection: "header"
  property int locationIndex: 0
  property bool cursorActive: false
  property string query: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: windscribe.connected ? foreground : dim
  readonly property color barIconColor: windscribe.connected ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string toggleHint: windscribe.connected ? "Disconnect VPN" : "Connect to best location"
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && windscribe.installed
  readonly property var recentNicknames: settings.recentLocations instanceof Array ? settings.recentLocations : []
  readonly property var visibleLocations: buildVisibleLocations()
  readonly property bool showControls: windscribe.installed && windscribe.loggedIn
  readonly property var protocolOptions: [
    { value: "Auto", label: "Auto" },
    { value: "WireGuard", label: "WireGuard" },
    { value: "UDP", label: "UDP" },
    { value: "TCP", label: "TCP" },
    { value: "Stealth", label: "Stealth" },
    { value: "WStunnel", label: "WStunnel" }
  ]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function matchesLoc(loc, q) {
    if (!loc || q === "") return true
    var hay = [loc.title, loc.subtitle, loc.city, loc.region, loc.nickname, loc.full].join(" ").toLowerCase()
    return hay.indexOf(q) !== -1
  }

  function isCurrent(loc) {
    if (!loc || !windscribe.connected || windscribe.locationName === "") return false
    var name = windscribe.locationName.toLowerCase()
    var nick = String(loc.nickname || "").toLowerCase()
    var city = String(loc.city || "").toLowerCase()
    if (nick !== "" && name.indexOf(nick) !== -1) {
      if (city === "" || name.indexOf(city) !== -1) return true
    }
    return name === (city + " - " + nick)
  }

  function findByNickname(nick) {
    var key = String(nick || "").toLowerCase()
    if (key === "") return null
    if (windscribe.bestLocation && String(windscribe.bestLocation.nickname || "").toLowerCase() === key)
      return windscribe.bestLocation
    for (var i = 0; i < windscribe.locations.length; i++) {
      if (String(windscribe.locations[i].nickname || "").toLowerCase() === key)
        return windscribe.locations[i]
    }
    return null
  }

  function buildVisibleLocations() {
    var out = []
    var seen = {}
    var q = String(query || "").trim().toLowerCase()

    function pushLoc(loc) {
      if (!loc) return
      var key = String(loc.target || loc.nickname || loc.full || "").toLowerCase()
      if (key !== "" && seen[key]) return
      if (q !== "" && !matchesLoc(loc, q)) return
      out.push(loc)
      if (key) seen[key] = true
    }

    pushLoc(windscribe.bestLocation)

    if (q === "") {
      for (var r = 0; r < recentNicknames.length && r < 5; r++)
        pushLoc(findByNickname(recentNicknames[r]))
      var current = null
      for (var c = 0; c < windscribe.locations.length; c++) {
        if (isCurrent(windscribe.locations[c])) { current = windscribe.locations[c]; break }
      }
      pushLoc(current)
      for (var f = 0; f < windscribe.favorites.length; f++)
        pushLoc(windscribe.favorites[f])
    } else {
      for (var i = 0; i < windscribe.locations.length && out.length < 40; i++)
        pushLoc(windscribe.locations[i])
    }
    return out
  }

  function selectedLocation() {
    if (visibleLocations.length === 0) return null
    return visibleLocations[Math.max(0, Math.min(locationIndex, visibleLocations.length - 1))]
  }

  function ensureCursor() {
    if (locationIndex >= visibleLocations.length) locationIndex = Math.max(0, visibleLocations.length - 1)
    if (locationIndex < 0) locationIndex = 0
    if (focusSection === "locations" && visibleLocations.length === 0) focusSection = "header"
    if (focusSection === "firewall" && !showControls) focusSection = "header"
    if (focusSection === "protocol" && !showControls) focusSection = "header"
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0 && showControls) focusSection = "firewall"
    } else if (focusSection === "firewall") {
      if (dy < 0) setHeaderCursor()
      else focusSection = "protocol"
    } else if (focusSection === "protocol") {
      if (dy < 0) focusSection = "firewall"
      else if (visibleLocations.length > 0) { focusSection = "locations"; locationIndex = 0 }
    } else if (focusSection === "locations") {
      if (dy < 0) {
        if (locationIndex <= 0) focusSection = showControls ? "protocol" : "header"
        else locationIndex--
      } else if (locationIndex < visibleLocations.length - 1) {
        locationIndex++
      }
    }
    ensureCursor()
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") windscribe.toggle()
    else if (focusSection === "firewall") windscribe.setFirewall(!windscribe.firewallOn)
    else if (focusSection === "protocol") protoDrop.toggle()
    else if (focusSection === "locations") connectLocation(selectedLocation())
  }

  function connectLocation(loc) {
    if (!loc || windscribe.busy) return
    persistRecent(loc)
    windscribe.connectTo(loc.target || loc.nickname || "best")
  }

  function persistRecent(loc) {
    if (!loc || loc.isBest) return
    var name = String(loc.nickname || "")
    if (name === "") return
    var next = [name]
    for (var i = 0; i < recentNicknames.length && next.length < 5; i++) {
      var existing = String(recentNicknames[i] || "")
      if (existing !== "" && existing !== name && next.indexOf(existing) === -1) next.push(existing)
    }
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.recentLocations = next
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function persistProtocol(value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.defaultProtocol = value
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection !== "locations" || !locColumn) return
    if (locationIndex >= 0 && locationIndex < locColumn.children.length)
      scrollItemIntoView(locColumn.children[locationIndex])
  }

  function heroMeta() {
    if (!windscribe.installed) return "windscribe-cli is not installed"
    if (!windscribe.loggedIn) return "Not logged in — run windscribe-cli login"
    if (windscribe.connected) return "Connected · " + (windscribe.locationName || "unknown location")
    return "Disconnected"
  }

  function detailLine() {
    var parts = []
    if (windscribe.protocolText !== "") parts.push(windscribe.protocolText)
    if (windscribe.publicIp !== "") parts.push(windscribe.publicIp)
    if (windscribe.dataUsage !== "") parts.push(windscribe.dataUsage)
    if (windscribe.loggedIn) parts.push("Firewall " + (windscribe.firewallOn ? "on" : "off"))
    return parts.join("  ·  ")
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    query = ""
    locationIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    windscribe.refreshAll()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onLocationIndexChanged: scrollCursorIntoView()

  Service {
    id: windscribe
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { windscribe.refreshAll(); return "ok" }
    function connectBest(): string { windscribe.connectTo("best"); return "ok" }
    function disconnect(): string { windscribe.disconnectVpn(); return "ok" }
    function rotateIp(): string { windscribe.rotateIp(); return "ok" }
    function status(): string {
      return windscribe.connected
        ? ("Connected: " + windscribe.locationName)
        : (windscribe.connectState || "Disconnected")
    }
    function debug(): string {
      return "installed=" + windscribe.installed
        + " loggedIn=" + windscribe.loggedIn
        + " state=" + windscribe.connectState
        + " err=" + windscribe.lastError
        + " busy=" + windscribe.busy
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: windscribe.connected
      ? ("Windscribe: " + (windscribe.locationName || "connected"))
      : "Windscribe: disconnected"
    iconComponent: Component {
      Item {
        WindscribeIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          crossed: !windscribe.connected && windscribe.installed && windscribe.loggedIn
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) windscribe.toggle()
      else if (buttonCode === Qt.MiddleButton) windscribe.refreshAll()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || protoDrop.popupOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/" || t === "s" || t === "S") {
          searchField.forceActiveFocus()
        } else if (t === "c" || t === "C" || t === "t" || t === "T") {
          windscribe.toggle()
        } else if (t === "r" || t === "R") {
          windscribe.refreshAll()
        } else if (t === "f" || t === "F") {
          windscribe.setFirewall(!windscribe.firewallOn)
        } else if (t === "i" || t === "I") {
          windscribe.rotateIp()
        } else if (t === "y" || t === "Y") {
          windscribe.copyIp()
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Windscribe"
              meta: root.heroMeta()
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: windscribe.connected ? 1.0 : 0.5
              iconComponent: Component {
                WindscribeIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  crossed: !windscribe.connected && windscribe.installed && windscribe.loggedIn
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: windscribe.installed
                  checked: windscribe.connected
                  busy: windscribe.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: windscribe.toggle()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: windscribe.installed && windscribe.loggedIn && root.detailLine() !== ""
            text: root.detailLine()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            visible: windscribe.actionStatus !== "" || windscribe.lastError !== ""
            width: parent.width
            text: windscribe.lastError !== "" ? windscribe.lastError : windscribe.actionStatus
            color: windscribe.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            visible: !windscribe.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "Install windscribe-cli and keep it on PATH."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          CursorSurface {
            visible: windscribe.installed && !windscribe.loggedIn
            width: parent.width
            implicitHeight: loginText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: loginText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "Run windscribe-cli login in a terminal, then refresh."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: root.showControls
            foreground: root.foreground
          }

          Column {
            visible: root.showControls
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "CONTROLS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Toggle {
              width: parent.width
              label: "Firewall"
              description: windscribe.firewallOn ? "Blocks traffic outside the tunnel" : "Off — traffic can leak off-VPN"
              checked: windscribe.firewallOn
              hasCursor: root.cursorActive && root.focusSection === "firewall"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "firewall" } }
              onClicked: windscribe.setFirewall(!windscribe.firewallOn)
            }

            Dropdown {
              id: protoDrop
              width: parent.width
              label: "PROTOCOL"
              value: String(root.settings.defaultProtocol || "Auto")
              options: root.protocolOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "protocol"
              onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "protocol" } }
              onChanged: function(value) { root.persistProtocol(value) }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                visible: windscribe.connected
                text: "Rotate IP"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !windscribe.busy
                onClicked: windscribe.rotateIp()
              }

              Button {
                visible: windscribe.publicIp !== ""
                text: "Copy IP"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: windscribe.copyIp()
              }

              PanelActionButton {
                iconText: "\uf021"
                tooltipText: "Refresh"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: windscribe.refreshAll()
              }
            }
          }

          PanelSeparator {
            visible: root.showControls
            foreground: root.foreground
          }

          Column {
            visible: root.showControls
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LOCATIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: searchField
              width: parent.width
              foreground: root.foreground
              placeholderText: windscribe.locationCount > 0
                ? ("Search " + windscribe.locationCount + " locations")
                : "Search locations"
              text: root.query
              onTextChanged: {
                root.query = text
                root.locationIndex = 0
                root.focusSection = "locations"
              }
              onAccepted: root.connectLocation(root.selectedLocation())
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down || event.text === "j") {
                  root.moveCursor(0, 1)
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Up || event.text === "k") {
                  root.moveCursor(0, -1)
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Escape) {
                  if (root.query !== "") {
                    root.query = ""
                    searchField.text = ""
                  } else {
                    keyCatcher.forceActiveFocus()
                  }
                  event.accepted = true
                }
              }
            }

            Text {
              visible: root.visibleLocations.length === 0
              width: parent.width
              text: root.query !== "" ? "No locations match that search." : "Loading locations…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: locColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.visibleLocations
                LocationRow {
                  required property var modelData
                  required property int index
                  width: locColumn.width
                  loc: modelData
                  rowIndex: index
                }
              }
            }

            Text {
              visible: root.query === "" && windscribe.locationCount > root.visibleLocations.length
              width: parent.width
              text: "Type to search the full list."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }

  component LocationRow: CursorSurface {
    id: locRow
    property var loc: null
    property int rowIndex: 0
    readonly property bool isConnected: root.isCurrent(loc)

    hasCursor: root.cursorActive && root.focusSection === "locations" && root.locationIndex === rowIndex
    current: locRow.isConnected
    foreground: root.foreground
    implicitHeight: locContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "locations"
        root.locationIndex = locRow.rowIndex
      }
      onClicked: root.connectLocation(locRow.loc)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      ColumnLayout {
        id: locContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: locRow.loc ? String(locRow.loc.title || locRow.loc.full || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          visible: locRow.loc && String(locRow.loc.subtitle || "") !== ""
          text: locRow.loc ? String(locRow.loc.subtitle || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: locRow.loc && locRow.loc.isBest === true
        text: "best"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: locRow.isConnected
        text: "connected"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
