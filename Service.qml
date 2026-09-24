import QtQuick
import Quickshell
import Quickshell.Io
import "DexcomModel.js" as DexcomModel

Item {
  id: root

  property var settings: ({})
  property int mgdl: -1
  property string trend: "None"
  property string arrow: ""
  property int ageSec: -1
  property string stampedAt: ""
  property var history: []
  property int chartHours: 4
  property bool checking: false
  property bool paused: false
  property string lastError: ""
  property string outputBuffer: ""
  property string errorBuffer: ""
  property bool canceling: false

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string fetchScript: pluginDir + "/dexcom_fetch.py"
  readonly property string credentialsPath: effectiveCredentialsPath()
  readonly property string glucoseUnit: DexcomModel.normalizeUnit(setting("glucoseUnit", "mg/dL"))
  readonly property int intervalSec: boundedInt("refreshIntervalSec", 60, 30, 600)
  readonly property int lowMgdl: boundedInt("lowMgdl", 70, 40, 120)
  readonly property int highMgdl: Math.max(lowMgdl + 1, boundedInt("highMgdl", 180, 120, 300))
  readonly property int urgentLowMgdl: Math.min(lowMgdl, boundedInt("urgentLowMgdl", 54, 40, 80))
  readonly property int urgentHighMgdl: Math.max(highMgdl, boundedInt("urgentHighMgdl", 250, 180, 400))
  readonly property string healthLevel: DexcomModel.healthLevel(mgdl, urgentLowMgdl, lowMgdl, highMgdl, urgentHighMgdl)
  readonly property color healthColor: DexcomModel.healthColor(healthLevel)
  readonly property color badgeTextColor: DexcomModel.badgeTextColor(healthLevel)
  readonly property string glucoseText: DexcomModel.formatGlucose(mgdl, glucoseUnit)
  readonly property string badgeText: mgdl < 0 ? "--" : (DexcomModel.formatGlucoseNumber(mgdl, glucoseUnit) + (arrow !== "" ? " " + arrow : ""))
  readonly property string ageText: DexcomModel.formatAge(ageSec)
  readonly property var chartPoints: DexcomModel.historyForHours(history, chartHours)
  readonly property var chartStats: DexcomModel.historyStats(chartPoints)

  onCredentialsPathChanged: {
    if (!paused) Qt.callLater(root.refresh)
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function boundedInt(name, fallback, minimumValue, maximumValue) {
    var number = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(number)) number = fallback
    return Math.max(minimumValue, Math.min(maximumValue, number))
  }

  function effectiveCredentialsPath() {
    var configured = String(setting("credentialsPath", "")).trim()
    if (configured !== "") return configured
    return Quickshell.env("HOME") + "/.config/omarchy/dexcom-share.json"
  }

  function setChartHours(hours) {
    var value = parseInt(String(hours), 10)
    if (!isFinite(value)) return
    if ([1, 4, 12, 24].indexOf(value) < 0) return
    chartHours = value
  }

  function refresh() {
    if (checking || paused) return
    checking = true
    lastError = ""
    outputBuffer = ""
    errorBuffer = ""
    fetchProcess.command = [
      "python3", fetchScript,
      "--credentials", credentialsPath,
      "--minutes", "1440",
      "--max-count", "288"
    ]
    fetchProcess.running = true
  }

  function togglePause() {
    setPaused(!paused)
  }

  function setPaused(value) {
    var next = value === true
    if (paused === next) return
    paused = next
    if (paused) {
      if (fetchProcess.running) {
        canceling = true
        fetchProcess.running = false
      } else {
        checking = false
      }
    } else {
      refresh()
    }
  }

  function status() {
    return (mgdl < 0 ? "offline" : glucoseText + " " + arrow)
      + (ageSec >= 0 ? " (" + ageText + ")" : "")
      + (history && history.length ? (", " + history.length + " pts") : "")
      + (paused ? ", paused" : (checking ? ", checking" : ""))
      + (lastError !== "" ? ", error=" + lastError : "")
  }

  Process {
    id: fetchProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.outputBuffer = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.errorBuffer = String(text || "").trim().slice(0, 500)
    }
    onExited: function(exitCode) {
      if (root.canceling) {
        root.canceling = false
        root.checking = false
        if (!root.paused) Qt.callLater(root.refresh)
        return
      }
      root.checking = false
      if (root.paused) return
      var result = DexcomModel.parseFetchPayload(root.outputBuffer)
      if (result.ok) {
        root.mgdl = result.mgdl
        root.trend = result.trend
        root.arrow = result.arrow
        root.ageSec = result.ageSec
        root.stampedAt = result.stampedAt
        root.history = result.history || []
        root.lastError = ""
      } else {
        root.mgdl = -1
        root.trend = "None"
        root.arrow = ""
        root.ageSec = -1
        root.stampedAt = ""
        root.history = []
        root.lastError = result.error || (root.errorBuffer !== "" ? root.errorBuffer : ("exit " + exitCode))
      }
    }
  }

  Timer {
    interval: root.intervalSec * 1000
    repeat: true
    running: !root.paused
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "failsafe.dexcom"
    function refresh(): void { root.refresh() }
    function pause(): void { root.setPaused(true) }
    function resume(): void { root.setPaused(false) }
    function status(): string { return root.status() }
  }
}
