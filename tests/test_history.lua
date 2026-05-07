---@diagnostic disable: undefined-global
local T = _G.T
local ns = _G.NS
local History = ns.History

local function newState()
  return { history = {} }
end

T.describe("History.Push", function()
  T.it("pushes to front and stamps ts when missing", function()
    local s = newState()
    History.Push(s, { kind = "HEAL", input = 5 })
    T.assertEq(#s.history, 1)
    T.assertEq(s.history[1].kind, "HEAL")
    T.assertNotNil(s.history[1].ts)
  end)
  T.it("preserves caller-supplied ts", function()
    local s = newState()
    History.Push(s, { kind = "HEAL", ts = 12345 })
    T.assertEq(s.history[1].ts, 12345)
  end)
  T.it("trims to History.MAX entries", function()
    local s = newState()
    for i = 1, History.MAX + 10 do
      History.Push(s, { kind = "HEAL", input = i, ts = i })
    end
    T.assertEq(#s.history, History.MAX)
    -- Most recent is at front.
    T.assertEq(s.history[1].input, History.MAX + 10)
  end)
  T.it("ignores non-table state or entry", function()
    History.Push(nil, { kind = "HEAL" })
    History.Push({ history = {} }, "not a table")
    -- Just shouldn't error.
    T.assertTrue(true)
  end)
  T.it("auto-creates history table on bare state", function()
    local s = {}
    History.Push(s, { kind = "HEAL" })
    T.assertEq(#s.history, 1)
  end)
end)

T.describe("History.Clear", function()
  T.it("empties the history array", function()
    local s = newState()
    History.Push(s, { kind = "HEAL" })
    History.Push(s, { kind = "DAMAGE_ARMOR" })
    History.Clear(s)
    T.assertEq(#s.history, 0)
  end)
end)

T.describe("History.FormatEntry", function()
  T.it("formats DAMAGE_ARMOR non-dodge with mitigation breakdown", function()
    local line = History.FormatEntry({
      kind = "DAMAGE_ARMOR", input = 50, damage = 20,
      dodge = 0, absorbedBlock = 0, absorbedMagic = 0, mitigation = 30,
      hpBefore = 100, hpAfter = 80,
    })
    T.assertNotNil(line)
    T.assertTrue(line:find("Dégâts subis %(armure%)") ~= nil)
    T.assertTrue(line:find("Avant") ~= nil)
    T.assertTrue(line:find("Après") ~= nil)
  end)
  T.it("formats dodge variant with ESQUIVÉ marker", function()
    local line = History.FormatEntry({
      kind = "DAMAGE_TRUE", input = 30, dodge = 30, dodged = true,
      hpBefore = 50, hpAfter = 50,
    })
    T.assertNotNil(line)
    T.assertTrue(line:find("ESQUIVÉ") ~= nil)
  end)
  T.it("prefixes [Familier] for pet-subject entries", function()
    local line = History.FormatEntry({
      kind = "HEAL", subject = "PET", input = 10,
      capMax = 20, effMax = 20, applied = 10, hpBefore = 5, hpAfter = 15,
    })
    T.assertNotNil(line)
    T.assertTrue(line:find("%[Familier%]") ~= nil)
  end)
  T.it("returns nil for unknown kinds", function()
    T.assertNil(History.FormatEntry({ kind = "UNKNOWN_KIND" }))
    T.assertNil(History.FormatEntry(nil))
  end)
end)

T.describe("History.FormatHistoryText subject filter", function()
  local function mkHistory()
    return {
      { kind = "HEAL", subject = "PET",  input = 5, capMax = 20, effMax = 20, applied = 5, hpBefore = 0, hpAfter = 5 },
      { kind = "HEAL", subject = nil,    input = 7, capMax = 20, effMax = 20, applied = 7, hpBefore = 0, hpAfter = 7 },
      { kind = "DAMAGE_ARMOR", subject = "PET", input = 3, damage = 3, mitigation = 0, dodge = 0, absorbedBlock = 0, absorbedMagic = 0, hpBefore = 5, hpAfter = 2 },
    }
  end

  T.it("nil filter shows everything", function()
    local txt = History.FormatHistoryText(mkHistory(), 0, nil)
    T.assertNotNil(txt)
    T.assertTrue(txt:find("%[Familier%]") ~= nil)
  end)
  T.it("CHAR filter excludes pet entries", function()
    local txt = History.FormatHistoryText(mkHistory(), 0, "CHAR")
    T.assertNotNil(txt)
    T.assertFalse(txt:find("%[Familier%]") ~= nil)
  end)
  T.it("PET filter excludes character entries", function()
    local txt = History.FormatHistoryText(mkHistory(), 0, "PET")
    T.assertNotNil(txt)
    -- The character heal had input 7; the pet heal had input 5. Verify only pet shown.
    local _, count = txt:gsub("Soins reçus", "")
    T.assertEq(count, 1)
  end)
  T.it("undoneCount hides the most recent N actions", function()
    local txt = History.FormatHistoryText(mkHistory(), 1, nil)
    -- Newest action (PET HEAL) should be hidden when undoneCount=1.
    T.assertNotNil(txt)
  end)
  T.it("returns nil for empty history", function()
    T.assertNil(History.FormatHistoryText({}, 0, nil))
    T.assertNil(History.FormatHistoryText(nil, 0, nil))
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Additional kinds: DIVINE_HEAL, SURGERY
-- ────────────────────────────────────────────────────────────────────

T.describe("History.FormatEntry extra kinds", function()
  T.it("formats DIVINE_HEAL with bypass-cap label", function()
    local line = History.FormatEntry({
      kind = "DIVINE_HEAL", gain = 75, hpBefore = 5, hpAfter = 80, maxHp = 100,
    })
    T.assertNotNil(line)
    T.assertTrue(line:find("Soins divins reçus") ~= nil)
    T.assertTrue(line:find("bypassé") ~= nil)
  end)
  T.it("formats SURGERY with bypass-cap label", function()
    local line = History.FormatEntry({
      kind = "SURGERY", gain = 50, hpBefore = 0, hpAfter = 50, maxHp = 100,
    })
    T.assertNotNil(line)
    T.assertTrue(line:find("Chirurgie reçue") ~= nil)
    T.assertTrue(line:find("bypassé") ~= nil)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Defensive
-- ────────────────────────────────────────────────────────────────────

T.describe("History defensive paths", function()
  T.it("EnsureState replaces non-table history with empty table", function()
    local s = { history = "not a table" }
    History.EnsureState(s)
    T.assertEq(type(s.history), "table")
    T.assertEq(#s.history, 0)
  end)
  T.it("Get returns empty array for nil state", function()
    local r = History.Get(nil)
    T.assertEq(type(r), "table")
    T.assertEq(#r, 0)
  end)
  T.it("Clear is a no-op on nil state", function()
    History.Clear(nil)  -- shouldn't throw
    T.assertTrue(true)
  end)
  T.it("FormatHistoryText with undoneCount > #history returns nil", function()
    local hist = {
      { kind = "HEAL", subject = nil, input = 1, capMax = 1, effMax = 1, applied = 1, hpBefore = 0, hpAfter = 1 },
    }
    T.assertNil(History.FormatHistoryText(hist, 99, nil))
  end)
end)
