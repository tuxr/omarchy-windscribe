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
  property var staticLocations: []
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
  readonly property int cliDeadlineSec: 20
  readonly property int maxFieldChars: 240
  readonly property int maxLocations: 400

  property var _queue: []
  property string _kind: ""
  property var _job: null
  property int _retries: 0
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

  function pluginFile(rel) {
    var url = Qt.resolvedUrl(rel).toString()
    if (url.indexOf("file://") === 0)
      url = decodeURIComponent(url.slice(7))
    return url
  }

  function boundedCommand(args) {
    return [pluginFile("scripts/run-bounded.py")].concat(args)
  }

  // CLI strings can land in QML Text (default AutoText). Strip markup and
  // cap length before any UI property sees them.
  function clipText(value, max) {
    var limit = max || maxFieldChars
    var text = String(value || "")
    text = text.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
    text = text.replace(/[<>]/g, "")
    if (text.length > limit) text = text.slice(0, limit)
    return text
  }

  function enqueue(args, kind) {
    if (!args || args.length === 0) return
    _queue.push({ args: args, kind: kind || "action" })
    pump()
  }

  function pump() {
    if (cli.running || _queue.length === 0) return
    var job = _queue.shift()
    _job = job
    _kind = job.kind
    cli.command = boundedCommand(job.args)
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
    _wantLists = true
    enqueue(["windscribe-cli", "status"], "status")
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
    actionStatus = t === "best" ? "Connecting to best location…" : ("Connecting to " + t.replace(/^static:/, "") + "…")
    var cmd
    if (t.indexOf("static:") === 0)
      cmd = ["windscribe-cli", "connect", "static", t.slice(7)]
    else
      cmd = ["windscribe-cli", "connect", t]
    if (protocolSetting !== "" && t.indexOf("static:") !== 0) cmd.push(protocolSetting)
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

  function pinIp() {
    if (!installed || !loggedIn || !connected) return
    lastError = ""
    actionStatus = "Pinning current IP…"
    enqueue(["windscribe-cli", "ip", "fav"], "action")
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
    connectState = clipText(stateMatch ? stateMatch[1].trim() : "Unknown")

    var usageMatch = text.match(/Data usage:\s*(.+)/)
    if (usageMatch) dataUsage = clipText(usageMatch[1].trim(), 80)

    if (connectState.indexOf("Connected") === 0) {
      var locMatch = connectState.match(/Connected:\s*(.+)$/)
      locationName = locMatch ? clipText(locMatch[1].trim()) : ""
      var protoMatch = text.match(/Protocol:\s*(.+)/)
      if (protoMatch) protocolText = clipText(protoMatch[1].trim(), 80)
      var vpnIpMatch = text.match(/VPN IP:\s*(\S+)/)
      if (vpnIpMatch) publicIp = clipText(vpnIpMatch[1], 80)
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
        full: clipText(label),
        region: "",
        city: "",
        nickname: clipText(nickname, 80),
        speed: clipText(speed, 40),
        target: "best",
        isBest: true,
        title: "Best location",
        subtitle: clipText(nickname !== "" ? (nickname + (speed !== "" ? " · " + speed : "")) : speed)
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
      full: clipText(label),
      region: clipText(region, 80),
      city: clipText(city, 80),
      nickname: clipText(nickname, 80),
      speed: clipText(speed, 40),
      target: clipText(nickname !== "" ? nickname : (city !== "" ? city : label), 80),
      isBest: false,
      title: clipText(title, 80),
      subtitle: clipText(bits.join(" · "))
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
      else if (result.length < maxLocations) result.push(loc)
    }
    return { locations: result, best: best }
  }

  function handleExit(exitCode, out, err, kind) {
    var failed = exitCode !== 0
    var timedOut = exitCode === 124
    var msg = clipText(String(err || out || "").trim())
    if (timedOut) {
      if (kind === "action") {
        _desired = -1
        actionStatus = ""
      }
      lastError = "windscribe-cli timed out"
      return
    }
    if (failed && /already running/i.test(msg)) {
      if (_retries < 3 && _job) {
        _retries += 1
        _queue = [_job].concat(_queue)
        retryTimer.restart()
      } else {
        _retries = 0
        if (kind === "action") {
          _desired = -1
          actionStatus = ""
          lastError = "Windscribe CLI was busy. Try again."
        }
      }
      return
    }
    _retries = 0

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
        enqueue(["windscribe-cli", "locations", "static"], "static")
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

    if (kind === "static") {
      if (failed) return
      staticLocations = parseLocationList(out, false).locations
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
    interval: (root.cliDeadlineSec + 2) * 1000
    repeat: false
    onTriggered: {
      if (cli.running) {
        var kind = root._kind
        cli.running = false
        if (kind === "action") {
          root._desired = -1
          root.actionStatus = ""
        }
        root.lastError = "windscribe-cli timed out"
        root._kind = ""
        root._job = null
        Qt.callLater(root.pump)
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 2000
    repeat: false
    onTriggered: root.pump()
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
