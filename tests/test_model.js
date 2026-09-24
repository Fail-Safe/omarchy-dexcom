#!/usr/bin/env node
"use strict"

const fs = require("fs")
const path = require("path")
const vm = require("vm")

const root = path.resolve(__dirname, "..")
const source = fs
  .readFileSync(path.join(root, "DexcomModel.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")

const context = { Date, Math, isFinite, parseInt, String, JSON }
vm.createContext(context)
vm.runInContext(source, context)

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function assertEq(actual, expected, message) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
  }
}

// Trends / display labels
assertEq(context.trendName(null), "None", "null trend")
assertEq(context.trendName(""), "None", "empty trend")
assertEq(context.trendName(4), "Steady", "numeric Flat/Steady")
assertEq(context.trendName("4"), "Steady", "string numeric Flat/Steady")
assertEq(context.trendName("Flat"), "Steady", "Flat alias")
assertEq(context.trendName("FLAT"), "Steady", "FLAT case-insensitive")
assertEq(context.trendName("FortyFiveUp"), "Forty-Five Up", "FortyFiveUp label")
assertEq(context.trendName("fortyFiveDown"), "Forty-Five Down", "fortyFiveDown label")
assertEq(context.trendName("DoubleUp"), "Double-Up", "DoubleUp label")
assertEq(context.trendName("SingleDown"), "Single-Down", "SingleDown label")
assertEq(context.trendName("NotComputable"), "Not Computable", "NotComputable label")
assertEq(context.trendName("RateOutOfRange"), "Rate Out-of-Range", "RateOutOfRange label")
assertEq(context.trendArrow("Flat"), "→", "Flat arrow")
assertEq(context.trendArrow(3), "↗", "FortyFiveUp arrow")
assertEq(context.trendArrow("Double-Up"), "⇈", "Double-Up arrow")
assertEq(context.trendArrow("unknown-trend"), "", "unknown arrow")

// Health bands
assertEq(context.healthLevel(-1, 54, 70, 180, 250), "unknown", "unknown health")
assertEq(context.healthLevel(50, 54, 70, 180, 250), "urgent", "urgent low")
assertEq(context.healthLevel(260, 54, 70, 180, 250), "urgent", "urgent high")
assertEq(context.healthLevel(65, 54, 70, 180, 250), "warn", "warn low")
assertEq(context.healthLevel(200, 54, 70, 180, 250), "warn", "warn high")
assertEq(context.healthLevel(100, 54, 70, 180, 250), "ok", "in range")

assertEq(context.glucoseColor(100, 54, 70, 180, 250), "#22c55e", "ok color")
assertEq(context.glucoseColor(200, 54, 70, 180, 250), "#f59e0b", "warn color")
assertEq(context.glucoseColor(50, 54, 70, 180, 250), "#ef4444", "urgent color")

const colored = context.coloredTrendSegments(
  [
    { epochSec: 0, mgdl: 100 },
    { epochSec: 100, mgdl: 200 },
  ],
  54,
  70,
  180,
  250
)
assert(colored.length >= 2, "crosses high into multiple segments")
assertEq(colored[0].color, "#22c55e", "first segment ok")
assertEq(colored[colored.length - 1].color, "#f59e0b", "last segment warn")

// Units
assertEq(context.normalizeUnit("mmol"), "mmol/L", "normalize mmol")
assertEq(context.normalizeUnit("MMOL/L"), "mmol/L", "normalize MMOL/L")
assertEq(context.normalizeUnit("mg/dL"), "mg/dL", "normalize mg/dL")
assertEq(context.normalizeUnit("nope"), "mg/dL", "unknown unit defaults")
assert(context.isMmol("mmol/L"), "isMmol true")
assert(!context.isMmol("mg/dL"), "isMmol false")
assertEq(context.formatGlucoseNumber(90, "mg/dL"), "90", "mg/dL number")
assertEq(context.formatGlucoseNumber(90, "mmol/L"), "5.0", "mmol number 90")
assertEq(context.formatGlucoseNumber(70, "mmol/L"), "3.9", "mmol number 70")
assertEq(context.formatGlucose(180, "mmol/L"), "10.0 mmol/L", "mmol full")
assertEq(context.formatGlucose(120, "mg/dL"), "120 mg/dL", "mg/dL full")
assertEq(context.formatGlucose(-1, "mmol/L"), "--", "offline format")

// Age / history / stats
assertEq(context.formatAge(-1), "unknown", "age unknown")
assertEq(context.formatAge(45), "45s ago", "age seconds")
assertEq(context.formatAge(120), "2m ago", "age minutes")
assertEq(context.formatAge(7200), "2h ago", "age hours")

const history = context.normalizeHistory([
  { mgdl: 110, epochSec: 200, trend: "Flat", ageSec: 10 },
  { mgdl: 100, epochSec: 100, trend: "SingleUp", ageSec: 20 },
  { mgdl: "bad", epochSec: 300, trend: "Flat" },
])
assertEq(history.length, 2, "normalizeHistory length")
assertEq(history[0].mgdl, 100, "normalizeHistory sort")
assertEq(history[0].trend, "Single-Up", "normalizeHistory trend")
assertEq(history[1].trend, "Steady", "normalizeHistory Flat→Steady")

const windowed = context.historyForHours(
  [
    { mgdl: 100, epochSec: 100 },
    { mgdl: 110, epochSec: 3500 },
  ],
  1,
  4000
)
assertEq(windowed.length, 1, "historyForHours window")
assertEq(windowed[0].mgdl, 110, "historyForHours keeps recent")

const stats = context.historyStats(history)
assertEq(stats.count, 2, "stats count")
assertEq(stats.min, 100, "stats min")
assertEq(stats.max, 110, "stats max")
assertEq(stats.avg, 105, "stats avg")

const bounds = context.chartBounds(history, 70, 180)
assert(bounds.min <= 70, "chartBounds includes low")
assert(bounds.max >= 180, "chartBounds includes high")

const idx = context.nearestPointIndex(
  [
    { epochSec: 0, mgdl: 100 },
    { epochSec: 1800, mgdl: 110 },
    { epochSec: 3600, mgdl: 120 },
  ],
  34 + 50,
  34,
  100,
  1,
  3600
)
assertEq(idx, 1, "nearestPointIndex mid")

// parseFetchPayload
const empty = context.parseFetchPayload("")
assert(!empty.ok && empty.error === "Empty response", "empty payload")

const badJson = context.parseFetchPayload("{nope")
assert(!badJson.ok && badJson.error === "Invalid JSON from fetch helper", "bad json")

const failed = context.parseFetchPayload(JSON.stringify({ ok: false, error: "boom" }))
assert(!failed.ok && failed.error === "boom", "fetch failed")

const missing = context.parseFetchPayload(JSON.stringify({ ok: true }))
assert(!missing.ok && missing.error === "Missing glucose value", "missing mgdl")

const ok = context.parseFetchPayload(
  JSON.stringify({
    ok: true,
    mgdl: 108,
    trend: "Flat",
    stampedAt: "2026-09-24T12:00:00Z",
    ageSec: 42,
    history: [{ mgdl: 108, epochSec: 1000, trend: "Flat", ageSec: 42 }],
  })
)
assert(ok.ok, "ok payload")
assertEq(ok.mgdl, 108, "ok mgdl")
assertEq(ok.trend, "Steady", "ok trend remapped")
assertEq(ok.arrow, "→", "ok arrow")
assertEq(ok.ageSec, 42, "ok age")
assertEq(ok.history.length, 1, "ok history")

console.log("DexcomModel tests passed")
