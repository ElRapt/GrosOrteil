---@diagnostic disable: undefined-global
-- Group damage/heal meter: pure aggregation (RaidMeter), the Core counters
-- feeding it, the comm payload carrying them, and the raid panel's
-- drag-to-reorder helpers.
local T = _G.T
local ns = _G.NS
local RaidMeter = ns.RaidMeter
local RaidPanel = ns.RaidPanel
local Core      = ns.Core
local Comm      = ns.Comm

local function reset()
  Core.ResetToDefaults()
end

-- Fabricated cache for the pure-aggregation tests.
local function fakeRoster()
  local states = {
    Alice = { classKey = "MAGE",    meter = { dmg = 100, heal = 50 } },
    Bob   = { classKey = "WARRIOR", meter = { dmg = 40,  heal = 0  } },
    Cleo  = { classKey = "PRIEST",  meter = { dmg = 0,   heal = 80 } },
    Dan   = { classKey = "ROGUE" },  -- old client: no meter counters
  }
  local members = {
    { name = "Alice" }, { name = "Bob" }, { name = "Cleo" },
    { name = "Dan" }, { name = "Eve" },   -- Eve: no state at all
  }
  local function getState(n) return states[n] end
  return members, getState, states
end

T.describe("RaidMeter.GetTotals", function()
  T.it("tolerates nil, junk and missing meter tables", function()
    local d, h = RaidMeter.GetTotals(nil)
    T.assertEq(d, 0); T.assertEq(h, 0)
    d, h = RaidMeter.GetTotals({})
    T.assertEq(d, 0); T.assertEq(h, 0)
    d, h = RaidMeter.GetTotals({ meter = "junk" })
    T.assertEq(d, 0); T.assertEq(h, 0)
    d, h = RaidMeter.GetTotals({ meter = { dmg = "12", heal = nil } })
    T.assertEq(d, 12); T.assertEq(h, 0)
  end)
end)

T.describe("RaidMeter.BuildRows", function()
  T.it("damage mode: sorts desc, drops zeros / missing states / old clients", function()
    local members, getState = fakeRoster()
    local r = RaidMeter.BuildRows(members, getState, nil, "damage")
    T.assertEq(#r.rows, 2)
    T.assertEq(r.rows[1].name, "Alice")
    T.assertEq(r.rows[1].value, 100)
    T.assertEq(r.rows[2].name, "Bob")
    T.assertEq(r.rows[2].value, 40)
    T.assertEq(r.total, 140)
    T.assertEq(r.maxValue, 100)
  end)

  T.it("heal mode switches the counter and re-sorts", function()
    local members, getState = fakeRoster()
    local r = RaidMeter.BuildRows(members, getState, nil, "heal")
    T.assertEq(#r.rows, 2)
    T.assertEq(r.rows[1].name, "Cleo")
    T.assertEq(r.rows[1].value, 80)
    T.assertEq(r.rows[2].name, "Alice")
    T.assertEq(r.rows[2].value, 50)
    T.assertEq(r.total, 130)
  end)

  T.it("computes shares against the group total", function()
    local members, getState = fakeRoster()
    local r = RaidMeter.BuildRows(members, getState, nil, "damage")
    T.assertNear(r.rows[1].share, 100 / 140, 1e-9)
    T.assertNear(r.rows[2].share, 40 / 140, 1e-9)
  end)

  T.it("subtracts baselines and clamps below-zero deltas away", function()
    local members, getState = fakeRoster()
    local baselines = { alice = { dmg = 90, heal = 0 } }
    local r = RaidMeter.BuildRows(members, getState, baselines, "damage")
    T.assertEq(r.rows[1].name, "Bob")     -- 40 beats Alice's delta of 10
    T.assertEq(r.rows[2].name, "Alice")
    T.assertEq(r.rows[2].value, 10)
    baselines.alice.dmg = 150              -- above current → filtered out
    r = RaidMeter.BuildRows(members, getState, baselines, "damage")
    T.assertEq(#r.rows, 1)
    T.assertEq(r.rows[1].name, "Bob")
  end)

  T.it("collapses duplicate members on the normalized key", function()
    local _, getState = fakeRoster()
    local members = { { name = "Alice" }, { name = "Alice-Realm" }, { name = "ALICE" } }
    local r = RaidMeter.BuildRows(members, getState, nil, "damage")
    T.assertEq(#r.rows, 1)
  end)

  T.it("breaks value ties by key for a stable order", function()
    local states = {
      Zed = { meter = { dmg = 10, heal = 0 } },
      Ann = { meter = { dmg = 10, heal = 0 } },
    }
    local members = { { name = "Zed" }, { name = "Ann" } }
    local r = RaidMeter.BuildRows(members, function(n) return states[n] end, nil, "damage")
    T.assertEq(r.rows[1].name, "Ann")
    T.assertEq(r.rows[2].name, "Zed")
  end)

  T.it("handles empty input", function()
    local r = RaidMeter.BuildRows(nil, nil, nil, "damage")
    T.assertEq(#r.rows, 0)
    T.assertEq(r.total, 0)
    T.assertEq(r.maxValue, 0)
  end)
end)

T.describe("RaidMeter.Reset", function()
  T.it("zeroes the display, then shows only post-reset deltas", function()
    local members, getState, states = fakeRoster()
    local baselines = RaidMeter.Reset(members, getState, {})
    local r = RaidMeter.BuildRows(members, getState, baselines, "damage")
    T.assertEq(#r.rows, 0)
    r = RaidMeter.BuildRows(members, getState, baselines, "heal")
    T.assertEq(#r.rows, 0)
    states.Alice.meter.dmg = 120  -- +20 since reset
    r = RaidMeter.BuildRows(members, getState, baselines, "damage")
    T.assertEq(#r.rows, 1)
    T.assertEq(r.rows[1].name, "Alice")
    T.assertEq(r.rows[1].value, 20)
  end)

  T.it("skips members without a state and keeps old baselines", function()
    local members, getState = fakeRoster()
    local baselines = { eve = { dmg = 7, heal = 7 } }
    RaidMeter.Reset(members, getState, baselines)
    T.assertEq(baselines.eve.dmg, 7)     -- Eve has no state → untouched
    T.assertNotNil(baselines.alice)
  end)
end)

T.describe("Core meter counters", function()
  T.it("start at zero on a fresh state", function()
    reset()
    local d, h = RaidMeter.GetTotals(Core.state)
    T.assertEq(d, 0); T.assertEq(h, 0)
  end)

  T.it("accumulate effective damage taken (mitigation applied)", function()
    reset()
    Core.DamageTrue(10)
    T.assertEq(Core.state.meter.dmg, 10)
    Core.SetArmor(3, 0)
    Core.DamageWithArmor(10)             -- 10 - 3 armor = 7
    T.assertEq(Core.state.meter.dmg, 17)
  end)

  T.it("ignore dodged hits", function()
    reset()
    Core.SetDodge(10)
    Core.DamageTrue(5)                   -- 5 <= dodge → fully dodged
    T.assertEq(Core.state.meter.dmg, 0)
  end)

  T.it("never count received/self/divine/pet heals (heal = heals GIVEN)", function()
    reset()
    Core.SetHP(10, 100)
    Core.Heal(100)                       -- self heal
    Core.DivineHeal()                    -- divine self heal
    Core.HealFrom(10, "Healer")          -- received from someone else
    Core.SetPetEnabled(true)
    Core.SetPetHP(5, 20)
    Core.PetHeal(5)                      -- pet heal
    T.assertEq(Core.state.meter.heal, 0)
  end)

  T.it("credit pet damage to the owner", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetHP(20, 20)
    Core.PetDamageTrue(5)
    T.assertEq(Core.state.meter.dmg, 5)
  end)

  T.it("roll back with undo and return with redo", function()
    reset()
    Core.DamageTrue(10)
    T.assertEq(Core.state.meter.dmg, 10)
    Core.Undo()
    local d = RaidMeter.GetTotals(Core.state)
    T.assertEq(d, 0)
    Core.Redo()
    T.assertEq(Core.state.meter.dmg, 10)
  end)
end)

T.describe("Heals given (heal-others handshake)", function()
  local Heal = ns.Heal

  T.it("Core.CreditHealGiven accumulates and sanitizes", function()
    reset()
    Core.CreditHealGiven(15)
    Core.CreditHealGiven(5)
    Core.CreditHealGiven(-3)             -- ignored
    Core.CreditHealGiven("junk")         -- ignored
    T.assertEq(Core.state.meter.heal, 20)
  end)

  T.it("OnResponse credits only accepted heals", function()
    reset()
    Heal:OnResponse("Bob", true, 15)
    T.assertEq(Core.state.meter.heal, 15)
    Heal:OnResponse("Bob", false, 10)    -- refused → no credit
    T.assertEq(Core.state.meter.heal, 15)
  end)

  T.it("Accept reports the amount actually applied (wound cap)", function()
    reset()
    Core.SetHP(10, 100)                  -- 10% → wound cap 25 HP
    local sent
    local orig = Comm.SendHealResponse
    Comm.SendHealResponse = function(_, healer, accepted, amount)
      sent = { healer = healer, accepted = accepted, amount = amount }
    end
    Heal.Accept("Bob", 100)              -- only 15 HP can land
    Comm.SendHealResponse = orig
    T.assertEq(Core.state.hp, 25)
    T.assertNotNil(sent)
    T.assertEq(sent.accepted, true)
    T.assertEq(sent.amount, 15)
    T.assertEq(Core.state.meter.heal, 0) -- recipient is not credited
  end)

  T.it("undo rolls a credit back", function()
    reset()
    Core.CreditHealGiven(7)
    T.assertEq(Core.state.meter.heal, 7)
    Core.Undo()
    local _, h = RaidMeter.GetTotals(Core.state)
    T.assertEq(h, 0)
  end)
end)

T.describe("Comm payload carries the meter", function()
  T.it("round-trips both counters", function()
    reset()
    Core.DamageTrue(10)
    Core.CreditHealGiven(5)
    local serialized = Comm.SerializeState(Core.state)
    T.assertNotNil(serialized)
    local out = Comm:DeserializeState("STATE_DATA", serialized, "Tester")
    T.assertNotNil(out)
    T.assertEq(out.meter.dmg, 10)
    T.assertEq(out.meter.heal, 5)
  end)

  T.it("defaults to zeros when the sender state has no counters", function()
    reset()
    Core.state.meter = nil
    local serialized = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", serialized, "Tester")
    T.assertEq(out.meter.dmg, 0)
    T.assertEq(out.meter.heal, 0)
  end)
end)

T.describe("RaidPanel drag-to-reorder helpers", function()
  local function names(list)
    local out = {}
    for i, m in ipairs(list) do out[i] = m.name end
    return out
  end

  T.it("moveInList moves forward, backward, and to the edges", function()
    local L = { "A", "B", "C" }
    T.assertEq(table.concat(RaidPanel._moveInList(L, 1, 3), ""), "BAC")
    T.assertEq(table.concat(RaidPanel._moveInList(L, 1, 4), ""), "BCA")
    T.assertEq(table.concat(RaidPanel._moveInList(L, 3, 1), ""), "CAB")
    T.assertEq(table.concat(RaidPanel._moveInList(L, 2, 2), ""), "ABC")
    T.assertEq(table.concat(RaidPanel._moveInList(L, 2, 99), ""), "ACB")
    T.assertEq(table.concat(RaidPanel._moveInList(L, 9, 1), ""), "ABC")
  end)

  T.it("applySavedOrder puts saved keys first, appends the rest", function()
    local members = { { name = "Alice" }, { name = "Bob" }, { name = "Cleo" } }
    local out = RaidPanel._applySavedOrder(members, { "cleo", "alice" })
    T.assertEq(table.concat(names(out), ","), "Cleo,Alice,Bob")
  end)

  T.it("applySavedOrder ignores unknown keys and matches across realms", function()
    local members = { { name = "Bob-KirinTor" }, { name = "Alice" } }
    local out = RaidPanel._applySavedOrder(members, { "ghost", "bob" })
    T.assertEq(out[1].name, "Bob-KirinTor")
    T.assertEq(out[2].name, "Alice")
  end)

  T.it("applySavedOrder is a no-op for nil/empty orders", function()
    local members = { { name = "Alice" }, { name = "Bob" } }
    T.assertEq(RaidPanel._applySavedOrder(members, nil), members)
    T.assertEq(RaidPanel._applySavedOrder(members, {}), members)
  end)

  T.it("dropIndexFromOffset follows the midpoint rule", function()
    local slots = { { top = 0, h = 30 }, { top = 37, h = 30 } }
    T.assertEq(RaidPanel._dropIndexFromOffset(slots, -5), 1)
    T.assertEq(RaidPanel._dropIndexFromOffset(slots, 14), 1)
    T.assertEq(RaidPanel._dropIndexFromOffset(slots, 16), 2)
    T.assertEq(RaidPanel._dropIndexFromOffset(slots, 51), 2)
    T.assertEq(RaidPanel._dropIndexFromOffset(slots, 53), 3)
    T.assertEq(RaidPanel._dropIndexFromOffset({}, 10), 1)
  end)

  T.it("saveOrder persists normalized keys readable by getSavedOrder", function()
    RaidPanel._saveOrder({ "Cleo", "Alice-Realm", "  " })
    local order = RaidPanel._getSavedOrder()
    T.assertNotNil(order)
    T.assertEq(order[1], "cleo")
    T.assertEq(order[2], "alice")
    RaidPanel._saveOrder({})  -- leave a clean slate for other tests
  end)
end)
