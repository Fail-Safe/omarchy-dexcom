.pragma library

var TREND_ARROWS = {
  "None": "",
  "DoubleUp": "⇈",
  "Double-Up": "⇈",
  "SingleUp": "↑",
  "Single-Up": "↑",
  "FortyFiveUp": "↗",
  "Forty-Five Up": "↗",
  "Steady": "→",
  "Flat": "→", // Dexcom Share still emits "Flat"
  "FortyFiveDown": "↘",
  "Forty-Five Down": "↘",
  "SingleDown": "↓",
  "Single-Down": "↓",
  "DoubleDown": "⇊",
  "Double-Down": "⇊",
  "NotComputable": "?",
  "Not Computable": "?",
  "RateOutOfRange": "?",
  "Rate Out-of-Range": "?",
  "1": "⇈",
  "2": "↑",
  "3": "↗",
  "4": "→",
  "5": "↘",
  "6": "↓",
  "7": "⇊",
  "8": "?",
  "9": "?"
}

var TREND_NAMES = {
  "1": "Double-Up",
  "doubleup": "Double-Up",
  "2": "Single-Up",
  "singleup": "Single-Up",
  "3": "Forty-Five Up",
  "fortyfiveup": "Forty-Five Up",
  "4": "Steady",
  "flat": "Steady", // Dexcom Share still emits "Flat"
  "5": "Forty-Five Down",
  "fortyfivedown": "Forty-Five Down",
  "6": "Single-Down",
  "singledown": "Single-Down",
  "7": "Double-Down",
  "doubledown": "Double-Down",
  "8": "Not Computable",
  "notcomputable": "Not Computable",
  "9": "Rate Out-of-Range",
  "rateoutofrange": "Rate Out-of-Range"
}

var RANGE_HOURS = [1, 4, 12, 24]

function trendName(trend) {
  if (trend === undefined || trend === null || trend === "") return "None"
  var key = String(trend)
  if (TREND_NAMES[key]) return TREND_NAMES[key]
  var lower = key.toLowerCase()
  if (TREND_NAMES[lower]) return TREND_NAMES[lower]
  return key
}

function trendArrow(trend) {
  var name = trendName(trend)
  if (TREND_ARROWS[name] !== undefined) return TREND_ARROWS[name]
  if (TREND_ARROWS[String(trend)] !== undefined) return TREND_ARROWS[String(trend)]
  return ""
}

function healthLevel(mgdl, urgentLow, low, high, urgentHigh) {
  if (mgdl < 0) return "unknown"
  if (mgdl <= urgentLow || mgdl >= urgentHigh) return "urgent"
  if (mgdl < low || mgdl > high) return "warn"
  return "ok"
}

function glucoseColor(mgdl, urgentLow, low, high, urgentHigh) {
  return healthColor(healthLevel(mgdl, urgentLow, low, high, urgentHigh))
}

// Split a history polyline into colored segments, cutting at threshold crossings
// so a run through high/low ranges is not painted with the current reading color.
function coloredTrendSegments(points, urgentLow, low, high, urgentHigh) {
  var segments = []
  if (!points || points.length < 2) return segments
  var thresholds = [urgentLow, low, high, urgentHigh]
  for (var i = 1; i < points.length; i++) {
    var a = points[i - 1]
    var b = points[i]
    var mg0 = a.mgdl
    var mg1 = b.mgdl
    var ep0 = a.epochSec
    var ep1 = b.epochSec
    if (!isFinite(mg0) || !isFinite(mg1) || !isFinite(ep0) || !isFinite(ep1)) continue

    var cuts = [0]
    var span = mg1 - mg0
    if (span !== 0) {
      for (var t = 0; t < thresholds.length; t++) {
        var level = thresholds[t]
        if (!isFinite(level)) continue
        if ((mg0 < level && mg1 > level) || (mg0 > level && mg1 < level)) {
          var ratio = (level - mg0) / span
          if (ratio > 0 && ratio < 1) cuts.push(ratio)
        }
      }
    }
    cuts.push(1)
    cuts.sort(function(x, y) { return x - y })

    for (var c = 1; c < cuts.length; c++) {
      var r0 = cuts[c - 1]
      var r1 = cuts[c]
      if (r1 - r0 < 1e-9) continue
      var midRatio = (r0 + r1) / 2
      var midMg = mg0 + span * midRatio
      segments.push({
        epoch0: ep0 + (ep1 - ep0) * r0,
        mgdl0: mg0 + span * r0,
        epoch1: ep0 + (ep1 - ep0) * r1,
        mgdl1: mg0 + span * r1,
        color: glucoseColor(midMg, urgentLow, low, high, urgentHigh)
      })
    }
  }
  return segments
}

// Dexcom Share reports mg/dL. Display may convert with the usual clinical factor.
var MGDL_PER_MMOL = 18.0

function normalizeUnit(unit) {
  var raw = String(unit || "").trim().toLowerCase()
  if (raw === "mmol/l" || raw === "mmol" || raw === "mmoll") return "mmol/L"
  return "mg/dL"
}

function isMmol(unit) {
  return normalizeUnit(unit) === "mmol/L"
}

function mgdlToDisplay(mgdl, unit) {
  if (!isFinite(mgdl) || mgdl < 0) return NaN
  if (isMmol(unit)) return mgdl / MGDL_PER_MMOL
  return mgdl
}

function formatGlucoseNumber(mgdl, unit) {
  var value = mgdlToDisplay(mgdl, unit)
  if (!isFinite(value)) return "--"
  if (isMmol(unit)) return (Math.round(value * 10) / 10).toFixed(1)
  return String(Math.round(value))
}

function formatGlucose(mgdl, unit) {
  if (!isFinite(mgdl) || mgdl < 0) return "--"
  return formatGlucoseNumber(mgdl, unit) + " " + normalizeUnit(unit)
}

function healthColor(level) {
  if (level === "urgent") return "#ef4444"
  if (level === "warn") return "#f59e0b"
  if (level === "ok") return "#22c55e"
  return "#6b7280"
}

function badgeTextColor(level) {
  if (level === "warn") return "#111827"
  return "#ffffff"
}

function formatAge(seconds) {
  if (seconds < 0) return "unknown"
  if (seconds < 60) return seconds + "s ago"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  return hours + "h ago"
}

function normalizeHistory(rawHistory) {
  var points = []
  if (!rawHistory || !rawHistory.length) return points
  for (var i = 0; i < rawHistory.length; i++) {
    var item = rawHistory[i]
    if (!item) continue
    var mgdl = parseInt(item.mgdl, 10)
    var epoch = parseInt(item.epochSec, 10)
    if (!isFinite(mgdl) || !isFinite(epoch)) continue
    points.push({
      mgdl: mgdl,
      epochSec: epoch,
      trend: trendName(item.trend),
      ageSec: isFinite(parseInt(item.ageSec, 10)) ? parseInt(item.ageSec, 10) : -1
    })
  }
  points.sort(function(a, b) { return a.epochSec - b.epochSec })
  return points
}

function historyForHours(history, hours, nowSec) {
  var points = history || []
  var windowSec = Math.max(1, hours) * 3600
  var cutoff = (isFinite(nowSec) ? nowSec : Math.floor(Date.now() / 1000)) - windowSec
  var filtered = []
  for (var i = 0; i < points.length; i++) {
    if (points[i].epochSec >= cutoff) filtered.push(points[i])
  }
  return filtered
}

function historyStats(points) {
  if (!points || points.length === 0) {
    return { count: 0, min: -1, max: -1, avg: -1 }
  }
  var min = points[0].mgdl
  var max = points[0].mgdl
  var total = 0
  for (var i = 0; i < points.length; i++) {
    var value = points[i].mgdl
    if (value < min) min = value
    if (value > max) max = value
    total += value
  }
  return {
    count: points.length,
    min: min,
    max: max,
    avg: Math.round(total / points.length)
  }
}

function chartBounds(points, lowMgdl, highMgdl) {
  var stats = historyStats(points)
  var min = stats.min < 0 ? lowMgdl : Math.min(stats.min, lowMgdl)
  var max = stats.max < 0 ? highMgdl : Math.max(stats.max, highMgdl)
  min = Math.max(40, Math.floor((min - 20) / 10) * 10)
  max = Math.min(400, Math.ceil((max + 20) / 10) * 10)
  if (max <= min) max = min + 40
  return { min: min, max: max }
}


function nearestPointIndex(points, mouseX, padL, plotW, hours, nowSec) {
  if (!points || points.length === 0 || plotW <= 0) return -1
  var windowSec = Math.max(1, hours) * 3600
  var xMin = (isFinite(nowSec) ? nowSec : Math.floor(Date.now() / 1000)) - windowSec
  var xMax = isFinite(nowSec) ? nowSec : Math.floor(Date.now() / 1000)
  var ratio = (mouseX - padL) / plotW
  if (ratio < -0.05 || ratio > 1.05) return -1
  var targetEpoch = xMin + Math.max(0, Math.min(1, ratio)) * (xMax - xMin)
  var best = 0
  var bestDist = Math.abs(points[0].epochSec - targetEpoch)
  for (var i = 1; i < points.length; i++) {
    var dist = Math.abs(points[i].epochSec - targetEpoch)
    if (dist < bestDist) {
      best = i
      bestDist = dist
    }
  }
  return best
}

function formatClock(epochSec) {
  if (!isFinite(epochSec) || epochSec <= 0) return ""
  var d = new Date(epochSec * 1000)
  var h = d.getHours()
  var m = d.getMinutes()
  var ampm = h >= 12 ? "PM" : "AM"
  var hr = h % 12
  if (hr === 0) hr = 12
  var mm = m < 10 ? "0" + m : String(m)
  return hr + ":" + mm + " " + ampm
}

function parseFetchPayload(raw) {
  var text = String(raw || "").trim()
  if (!text) return { ok: false, error: "Empty response" }
  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return { ok: false, error: "Invalid JSON from fetch helper" }
  }
  if (!data || data.ok !== true) {
    return { ok: false, error: (data && data.error) ? String(data.error) : "Fetch failed" }
  }
  var mgdl = parseInt(data.mgdl, 10)
  if (!isFinite(mgdl)) return { ok: false, error: "Missing glucose value" }
  return {
    ok: true,
    mgdl: mgdl,
    trend: trendName(data.trend),
    arrow: trendArrow(data.trend),
    stampedAt: data.stampedAt ? String(data.stampedAt) : "",
    ageSec: isFinite(parseInt(data.ageSec, 10)) ? parseInt(data.ageSec, 10) : -1,
    history: normalizeHistory(data.history),
    error: ""
  }
}
