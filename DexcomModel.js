.pragma library

var TREND_ARROWS = {
  "None": "",
  "DoubleUp": "⇈",
  "SingleUp": "↑",
  "FortyFiveUp": "↗",
  "Flat": "→",
  "FortyFiveDown": "↘",
  "SingleDown": "↓",
  "DoubleDown": "⇊",
  "NotComputable": "?",
  "RateOutOfRange": "?",
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
  "1": "DoubleUp",
  "2": "SingleUp",
  "3": "FortyFiveUp",
  "4": "Flat",
  "5": "FortyFiveDown",
  "6": "SingleDown",
  "7": "DoubleDown",
  "8": "NotComputable",
  "9": "RateOutOfRange"
}

var RANGE_HOURS = [1, 4, 12, 24]

function trendName(trend) {
  if (trend === undefined || trend === null || trend === "") return "None"
  var key = String(trend)
  if (TREND_NAMES[key]) return TREND_NAMES[key]
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
  try {
    var data = JSON.parse(text)
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
