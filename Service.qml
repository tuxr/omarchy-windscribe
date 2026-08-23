import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// All windscribe-cli calls go through one Process. The binary is single-
// instance: a second spawn exits 1 with "already running".
Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool loggedIn: false
  property string connectState: ""
  property string locationName: ""
  property string protocolText: ""
  property string publicIp: ""
  property string dataUsage: ""
  property bool firewallOn: false
  property var locations: []
  property var favorites: []
  property var bestLocation: null
  property string lastError: ""
  property string actionStatus: ""

  // Optimistic state so the icon flips the instant you click.
  property int _desired: -1
  readonly property bool connected: _desired === -1
    ? (connectState.indexOf("Connected") === 0)
    : (_desired === 1)

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 10, 3600)
  readonly property string protocolSetting: normalizeProtocol(setting("defaultProtocol", "Auto"))
  readonly property bool busy: cli.running
  readonly property int locationCount: locations.length

  property var _queue: []
  property string _kind: ""
  property bool _wantLists: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function normalizeProtocol(value) {
    var raw = String(value || "Auto").trim().toLowerCase()
    if (raw === "wireguard") return "wireguard"
    if (raw === "udp") return "udp"
    if (raw === "tcp") return "tcp"
    if (raw === "stealth") return "stealth"
    if (raw === "wstunnel") return "wstunnel"
    return ""
  }

  function enqueue(args, kind) {
    if (!args || args.length === 0) return
    _queue.push({ args: args, kind: kind || "action" })
    pump()
  }

  function pump() {
    if (cli.running || _queue.length === 0) return
    var job = _queue.shift()
    _kind = job.kind
    cli.command = job.args
    cli.running = true
    watchdog.restart()
  }

  function refresh() {
    if (!installed) {
      enqueue(["which", "windscribe-cli"], "which")
      return
    }
    enqueue(["windscribe-cli", "status"], "status")
  }

  function refreshAll() {
    if (!installed) {
      enqueue(["which", "windscribe-cli"], "which")
      return
    }
    _wantLists = true
    enqueue(["windscribe-cli", "status"], "status")
  }

  function refreshLocations() {
    if (!installed || !loggedIn) return
    enqueue(["windscribe-cli", "locations"], "locations")
    enqueue(["windscribe-cli", "locations", "fav"], "fav")
  }

  function toggle() {
    if (!installed || !loggedIn) return
    if (connected) disconnectVpn()
    else connectTo("best")
  }

  function connectTo(target) {
    if (!installed || !loggedIn) return
    var t = String(target || "best").trim()
    if (t === "") t = "best"
    _desired = 1
    lastError = ""
    actionStatus = t === "best" ? "Connecting to best location…" : ("Connecting to " + t + "…")
    var cmd = ["windscribe-cli", "connect", t]
    if (protocolSetting !== "") cmd.push(protocolSetting)
    enqueue(cmd, "action")
  }

  function disconnectVpn() {
    if (!installed) return
    _desired = 0
    lastError = ""
    actionStatus = "Disconnecting…"
    enqueue(["windscribe-cli", "disconnect"], "action")
  }

  function setFirewall(on) {
    if (!installed || !loggedIn) return
    lastError = ""
    actionStatus = on ? "Enabling firewall…" : "Disabling firewall…"
    enqueue(["windscribe-cli", "firewall", on ? "on" : "off"], "action")
  }

  function rotateIp() {
    if (!installed || !loggedIn || !connected) return
    lastError = ""
    actionStatus = "Rotating IP…"
    enqueue(["windscribe-cli", "ip", "rotate"], "action")
  }

  function copyIp() {
    if (publicIp === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(publicIp) + " | wl-copy"])
    actionStatus = "Copied " + publicIp
    statusClear.restart()
  }

  function parseStatus(raw) {
    var text = String(raw || "")
    loggedIn = /Login state:\s*Logged in/.test(text)
    firewallOn = /Firewall state:\s*On/.test(text)
    publicIp = ""
    protocolText = ""
    locationName = ""
    dataUsage = ""

    var stateMatch = text.match(/Connect state:\s*(.+)/)
    connectState = stateMatch ? stateMatch[1].trim() : "Unknown"

    var usageMatch = text.match(/Data usage:\s*(.+)/)
    if (usageMatch) dataUsage = usageMatch[1].trim()

    if (connectState.indexOf("Connected") === 0) {
      var locMatch = connectState.match(/Connected:\s*(.+)$/)
      locationName = locMatch ? locMatch[1].trim() : ""
      var protoMatch = text.match(/Protocol:\s*(.+)/)
      if (protoMatch) protocolText = protoMatch[1].trim()
      var vpnIpMatch = text.match(/VPN IP:\s*(\S+)/)
      if (vpnIpMatch) publicIp = vpnIpMatch[1]
    }

    var real = connectState.indexOf("Connected") === 0
    if (_desired !== -1 && real === (_desired === 1)) _desired = -1
  }

  function parseLocationLine(line, isBest) {
    var raw = String(line || "").trim()
    if (raw === "" || /^No locations/i.test(raw) || /^\(Device name/i.test(raw)) return null
    var speed = ""
    var speedMatch = raw.match(/\(([^)]+)\)\s*$/)
    if (speedMatch) speed = speedMatch[1].trim()
    var label = raw.replace(/\s*\([^)]*\)\s*$/, "")
    var parts = label.split(" - ")
    var region = ""
    var city = ""
    var nickname = ""
    if (isBest || /^Best Location/i.test(parts[0] || "")) {
      nickname = parts.length > 1 ? parts[parts.length - 1] : ""
      return {
        full: label,
        region: "",
        city: "",
        nickname: nickname,
        speed: speed,
        target: "best",
        isBest: true,
        title: "Best location",
        subtitle: nickname !== "" ? (nickname + (speed !== "" ? " · " + speed : "")) : speed
      }
    }
    if (parts.length >= 3) {
      region = parts[0]
      city = parts[1]
      nickname = parts.slice(2).join(" - ")
    } else if (parts.length === 2) {
      region = parts[0]
      nickname = parts[1]
    } else {
      nickname = label
    }
    var title = city !== "" ? city : nickname
    var bits = []
    if (region !== "") bits.push(region)
    if (nickname !== "" && nickname !== title) bits.push(nickname)
    if (speed !== "") bits.push(speed)
    return {
      full: label,
      region: region,
      city: city,
      nickname: nickname,
      speed: speed,
      target: nickname !== "" ? nickname : (city !== "" ? city : label),
      isBest: false,
      title: title,
      subtitle: bits.join(" · ")
    }
  }

  function parseLocationList(raw, markBest) {
    var lines = String(raw || "").split("\n")
    var result = []
    var best = null
    for (var i = 0; i < lines.length; i++) {
      var isBestLine = markBest && i === 0 && /^Best Location/i.test(lines[i].trim())
      var loc = parseLocationLine(lines[i], isBestLine)
      if (!loc) continue
      if (loc.isBest) best = loc
      else result.push(loc)
    }
    return { locations: result, best: best }
  }

  function handleExit(exitCode, out, err, kind) {
    var failed = exitCode !== 0
    var msg = String(err || out || "").trim()
    if (failed && /already running/i.test(msg)) {
      retryTimer.restart()
      return
    }

    if (kind === "which") {
      installed = exitCode === 0
      if (installed) {
        lastError = ""
        enqueue(["windscribe-cli", "status"], "status")
      } else {
        lastError = "windscribe-cli not found in PATH"
      }
      return
    }

    if (kind === "status") {
      if (failed) {
        lastError = msg || ("status failed (" + exitCode + ")")
        return
      }
      lastError = ""
      parseStatus(out)
      if (loggedIn && (_wantLists || locations.length === 0)) {
        _wantLists = false
        enqueue(["windscribe-cli", "locations"], "locations")
        enqueue(["windscribe-cli", "locations", "fav"], "fav")
      } else {
        _wantLists = false
      }
      return
    }

    if (kind === "locations") {
      if (failed) {
        lastError = msg || "locations failed"
        return
      }
      var parsed = parseLocationList(out, true)
      locations = parsed.locations
      if (parsed.best) bestLocation = parsed.best
      return
    }

    if (kind === "fav") {
      if (failed) return
      favorites = parseLocationList(out, false).locations
      return
    }

    // action
    if (failed) {
      _desired = -1
      actionStatus = ""
      lastError = msg || "command failed"
      enqueue(["windscribe-cli", "status"], "status")
      return
    }
    lastError = ""
    actionStatus = ""
    enqueue(["windscribe-cli", "status"], "status")
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!root.busy && root._queue.length === 0) root.refresh()
  }

  Timer {
    id: watchdog
    interval: 25000
    repeat: false
    onTriggered: {
      if (cli.running) {
        cli.running = false
        root.lastError = "windscribe-cli timed out"
        root._kind = ""
        Qt.callLater(root.pump)
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 2000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: statusClear
    interval: 2500
    repeat: false
    onTriggered: if (root.lastError === "") root.actionStatus = ""
  }

  Process {
    id: cli
    running: false
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      watchdog.stop()
      var out = String(stdout.text || "")
      var err = String(stderr.text || "")
      var kind = root._kind
      root._kind = ""
      root.handleExit(exitCode, out, err, kind)
      Qt.callLater(root.pump)
    }
  }
}
