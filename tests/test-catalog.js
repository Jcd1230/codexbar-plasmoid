#!/usr/bin/env node

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(
    path.join(__dirname, "..", "contents", "ui", "code", "catalog.js"),
    "utf8"
).replace(/^\.pragma library$/m, "")
const catalog = {}
vm.createContext(catalog)
vm.runInContext(source, catalog, { filename: "catalog.js" })

const now = Date.parse("2026-08-30T12:00:00Z")
const weeklyExtra = {
    usedPercent: 10,
    windowMinutes: 10080,
    resetsAt: "2026-09-05T00:00:00Z",
}
const sessionExtra = {
    usedPercent: 10,
    windowMinutes: 300,
    resetsAt: "2026-08-30T14:00:00Z",
}

const weeklyMinutes = catalog.effectiveWindowMinutes(
    weeklyExtra, "codex", "extra"
)
assert.equal(weeklyMinutes, 10080)
assert.equal(
    catalog.paceLine(null, weeklyExtra, weeklyMinutes, now, "codex"),
    "Pace: 11% in reserve · Lasts until reset"
)

// A weekly reset 3.5 days from now means 50% of the quota week has elapsed.
const midpointWeek = { usedPercent: 35, resetsAt: new Date(now + 3.5 * 86400000).toISOString() }
assert.equal(catalog.weeklyPaceExpectedPercent(null, midpointWeek, 10080, now), 50)
assert.equal(
    catalog.paceLine(null, midpointWeek, 10080, now, "codex"),
    "Pace: 15% in reserve · Lasts until reset"
)

// The CLI's own pace calculation and the Claude adapter's expectedPct win over
// local elapsed-time calculations. A session or invalid week has no marker.
assert.equal(
    catalog.weeklyPaceExpectedPercent({ expectedUsedPercent: 62 }, midpointWeek, 10080, now),
    62
)
assert.equal(
    catalog.weeklyPaceExpectedPercent(null,
        { usedPercent: 35, resetsAt: midpointWeek.resetsAt, expectedPct: 41 },
        10080, now),
    41
)
assert.equal(catalog.weeklyPaceExpectedPercent(null, midpointWeek, 300, now), -1)
assert.equal(catalog.weeklyPaceExpectedPercent(null, { usedPercent: 35 }, 10080, now), -1)
assert.equal(catalog.weeklyPaceExpectedPercent(null,
    { usedPercent: 35, resetsAt: new Date(now - 1000).toISOString() }, 10080, now), -1)
assert.equal(catalog.weeklyPaceExpectedPercent(null,
    { usedPercent: 35, resetsAt: new Date(now + 8 * 86400000).toISOString() }, 10080, now), -1)
assert.equal(catalog.weeklyPaceExpectedPercent(null,
    { usedPercent: 35, resetsAt: "invalid" }, 10080, now), -1)
assert.equal(catalog.weeklyPaceExpectedPercent(null,
    { usedPercent: 35, expectedPct: 20 }, 10080, now), 20)
assert.equal(catalog.weeklyPaceExpectedPercent(null,
    { usedPercent: 35, usageKnown: false, expectedPct: 20 }, 10080, now), -1)

const sessionMinutes = catalog.effectiveWindowMinutes(
    sessionExtra, "codex", "extra"
)
assert.equal(sessionMinutes, 300)
assert.equal(
    catalog.paceLine(null, sessionExtra, sessionMinutes, now, "codex"),
    ""
)

const resetAt = new Date()
resetAt.setHours(13, 5, 0, 0)
const resetDay = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][resetAt.getDay()]
assert.equal(
    catalog.resetDateTimeText({ resetsAt: resetAt.toISOString() }),
    "Resets " + resetDay + " 1:05 PM"
)
assert.equal(catalog.resetDateTimeText({}), "")

const antigravityUsage = {
    primary: { usedPercent: 76, windowMinutes: 300 },
    secondary: { usedPercent: 0, windowMinutes: 300 },
    extraRateWindows: [
        {
            id: "antigravity-quota-summary-gemini-5h",
            title: "Gemini 5-hour",
            window: { usedPercent: 76, windowMinutes: 300 },
        },
        {
            id: "antigravity-quota-summary-gemini-weekly",
            title: "Gemini weekly",
            window: { usedPercent: 69, windowMinutes: 10080 },
        },
        {
            id: "antigravity-quota-summary-3p-5h",
            title: "Claude/GPT 5-hour",
            window: { usedPercent: 0, windowMinutes: 300 },
        },
        {
            id: "antigravity-quota-summary-3p-weekly",
            title: "Claude/GPT weekly",
            window: { usedPercent: 0, windowMinutes: 10080 },
        },
    ],
}

const antigravityWindows = catalog.antigravityGeminiWindows(antigravityUsage)
assert.equal(antigravityWindows.length, 2)
assert.equal(antigravityWindows[0].id, "antigravity-quota-summary-gemini-5h")
assert.equal(antigravityWindows[1].id, "antigravity-quota-summary-gemini-weekly")
assert.equal(catalog.windowFor(antigravityUsage, "antigravity", 300).usedPercent, 76)
assert.equal(catalog.windowFor(antigravityUsage, "antigravity", 10080).usedPercent, 69)

console.log("Catalog tests passed")
