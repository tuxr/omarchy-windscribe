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
  property var expandedRegions: ({})

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: windscribe.connected ? foreground : dim
  readonly property color barIconColor: windscribe.connected ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string toggleHint: windscribe.connected ? "Disconnect VPN" : "Connect to best location"
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && windscribe.installed
  readonly property var recentNicknames: settings.recentLocations instanceof Array ? settings.recentLocations : []
  readonly property var visibleRows: buildVisibleRows()
  readonly property bool showControls: windscribe.installed && windscribe.loggedIn
  readonly property bool showStatic: windscribe.staticLocations.length > 0
  readonly property bool showFavs: windscribe.favorites.length > 0
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

  function isCurrent(loc) {
    if (!loc || !windscribe.connected || windscribe.locationName === "") return false
    var name = windscribe.locationName.toLowerCase()
    var nick = String(loc.nickname || "").toLowerCase()
    var city = String(loc.city || "").toLowerCase()
    if (nick !== "" && (name === nick || name.endsWith(" - " + nick))) {
      if (city === "" || name.indexOf(city) !== -1) return true
    }
    return name === (city + " - " + nick)
  }

  function isRegionCurrent(region) {
    if (!windscribe.connected) return false
    for (var i = 0; i < windscribe.locations.length; i++) {
      if (windscribe.locations[i].region === region && isCurrent(windscribe.locations[i]))
        return true
    }
    return false
  }

  function rowMatches(row, q) {
    if (!row || q === "") return true
    var hay = [row.title, row.subtitle, row.target, row.region].join(" ").toLowerCase()
    return hay.indexOf(q) !== -1
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

  function groupedRegions() {
    var order = []
    var map = {}
    for (var i = 0; i < windscribe.locations.length; i++) {
      var loc = windscribe.locations[i]
      var region = String(loc.region || "Other")
      if (!map[region]) {
        map[region] = []
        order.push(region)
      }
      map[region].push(loc)
    }
    return { order: order, map: map }
  }

  function locRow(loc, extra) {
    var row = {
      kind: "loc",
      title: loc.city !== "" ? (loc.city + (loc.nickname !== "" && loc.nickname !== loc.city ? "  " + loc.nickname : "")) : (loc.title || loc.nickname),
      subtitle: loc.speed !== "" ? loc.speed : (loc.region || ""),
      target: loc.target || loc.nickname,
      region: loc.region || "",
      loc: loc,
      indent: 1,
      expandable: false,
      expanded: false,
      connected: isCurrent(loc)
    }
    if (extra) {
      for (var k in extra) row[k] = extra[k]
    }
    return row
  }

  function toggleRegion(name) {
    var next = {}
    for (var k in expandedRegions) next[k] = expandedRegions[k]
    next[name] = !next[name]
    expandedRegions = next
  }

  function expandCurrentRegion() {
    if (!windscribe.connected) return
    for (var i = 0; i < windscribe.locations.length; i++) {
      if (isCurrent(windscribe.locations[i]) && windscribe.locations[i].region) {
        var next = {}
        for (var k in expandedRegions) next[k] = expandedRegions[k]
        next[windscribe.locations[i].region] = true
        expandedRegions = next
        return
      }
    }
  }

  function buildVisibleRows() {
    var rows = []
    var q = String(query || "").trim().toLowerCase()

    function pushBest() {
      var best = windscribe.bestLocation
      if (!best) return
      if (q !== "" && !rowMatches({ title: best.title, subtitle: best.subtitle, target: best.target }, q)) return
      rows.push({
        kind: "best",
        title: "Best location",
        subtitle: best.subtitle || best.nickname,
        target: "best",
        region: "",
        loc: best,
        indent: 0,
        expandable: false,
        expanded: false,
        connected: isCurrent(best)
      })
    }

    function pushLocList(list, indent) {
      for (var i = 0; i < list.length; i++) {
        var loc = list[i]
        var row = locRow(loc, { indent: indent || 0 })
        if (q === "" || rowMatches(row, q)) rows.push(row)
      }
    }

    pushBest()

    if (q === "") {
      for (var r = 0; r < recentNicknames.length && r < 5; r++) {
        var rec = findByNickname(recentNicknames[r])
        if (rec) rows.push(locRow(rec, { indent: 0, kind: "recent" }))
      }
    }

    for (var f = 0; f < windscribe.favorites.length; f++) {
      var fr = locRow(windscribe.favorites[f], { indent: 0, kind: "fav" })
      if (q === "" || rowMatches(fr, q)) rows.push(fr)
    }

    for (var s = 0; s < windscribe.staticLocations.length; s++) {
      var sl = windscribe.staticLocations[s]
      var sr = locRow(sl, { indent: 0, kind: "static", target: "static:" + (sl.city || sl.nickname || sl.target) })
      if (q === "" || rowMatches(sr, q)) rows.push(sr)
    }

    var grouped = groupedRegions()
    for (var g = 0; g < grouped.order.length; g++) {
      var region = grouped.order[g]
      var members = grouped.map[region]
      var expanded = expandedRegions[region] === true || q !== ""
      var regionRow = {
        kind: "region",
        title: region,
        subtitle: members.length + (members.length === 1 ? " city" : " cities"),
        target: region,
        region: region,
        loc: null,
        indent: 0,
        expandable: true,
        expanded: expanded,
        connected: isRegionCurrent(region)
      }
      if (q === "") {
        rows.push(regionRow)
        if (expanded) {
          for (var m = 0; m < members.length; m++)
            rows.push(locRow(members[m], { indent: 1 }))
        }
      } else {
        var matched = []
        for (var n = 0; n < members.length; n++) {
          var cand = locRow(members[n], { indent: 1 })
          if (rowMatches(cand, q) || region.toLowerCase().indexOf(q) !== -1)
            matched.push(cand)
        }
        if (matched.length > 0) {
          rows.push(regionRow)
          for (var p = 0; p < matched.length; p++) rows.push(matched[p])
        }
      }
    }
    return rows
  }

  function selectedRow() {
    if (visibleRows.length === 0) return null
    return visibleRows[Math.max(0, Math.min(locationIndex, visibleRows.length - 1))]
  }

  function ensureCursor() {
    if (locationIndex >= visibleRows.length) locationIndex = Math.max(0, visibleRows.length - 1)
    if (locationIndex < 0) locationIndex = 0
    if (focusSection === "locations" && visibleRows.length === 0) focusSection = "header"
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
      else if (visibleRows.length > 0) { focusSection = "locations"; locationIndex = 0 }
    } else if (focusSection === "locations") {
      if (dy < 0) {
        if (locationIndex <= 0) focusSection = showControls ? "protocol" : "header"
        else locationIndex--
      } else if (locationIndex < visibleRows.length - 1) {
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
    else if (focusSection === "locations") activateLocation(selectedRow())
  }

  function activateLocation(row) {
    if (!row || windscribe.busy) return
    if (row.kind === "region") {
      if (!row.expanded) {
        toggleRegion(row.region)
        return
      }
      windscribe.connectTo(row.target)
      return
    }
    persistRecent(row.loc)
    var target = String(row.target || "")
    if (target.indexOf("static:") === 0)
      windscribe.connectTo(target)
    else
      windscribe.connectTo(target || "best")
  }

  function connectLocation(loc) {
    activateLocation(loc && loc.target ? loc : locRow(loc, { indent: 0 }))
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

  function heroTitle() {
    if (windscribe.connected && windscribe.locationName !== "") {
      var parts = windscribe.locationName.split(" - ")
      return parts[0]
    }
    return "Windscribe"
  }

  function heroMeta() {
    if (!windscribe.installed) return "windscribe-cli is not installed"
    if (!windscribe.loggedIn) return "Not logged in — run windscribe-cli login"
    if (windscribe.connected) {
      var parts = String(windscribe.locationName || "").split(" - ")
      var nick = parts.length > 1 ? parts.slice(1).join(" - ") : ""
      var bits = []
      if (nick !== "") bits.push(nick)
      if (windscribe.protocolText !== "") bits.push(windscribe.protocolText)
      return bits.length > 0 ? bits.join(" · ") : "Connected"
    }
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
    expandCurrentRegion()
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
    function pinIp(): string { windscribe.pinIp(); return "ok" }
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
        } else if (t === "p" || t === "P") {
          windscribe.pinIp()
        } else if (t === "l" || t === "L" || t === "h" || t === "H") {
          var row = root.selectedRow()
          if (row && row.kind === "region") root.toggleRegion(row.region)
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
              title: root.heroTitle()
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
              text: "CONNECTION"
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
              spacing: Style.space(6)

              PanelActionButton {
                visible: windscribe.connected
                iconText: "\uf08d"
                tooltipText: "Pin current IP"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !windscribe.busy
                onClicked: windscribe.pinIp()
              }

              PanelActionButton {
                visible: windscribe.connected
                iconText: "\uf021"
                tooltipText: "Rotate IP"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !windscribe.busy
                onClicked: windscribe.rotateIp()
              }

              PanelActionButton {
                visible: windscribe.publicIp !== ""
                iconText: "\uf0c5"
                tooltipText: "Copy IP"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: windscribe.copyIp()
              }

              PanelActionButton {
                iconText: "\uf01e"
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
              onAccepted: root.activateLocation(root.selectedRow())
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down) {
                  root.moveCursor(0, 1)
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Up) {
                  root.moveCursor(0, -1)
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
                  var row = root.selectedRow()
                  if (row && row.kind === "region") {
                    root.toggleRegion(row.region)
                    event.accepted = true
                  }
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
              visible: root.visibleRows.length === 0
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
                model: root.visibleRows
                LocationRow {
                  required property var modelData
                  required property int index
                  width: locColumn.width
                  row: modelData
                  rowIndex: index
                }
              }
            }

            Text {
              visible: root.query === ""
              width: parent.width
              text: "Enter expands a region · click a city to connect"
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
    property var row: null
    property int rowIndex: 0
    readonly property bool isConnected: row ? row.connected === true : false
    readonly property int indentPx: row && row.indent ? Style.space(16) * row.indent : 0

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
      onClicked: root.activateLocation(locRow.row)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10) + locRow.indentPx
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      ColumnLayout {
        id: locContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: locRow.row ? String(locRow.row.title || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: locRow.row && locRow.row.kind === "region"
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          visible: locRow.row && String(locRow.row.subtitle || "") !== ""
          text: locRow.row ? String(locRow.row.subtitle || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: locRow.row && locRow.row.kind === "best"
        text: "best"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: locRow.row && locRow.row.kind === "recent"
        text: "recent"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: locRow.row && locRow.row.kind === "fav"
        text: "fav"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: locRow.row && locRow.row.kind === "static"
        text: "static"
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

      PanelActionButton {
        visible: locRow.row && locRow.row.expandable === true
        iconText: locRow.row && locRow.row.expanded ? "\uf078" : "\uf054"
        tooltipText: locRow.row && locRow.row.expanded ? "Collapse" : "Expand"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: if (locRow.row) root.toggleRegion(locRow.row.region)
      }
    }
  }
}
