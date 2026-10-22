import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Seats for Claude Code: an account switcher built in the image of omarchy.agents: a bar
// icon that opens a panel with the active login, one switch per saved
// account, and every account's rate limits side by side. When the active
// account nears a limit and another one has room, it offers the switch in a
// notification.
Panel {
  id: root
  moduleName: "zorry.seats"
  ipcTarget: "zorry.seats"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string script: Qt.resolvedUrl("seats").toString().replace(/^file:\/\//, "")
  readonly property string home: Quickshell.env("HOME")
  readonly property url claudeMark: "file:///usr/share/omarchy/shell/plugins/agents/assets/claude.svg"

  readonly property bool alertsEnabled: setting("alerts", true) === true
  readonly property real alertAt: Number(setting("alertAt", 90)) / 100
  // Hidden "demo" setting: made-up accounts for screenshots; nothing real is
  // read or switched.
  readonly property bool demo: setting("demo", false) === true

  property var status: ({ current: "", loggedIn: false, liveEmail: "", accounts: [] })
  property var limitData: ({})
  property bool switching: false
  property string switchError: ""
  property int cursorIndex: 0
  property bool cursorActive: false
  property double nowMs: Date.now()
  // Windows already alerted on, keyed by account, window and reset time, so
  // each window nags once per period.
  property var alerted: ({})

  readonly property var accounts: status.accounts || []
  readonly property int activeIndex: {
    for (var i = 0; i < accounts.length; i++) if (accounts[i].name === status.current) return i
    return -1
  }
  readonly property var active: activeIndex >= 0 ? accounts[activeIndex] : null
  // Active account first, then the rest in saved order.
  readonly property var orderedAccounts: {
    var out = active ? [active] : []
    for (var i = 0; i < accounts.length; i++) if (i !== activeIndex) out.push(accounts[i])
    return out
  }
  readonly property var activeLimits: active ? windowsFor(active.name) : []
  readonly property bool alarming: peak(activeLimits) >= alertAt
  // Status and limits load independently; whichever lands last runs the check.
  onActiveLimitsChanged: checkAlerts()

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function titleCase(s) { s = String(s || ""); return s.charAt(0).toUpperCase() + s.slice(1) }

  function planOf(name) {
    var d = limitData[name]
    return d && d.plan ? d.plan : ""
  }

  function heroTitle() {
    if (active) return titleCase(active.name)
    return status.loggedIn ? "Unsaved login" : "Logged out"
  }

  function heroMeta() {
    if (switching) return "Switching…"
    // A personal account's organization is named after its email; the plan says more.
    if (active) {
      var org = active.org && active.org.indexOf(active.email) < 0 ? active.org : planOf(active.name)
      return [active.email, org].filter(function(s) { return s }).join(" · ")
    }
    return status.liveEmail
  }

  function windowTitle(e) {
    if (e.title) return String(e.title)
    var label = String(e.label || "").toLowerCase()
    if (label.indexOf("week") >= 0 || label.indexOf("7-day") >= 0) return "Weekly"
    if (label.indexOf("session") >= 0 || label.indexOf("5-hour") >= 0) return "Session"
    return titleCase(e.label)
  }

  function windowsFor(name) {
    var d = limitData[name]
    if (!d || (switching && name === status.current)) return []
    var out = []
    var list = d.limits || []
    for (var i = 0; i < list.length; i++) {
      var p = Number(list[i].percent)
      if (p >= 0) out.push({ title: windowTitle(list[i]), percent: p, resetAt: String(list[i].resetsAt || ""), reset: !!list[i].reset })
    }
    return out
  }

  function peak(windows) {
    var m = 0
    for (var i = 0; i < windows.length; i++) m = Math.max(m, windows[i].percent)
    return m
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  function freshness(name) {
    var d = limitData[name]
    if (!d) return ""
    if (name === status.current && !d.status) return "ACTIVE"
    if (d.live) return "LIVE"
    if (!(d.fetchedAtMs > 0)) return d.status ? d.status.toUpperCase() : "NO DATA"
    var age = formatDuration(nowMs - d.fetchedAtMs).split(" ")[0]
    return age.toUpperCase() + " AGO"
  }

  function demoStatus(current) {
    return {
      current: current, loggedIn: true, liveEmail: "",
      accounts: [
        { name: "private", email: "you@example.com", org: "", plan: "" },
        { name: "work", email: "you@company.com", org: "Acme Inc", plan: "claude_team" }
      ]
    }
  }

  function demoLimits() {
    var now = Date.now()
    function at(h) { return new Date(now + h * 3600000).toISOString() }
    return {
      work: { plan: "Team", live: true, fetchedAtMs: now, limits: [
        { label: "Session (5-hour)", percent: 0.42, resetsAt: at(2.2) },
        { label: "Weekly (7-day)", percent: 0.61, resetsAt: at(77) } ] },
      private: { plan: "Max 5x", live: false, fetchedAtMs: now - 2 * 3600000, limits: [
        { label: "Session (5-hour)", percent: 0.08, resetsAt: at(3.5) },
        { label: "Weekly (7-day)", percent: 0.93, resetsAt: at(14) } ] }
    }
  }

  function refresh() {
    if (demo) { if (status.accounts.length === 0 || status.current === "") status = demoStatus(String(setting("demoActive", "work"))); return }
    if (!statusProc.running) statusProc.running = true
  }

  function refreshLimits(force) {
    if (demo) { limitData = demoLimits(); checkAlerts(); return }
    if (limitsProc.running) return
    limitsProc.command = [root.script, "limits"].concat(force ? ["--force"] : [])
    limitsProc.running = true
  }

  function switchTo(name) {
    if (switchProc.running || name === status.current) return
    if (demo) { status = demoStatus(name); return }
    switchError = ""
    switching = true
    switchProc.command = [root.script, "use", name]
    switchProc.running = true
  }

  // Logging in needs a browser round-trip and a name, so it runs in a
  // terminal; the credentials watcher picks up the result.
  function login(name, verb) {
    if (!root.bar) return
    var cmd = "'" + root.script + "' " + (verb || "login") + (name ? " '" + name + "'" : "")
    root.bar.run("xdg-terminal-exec --app-id=zorry.seats-login --title=\"Seats: Claude login\" -- bash -c \"" + cmd
      + "; echo; read -n1 -rsp 'Press any key to close'\"")
    root.close()
  }

  // The cursor walks the account buttons plus the trailing "+ Add" button.
  function moveCursor(dx) {
    var n = accounts.length + 1
    cursorActive = true
    cursorIndex = ((cursorIndex + dx) % n + n) % n
  }

  function activateCursor() {
    if (cursorIndex < accounts.length) switchTo(accounts[cursorIndex].name)
    else if (accounts.length === 0 && status.loggedIn) login("", "save")
    else login("")
  }

  // ---------------------------------------------------------------- alerts

  function checkAlerts() {
    if (!alertsEnabled || !active || switching) return
    var windows = activeLimits
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      if (w.percent < alertAt) continue
      // The API's reset time jitters by a second between probes; bucket it.
      var key = active.name + "|" + w.title + "|" + Math.round(new Date(w.resetAt).getTime() / 600000)
      if (alerted[key]) continue
      var next = Object.assign({}, alerted)
      next[key] = true
      alerted = next
      notifyLimit(w, bestAlternative(w.title))
      return
    }
  }

  // The other account with the most room in the same window, as long as it
  // isn't past the alert line itself.
  function bestAlternative(title) {
    var best = null
    var bestPercent = 2
    for (var i = 0; i < accounts.length; i++) {
      var name = accounts[i].name
      if (name === status.current) continue
      var ws = windowsFor(name)
      var p = 0
      for (var j = 0; j < ws.length; j++) if (ws[j].title === title) p = ws[j].percent
      if (p < alertAt && p < bestPercent) { best = { name: name, percent: p }; bestPercent = p }
    }
    return best
  }

  // Omarchy toasts run an argv when clicked, so the alert itself is the
  // switch button.
  function notifyLimit(w, alt) {
    var pct = Math.round(w.percent * 100) + "%"
    var resets = w.resetAt !== "" ? " Resets in " + formatDuration(new Date(w.resetAt).getTime() - Date.now()) + "." : ""
    var title = titleCase(active.name) + " is at " + pct + " of its " + w.title.toLowerCase() + " limit"
    var cmd = ["omarchy-notification-send", "--app-name", "Seats", "-g", "󰀉",
               "-u", w.percent >= 1 ? "critical" : "normal"]
    if (alt) {
      cmd.push(title, "Click to switch to " + titleCase(alt.name) + " (" + Math.round(alt.percent * 100) + "% " + w.title.toLowerCase() + " used)." + resets)
      if (!demo) cmd.push("--exec", root.script, "use", alt.name)
    } else {
      cmd.push(title, (accounts.length > 1 ? "Your other accounts are near their limits too." : "") + resets)
    }
    Quickshell.execDetached(cmd)
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    cursorActive = false
    cursorIndex = Math.max(0, activeIndex)
    refresh()
    refreshLimits(false)
  }

  Process {
    id: statusProc
    command: [root.script, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.status = JSON.parse(text) } catch (e) {} }
    }
  }

  Process {
    id: limitsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.limitData = parsed.accounts || {}
        } catch (e) { return }
        root.nowMs = Date.now()
        root.checkAlerts()
      }
    }
  }

  Process {
    id: switchProc
    stderr: StdioCollector { id: switchErr; waitForEnd: true }
    onExited: function(code) {
      root.switching = false
      root.refresh()
      if (code !== 0) root.switchError = switchErr.text.trim()
      else root.refreshLimits(true)
    }
  }

  // A /login in a terminal rewrites the credentials file; pick that up.
  FileView {
    path: root.home + "/.claude/.credentials.json"
    watchChanges: true
    printErrors: false
    onFileChanged: { root.refresh(); root.refreshLimits(false) }
  }

  Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  // Limits for the alert: the script probes at most every two minutes per
  // account, so this stays well clear of the endpoint's rate limit.
  Timer { interval: 300000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refreshLimits(false) }
  Timer { interval: 30000; running: root.opened; repeat: true; onTriggered: root.nowMs = Date.now() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰀉"
    active: root.alarming
    dimmed: root.status.current === ""
    tooltipText: root.opened ? "" : "Claude: " + (root.active ? root.titleCase(root.active.name) + " · " + root.active.email : root.heroTitle())
    onPressed: function(b) {
      if (b === Qt.MiddleButton && root.accounts.length > 1)
        root.switchTo(root.accounts[(root.activeIndex + 1) % root.accounts.length].name)
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.moveCursor(dx) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshLimits(true) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: Claude mark · account · email/org ----------
        PanelHero {
          width: parent.width
          title: root.heroTitle()
          meta: root.heroMeta()
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Item {
              width: Style.font.display
              height: Style.font.display

              Image {
                id: mark
                anchors.fill: parent
                source: root.claudeMark
                sourceSize.width: Style.font.display * 2
                sourceSize.height: Style.font.display * 2
                fillMode: Image.PreserveAspectFit
              }

              Text {
                anchors.centerIn: parent
                visible: mark.status !== Image.Ready
                text: button.text
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }
        }

        // ---------- Account switch ----------
        Row {
          id: accountSwitch
          width: parent.width
          spacing: Style.spacing.md

          readonly property real addWidth: root.accounts.length > 0 ? Math.max(Style.space(64), addButton.implicitWidth) : width
          readonly property real cellWidth: root.accounts.length > 0
            ? (width - addWidth - spacing * root.accounts.length) / root.accounts.length
            : 0

          Repeater {
            model: root.accounts

            Button {
              required property var modelData
              required property int index

              width: accountSwitch.cellWidth
              text: root.titleCase(modelData.name)
              tooltipText: modelData.email + (modelData.org ? " · " + modelData.org : "") + "\nRight-click to log in again"
              selected: index === root.activeIndex
              hasCursor: root.cursorActive && index === root.cursorIndex
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: {
                root.cursorIndex = index
                root.switchTo(modelData.name)
              }
              onRightClicked: root.login(modelData.name)
              onHovered: function(isHovered) {
                if (isHovered) { root.cursorActive = true; root.cursorIndex = index }
              }
            }
          }

          Button {
            id: addButton
            width: accountSwitch.addWidth
            text: root.accounts.length > 0 ? "+ Add" : (root.status.loggedIn ? "Save this login" : "Log in")
            tooltipText: "Log in with another Claude account in a terminal and save it"
            hasCursor: root.cursorActive && root.cursorIndex === root.accounts.length
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.accounts.length === 0 && root.status.loggedIn ? root.login("", "save") : root.login("")
            onHovered: function(isHovered) {
              if (isHovered) { root.cursorActive = true; root.cursorIndex = root.accounts.length }
            }
          }
        }

        // ---------- Status ----------
        BorderSurface {
          readonly property string message: root.switchError !== "" ? root.switchError
            : root.accounts.length === 0 || root.status.current === ""
              ? (root.status.loggedIn
                  ? "This login isn't saved yet. Use Save this login to give it a name."
                  : "Not logged in to Claude Code.")
              : root.accounts.length === 1
                ? "Only one account saved. Use + Add to log in with your other one."
                : ""
          visible: message !== ""
          width: parent.width
          implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
          color: root.alpha(root.urgent, 0.10)
          borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
          radius: Style.cornerRadius

          Text {
            id: statusText
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            text: parent.message
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Limits, one block per account ----------
        Repeater {
          model: root.orderedAccounts

          Column {
            id: accountBlock
            required property var modelData
            required property int index

            readonly property bool isActive: modelData.name === root.status.current
            readonly property var windows: root.windowsFor(modelData.name)

            width: column.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }

            Item {
              width: parent.width
              implicitHeight: Math.max(blockHeader.implicitHeight, blockState.implicitHeight)

              PanelSectionHeader {
                id: blockHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: (accountBlock.modelData.name + (root.planOf(accountBlock.modelData.name) ? " · " + root.planOf(accountBlock.modelData.name) : "")).toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                id: blockState
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.switching && accountBlock.isActive ? "FETCHING…" : root.freshness(accountBlock.modelData.name)
                color: accountBlock.isActive ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: accountBlock.isActive
              }
            }

            // The active account gets the full Agents-style rows.
            Repeater {
              model: accountBlock.isActive ? accountBlock.windows : []

              LimitRow {
                required property var modelData
                width: accountBlock.width
                window: modelData
              }
            }

            // Others read as a compact table; click to switch to them.
            Item {
              visible: !accountBlock.isActive
              width: parent.width
              implicitHeight: compactRows.implicitHeight

              Column {
                id: compactRows
                width: parent.width
                spacing: Style.spacing.sm

                Repeater {
                  model: accountBlock.isActive ? [] : accountBlock.windows

                  CompactRow {
                    required property var modelData
                    width: compactRows.width
                    window: modelData
                  }
                }

                Text {
                  visible: accountBlock.windows.length === 0
                  textFormat: Text.PlainText
                  width: parent.width
                  text: "No limits yet. Switch to it once to fetch them."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.switchTo(accountBlock.modelData.name)
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          topPadding: Style.space(2)
          text: root.switching ? "Fetching limits for the new account…" : "New Claude sessions use the selected account"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }

  component Meter: Item {
    id: meter
    property real value: 0
    property bool alarming: false
    implicitHeight: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground
      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
  }

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null
    readonly property bool alarming: window && window.percent >= root.alertAt

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        textFormat: Text.PlainText
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        textFormat: Text.PlainText
        text: limitRow.window ? Math.round(limitRow.window.percent * 100) + "%" : "—"
        color: limitRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : 0
      alarming: limitRow.alarming
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: {
        if (!limitRow.window || limitRow.window.resetAt === "") return ""
        var ms = new Date(limitRow.window.resetAt).getTime() - root.nowMs
        return ms > 0 ? "Resets in " + root.formatDuration(ms) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // One line per window: title, meter, percentage. Used for idle accounts.
  component CompactRow: Item {
    id: compactRow
    property var window: null
    readonly property bool alarming: window && window.percent >= root.alertAt

    implicitHeight: Math.max(compactLabel.implicitHeight, compactValue.implicitHeight)

    Text {
      id: compactLabel
      textFormat: Text.PlainText
      text: compactRow.window ? compactRow.window.title : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      width: Style.space(64)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Meter {
      anchors.left: compactLabel.right
      anchors.right: compactValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      value: compactRow.window ? compactRow.window.percent : 0
      alarming: compactRow.alarming
    }

    Text {
      id: compactValue
      textFormat: Text.PlainText
      text: compactRow.window ? (compactRow.window.reset ? "reset" : Math.round(compactRow.window.percent * 100) + "%") : ""
      color: compactRow.alarming ? root.urgent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      width: Style.space(44)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
