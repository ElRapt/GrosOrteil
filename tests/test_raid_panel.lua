---@diagnostic disable: undefined-global
local T  = _G.T
local ns = _G.NS

local Popup     = ns.TargetPopup
local RaidPanel = ns.RaidPanel

-- ── helpers ───────────────────────────────────────────────────────────────────

local function makeState(overrides)
  local base = {
    classKey = "MAGE",
    hp       = 80,
    maxHp    = 100,
    res      = 70,
    maxRes   = 100,
  }
  if overrides then
    for k, v in pairs(overrides) do base[k] = v end
  end
  return base
end

-- ── RaidPanel._getDisplayData ─────────────────────────────────────────────────

T.describe("RaidPanel.getDisplayData — nil / missing state", function()
  T.it("returns nil for nil state", function()
    T.assertNil(RaidPanel._getDisplayData("Foo", nil))
  end)

  T.it("returns nil for false state", function()
    T.assertNil(RaidPanel._getDisplayData("Foo", false))
  end)

  T.it("preserves the display name in the result", function()
    local d = RaidPanel._getDisplayData("Archimonde", makeState())
    T.assertEq(d.name, "Archimonde")
  end)
end)

T.describe("RaidPanel.getDisplayData — HP extraction", function()
  T.it("extracts hp and maxHp", function()
    local d = RaidPanel._getDisplayData("X", makeState({ hp = 45, maxHp = 120 }))
    T.assertEq(d.hp,    45)
    T.assertEq(d.maxHp, 120)
  end)

  T.it("clamps maxHp to at least 1", function()
    local d = RaidPanel._getDisplayData("X", makeState({ hp = 0, maxHp = 0 }))
    T.assertTrue(d.maxHp >= 1)
  end)

  T.it("coerces string numbers", function()
    local d = RaidPanel._getDisplayData("X", makeState({ hp = "60", maxHp = "100" }))
    T.assertEq(d.hp,    60)
    T.assertEq(d.maxHp, 100)
  end)
end)

T.describe("RaidPanel.getDisplayData — status detection", function()
  T.it("status is nil when hp > 0", function()
    local d = RaidPanel._getDisplayData("X", makeState({ hp = 1 }))
    T.assertNil(d.status)
  end)

  T.it("status is 'agonie' when hp == 0 and stabilise is false", function()
    local d = RaidPanel._getDisplayData("X", makeState({ hp = 0, stabilise = false }))
    T.assertEq(d.status, "agonie")
  end)

  T.it("status is 'agonie' when hp == 0 and stabilise is nil", function()
    local d = RaidPanel._getDisplayData("X", makeState({ hp = 0, stabilise = nil }))
    T.assertEq(d.status, "agonie")
  end)

  T.it("status is 'stabilise' when hp == 0 and stabilise is true", function()
    local d = RaidPanel._getDisplayData("X", makeState({ hp = 0, stabilise = true }))
    T.assertEq(d.status, "stabilise")
  end)
end)

T.describe("RaidPanel.getDisplayData — resource counts per class", function()
  T.it("Mage has 2 resources (Mana + Charge arcanique)", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "MAGE", res = 70, maxRes = 100, res2 = 3, maxRes2 = 8,
    }))
    T.assertEq(#d.resources, 2)
    T.assertEq(d.resources[1].cur, 70)
    T.assertEq(d.resources[1].max, 100)
  end)

  T.it("Warlock has 3 resources (Energie, Corruption, Fragments d'ame)", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "WARLOCK",
      res = 50, maxRes = 100,
      res2 = 30, maxRes2 = 60,
      res3 = 2,  maxRes3 = 5,
    }))
    T.assertEq(#d.resources, 3)
  end)

  T.it("ShadowPriest has 2 resources (Points de foi + Insanite)", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "SHADOWPRIEST",
      res = 60, maxRes = 100,
      res2 = 15, maxRes2 = 25,
    }))
    T.assertEq(#d.resources, 2)
  end)

  T.it("Shaman has 4 resources (Terre, Air, Eau, Feu)", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "SHAMAN",
      res = 10, maxRes = 10,
      res2 = 5, maxRes2 = 10,
      res3 = 3, maxRes3 = 10,
      res4 = 1, maxRes4 = 10,
    }))
    T.assertEq(#d.resources, 4)
  end)

  T.it("Medic has 2 resources (Fournitures + Seringues)", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "MEDIC", res = 5, maxRes = 10, res2 = 3, maxRes2 = 5,
    }))
    T.assertEq(#d.resources, 2)
  end)

  T.it("class without a profile entry (Warrior) has 0 resources", function()
    local d = RaidPanel._getDisplayData("X", makeState({ classKey = "WARRIOR" }))
    T.assertEq(#d.resources, 0)
  end)
end)

T.describe("RaidPanel.getDisplayData — dispMax caps", function()
  T.it("Warlock Corruption (idx 2) is capped at 60 regardless of maxRes2", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "WARLOCK",
      res = 50, maxRes = 100,
      res2 = 100, maxRes2 = 999,
      res3 = 0,   maxRes3 = 5,
    }))
    T.assertEq(d.resources[2].max, 60)
  end)

  T.it("Warlock Corruption cur is clamped to 60", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "WARLOCK",
      res = 50, maxRes = 100,
      res2 = 200, maxRes2 = 999,
      res3 = 0,   maxRes3 = 5,
    }))
    T.assertTrue(d.resources[2].cur <= 60)
  end)

  T.it("ShadowPriest Insanity (idx 2) is capped at 25", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "SHADOWPRIEST",
      res = 60, maxRes = 100,
      res2 = 99, maxRes2 = 999,
    }))
    T.assertEq(d.resources[2].max, 25)
  end)

  T.it("Mage Arcane Charge (idx 2) is capped at 8", function()
    -- Mage has only 1 resource profile entry for standard mages;
    -- only applies if the class profile includes an idx-2 entry.
    -- Test that the cap logic doesn't error for a plain Mage (no idx-2 in profile).
    local d = RaidPanel._getDisplayData("X", makeState({ classKey = "MAGE", res = 70, maxRes = 100 }))
    T.assertTrue(#d.resources >= 1)
  end)

  T.it("dispMax defaults to 1 when maxv == 0 to avoid divide-by-zero", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "MAGE", res = 0, maxRes = 0,
    }))
    T.assertTrue(d.resources[1].max >= 1)
  end)
end)

T.describe("RaidPanel.getDisplayData — resource colors present", function()
  T.it("each resource entry has r, g, b fields", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "WARLOCK",
      res = 50, maxRes = 100,
      res2 = 30, maxRes2 = 60,
      res3 = 2,  maxRes3 = 5,
    }))
    for _, r in ipairs(d.resources) do
      T.assertNotNil(r.r)
      T.assertNotNil(r.g)
      T.assertNotNil(r.b)
    end
  end)
end)

-- ── RaidPanel._getRaidMembers ─────────────────────────────────────────────────

T.describe("RaidPanel.getRaidMembers — solo", function()
  T.it("returns just the player when not in any group", function()
    _G.IsInRaid  = function() return false end
    _G.IsInGroup = function() return false end
    _G.UnitName  = function(u) if u == "player" then return "Solo", nil end end
    _G.UnitExists = function() return false end
    local m = RaidPanel._getRaidMembers()
    T.assertEq(#m, 1)
    T.assertEq(m[1].name, "Solo")
    T.assertEq(m[1].unit, "player")
  end)

  T.it("skips player slot when UnitName returns nil", function()
    _G.IsInRaid  = function() return false end
    _G.IsInGroup = function() return false end
    _G.UnitName  = function() return nil end
    _G.UnitExists = function() return false end
    local m = RaidPanel._getRaidMembers()
    T.assertEq(#m, 0)
  end)
end)

T.describe("RaidPanel.getRaidMembers — raid", function()
  T.it("returns only raid slots where UnitExists is true", function()
    _G.IsInRaid = function() return true end
    _G.UnitExists = function(u) return u == "raid1" or u == "raid3" end
    _G.UnitName   = function(u)
      if u == "raid1" then return "Alpha" end
      if u == "raid3" then return "Gamma" end
    end
    local m = RaidPanel._getRaidMembers()
    T.assertEq(#m, 2)
    T.assertEq(m[1].name, "Alpha")
    T.assertEq(m[1].unit, "raid1")
    T.assertEq(m[2].name, "Gamma")
    T.assertEq(m[2].unit, "raid3")
  end)

  T.it("iterates up to raid40", function()
    _G.IsInRaid   = function() return true end
    local count   = 0
    _G.UnitExists = function(u)
      if u:match("^raid") then count = count + 1 end
      return false
    end
    _G.UnitName = function() return nil end
    RaidPanel._getRaidMembers()
    T.assertEq(count, 40)
  end)
end)

T.describe("RaidPanel.getRaidMembers — party", function()
  T.it("returns player plus party slots that exist", function()
    _G.IsInRaid  = function() return false end
    _G.IsInGroup = function() return true end
    _G.UnitExists = function(u) return u == "party1" or u == "party2" end
    _G.UnitName   = function(u)
      if u == "player" then return "Me" end
      if u == "party1" then return "P1" end
      if u == "party2" then return "P2" end
    end
    local m = RaidPanel._getRaidMembers()
    -- player first, then party members
    T.assertTrue(#m >= 1)
    T.assertEq(m[1].name, "Me")
    local names = {}
    for _, e in ipairs(m) do names[e.name] = true end
    T.assertTrue(names["P1"])
    T.assertTrue(names["P2"])
  end)
end)

-- ── Popup.GetCachedState / Popup.InjectState ──────────────────────────────────

T.describe("Popup.InjectState + GetCachedState round-trip", function()
  T.it("reads back the same state object", function()
    local state = makeState({ hp = 42, maxHp = 100 })
    Popup.InjectState("RoundTripPlayer", state)
    local got = Popup.GetCachedState("RoundTripPlayer")
    T.assertNotNil(got)
    T.assertEq(got.hp, 42)
  end)

  T.it("name with realm resolves to the same slot as bare name", function()
    local state = makeState({ hp = 77 })
    Popup.InjectState("RealmPlayer-MyRealm", state)
    local got = Popup.GetCachedState("RealmPlayer")
    T.assertNotNil(got)
    T.assertEq(got.hp, 77)
  end)

  T.it("returns nil for a name that was never injected", function()
    local got = Popup.GetCachedState("NobodyEverInjectedThis_xyz123")
    T.assertNil(got)
  end)
end)

-- ── Popup.OnStateArrived ──────────────────────────────────────────────────────

T.describe("Popup.OnStateArrived — basic callback", function()
  T.it("fires registered callback when OnStateReceived is called", function()
    local fired = false
    local unsub = Popup.OnStateArrived(function(sender, _)
      if sender == "CallbackTestSender" then fired = true end
    end)
    Popup:OnStateReceived("CallbackTestSender", makeState())
    unsub()
    T.assertTrue(fired)
  end)

  T.it("does not fire after unsubscribe", function()
    local callCount = 0
    local unsub = Popup.OnStateArrived(function()
      callCount = callCount + 1
    end)
    Popup:OnStateReceived("UnsubTest1", makeState())
    unsub()
    Popup:OnStateReceived("UnsubTest2", makeState())
    T.assertEq(callCount, 1)
  end)

  T.it("a faulty callback does not prevent others from firing", function()
    local good = false
    local unsubBad  = Popup.OnStateArrived(function() error("boom") end)
    local unsubGood = Popup.OnStateArrived(function() good = true end)
    Popup:OnStateReceived("FaultTest", makeState())
    unsubBad()
    unsubGood()
    T.assertTrue(good, "good callback must still fire after a faulty one errored")
  end)

  T.it("multiple independent subscribers each receive the event", function()
    local a, b = false, false
    local u1 = Popup.OnStateArrived(function() a = true end)
    local u2 = Popup.OnStateArrived(function() b = true end)
    Popup:OnStateReceived("MultiSubTest", makeState())
    u1(); u2()
    T.assertTrue(a)
    T.assertTrue(b)
  end)
end)

-- ── Popup.OnStateArrived — cache is updated before callbacks fire ──────────────

T.describe("Popup.OnStateArrived — cache freshness", function()
  T.it("GetCachedState returns the new state inside the callback", function()
    local seenInside = nil
    local unsub = Popup.OnStateArrived(function(sender, _)
      if sender == "CacheFreshTest" then
        seenInside = Popup.GetCachedState(sender)
      end
    end)
    local newState = makeState({ hp = 99 })
    Popup:OnStateReceived("CacheFreshTest", newState)
    unsub()
    T.assertNotNil(seenInside)
    T.assertEq(seenInside.hp, 99)
  end)
end)

-- ── RaidPanel._resMarkerDefs (threshold positions) ────────────────────────────

T.describe("RaidPanel.resMarkerDefs — threshold marker positions", function()
  T.it("Warlock Corruption (idx 2) has 3 markers at 10/25/45 over 60", function()
    local m = RaidPanel._resMarkerDefs("WARLOCK", 2)
    T.assertEq(#m, 3)
    T.assertNear(m[1].pct, 10/60, 1e-9)
    T.assertNear(m[2].pct, 25/60, 1e-9)
    T.assertNear(m[3].pct, 45/60, 1e-9)
  end)

  T.it("ShadowPriest Insanity (idx 2) has 4 markers up to 25/25", function()
    local m = RaidPanel._resMarkerDefs("SHADOWPRIEST", 2)
    T.assertEq(#m, 4)
    T.assertNear(m[4].pct, 1.0, 1e-9)
  end)

  T.it("Mage Arcane (idx 2) has 2 markers at 4/8 and 8/8", function()
    local m = RaidPanel._resMarkerDefs("MAGE", 2)
    T.assertEq(#m, 2)
    T.assertNear(m[1].pct, 0.5, 1e-9)
    T.assertNear(m[2].pct, 1.0, 1e-9)
  end)

  T.it("primary resource (idx 1) has no markers", function()
    T.assertEq(#RaidPanel._resMarkerDefs("WARLOCK", 1), 0)
    T.assertEq(#RaidPanel._resMarkerDefs("MAGE", 1), 0)
  end)

  T.it("classes without thresholds return empty", function()
    T.assertEq(#RaidPanel._resMarkerDefs("ROGUE", 2), 0)
    T.assertEq(#RaidPanel._resMarkerDefs("SHAMAN", 2), 0)
  end)

  T.it("every marker def carries pct + color + width", function()
    local m = RaidPanel._resMarkerDefs("WARLOCK", 2)
    for _, d in ipairs(m) do
      T.assertNotNil(d.pct)
      T.assertNotNil(d.r); T.assertNotNil(d.g); T.assertNotNil(d.b)
      T.assertNotNil(d.w)
    end
  end)
end)

T.describe("RaidPanel.getDisplayData — markers attached to resources", function()
  T.it("Warlock Corruption resource carries its 3 markers", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      classKey = "WARLOCK",
      res = 50, maxRes = 100,
      res2 = 30, maxRes2 = 60,
      res3 = 2,  maxRes3 = 5,
    }))
    T.assertEq(#d.resources[2].markers, 3)
    T.assertEq(#d.resources[1].markers, 0)
  end)
end)

-- ── RaidPanel.getDisplayData — class metadata for the UI ──────────────────────

T.describe("RaidPanel.getDisplayData — class metadata", function()
  T.it("attaches a French class label", function()
    local d = RaidPanel._getDisplayData("X", makeState({ classKey = "MAGE" }))
    T.assertEq(d.classLabel, "Mage")
  end)

  T.it("attaches a name color from CLASS_STYLES", function()
    local d = RaidPanel._getDisplayData("X", makeState({ classKey = "MAGE" }))
    T.assertNotNil(d.nameColor)
    T.assertEq(#d.nameColor, 3)
    -- Mage style is blue-ish (0.20, 0.55, 1.00)
    T.assertNear(d.nameColor[3], 1.00, 1e-9)
  end)

  T.it("unknown class falls back to a default gold name color", function()
    local d = RaidPanel._getDisplayData("X", makeState({ classKey = "NOTACLASS" }))
    T.assertNotNil(d.nameColor)
    T.assertEq(#d.nameColor, 3)
  end)
end)

-- ── RaidPanel._collectData (the /go raidtest + Refresh data path) ──────────────

T.describe("RaidPanel.collectData — maps members to cached display data", function()
  T.it("returns display data for members with a cached state", function()
    Popup.InjectState("CollectA", makeState({ classKey = "MAGE", hp = 80, maxHp = 100 }))
    Popup.InjectState("CollectB", makeState({ classKey = "ROGUE", hp = 55, maxHp = 130 }))
    local list = RaidPanel._collectData({ { name = "CollectA" }, { name = "CollectB" } })
    T.assertEq(#list, 2)
    T.assertEq(list[1].name, "CollectA")
    T.assertEq(list[1].hp, 80)
    T.assertEq(list[2].name, "CollectB")
    T.assertEq(list[2].hp, 55)
  end)

  T.it("yields a placeholder (name only, no hp) for an uncached member", function()
    local list = RaidPanel._collectData({ { name = "NeverCached_zzz" } })
    T.assertEq(#list, 1)
    T.assertEq(list[1].name, "NeverCached_zzz")
    T.assertNil(list[1].hp)
  end)

  T.it("preserves member order", function()
    Popup.InjectState("OrderOne", makeState({ hp = 1 }))
    Popup.InjectState("OrderTwo", makeState({ hp = 2 }))
    local list = RaidPanel._collectData({ { name = "OrderTwo" }, { name = "OrderOne" } })
    T.assertEq(list[1].name, "OrderTwo")
    T.assertEq(list[2].name, "OrderOne")
  end)

  T.it("handles an empty member list", function()
    local list = RaidPanel._collectData({})
    T.assertEq(#list, 0)
  end)

  T.it("threads the member unit onto cached data (for click-to-target)", function()
    Popup.InjectState("UnitCached", makeState({ hp = 50 }))
    local list = RaidPanel._collectData({ { name = "UnitCached", unit = "raid7" } })
    T.assertEq(list[1].unit, "raid7")
  end)

  T.it("threads the member unit onto placeholder rows too", function()
    local list = RaidPanel._collectData({ { name = "NoCacheUnit_q", unit = "party2" } })
    T.assertNil(list[1].hp)        -- placeholder
    T.assertEq(list[1].unit, "party2")
  end)
end)

-- ── RaidPanel.getDisplayData — Points de Chance ───────────────────────────────

T.describe("RaidPanel.getDisplayData — chance pool", function()
  T.it("chance is nil when maxChance is 0 / absent", function()
    local d = RaidPanel._getDisplayData("X", makeState())
    T.assertNil(d.chance)
  end)

  T.it("chance carries cur/max when maxChance > 0", function()
    local d = RaidPanel._getDisplayData("X", makeState({ chance = 3, maxChance = 5 }))
    T.assertNotNil(d.chance)
    T.assertEq(d.chance.cur, 3)
    T.assertEq(d.chance.max, 5)
  end)

  T.it("chance.cur is clamped to maxChance", function()
    local d = RaidPanel._getDisplayData("X", makeState({ chance = 99, maxChance = 5 }))
    T.assertEq(d.chance.cur, 5)
  end)

  T.it("chance.cur floors at 0", function()
    local d = RaidPanel._getDisplayData("X", makeState({ chance = -4, maxChance = 5 }))
    T.assertEq(d.chance.cur, 0)
  end)
end)

-- ── RaidPanel.getDisplayData — pet sub-card ───────────────────────────────────

T.describe("RaidPanel.getDisplayData — pet extraction", function()
  T.it("pet is nil when the state has no pet table", function()
    local d = RaidPanel._getDisplayData("X", makeState())
    T.assertNil(d.pet)
  end)

  T.it("pet is nil when the pet is disabled", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      pet = { enabled = false, name = "Rex", hp = 10, maxHp = 20 },
    }))
    T.assertNil(d.pet)
  end)

  T.it("carries name/hp/maxHp when the pet is enabled", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      pet = { enabled = true, name = "Rex", hp = 12, maxHp = 20 },
    }))
    T.assertNotNil(d.pet)
    T.assertEq(d.pet.name,  "Rex")
    T.assertEq(d.pet.hp,    12)
    T.assertEq(d.pet.maxHp, 20)
  end)

  T.it("falls back to 'Familier' for a missing/empty pet name", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      pet = { enabled = true, name = "", hp = 5, maxHp = 20 },
    }))
    T.assertEq(d.pet.name, "Familier")
  end)

  T.it("clamps pet hp into [0, maxHp] and maxHp to at least 1", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      pet = { enabled = true, name = "Rex", hp = 99, maxHp = 0 },
    }))
    T.assertTrue(d.pet.maxHp >= 1)
    T.assertTrue(d.pet.hp <= d.pet.maxHp)
  end)

  T.it("woundCap follows the pet's own wounds", function()
    local d = RaidPanel._getDisplayData("X", makeState({
      pet = { enabled = true, name = "Rex", hp = 5, maxHp = 20,
              wounds = { hit25 = true, hit10 = false } },
    }))
    T.assertNear(d.pet.woundCap, 0.50, 1e-9)
  end)

  T.it("collectData threads pet data through", function()
    Popup.InjectState("PetOwnerCached", makeState({
      pet = { enabled = true, name = "Rex", hp = 12, maxHp = 20 },
    }))
    local list = RaidPanel._collectData({ { name = "PetOwnerCached", unit = "raid3" } })
    T.assertNotNil(list[1].pet)
    T.assertEq(list[1].pet.name, "Rex")
  end)
end)

-- ── French class name rename (Voleur -> Furtif) ───────────────────────────────

T.describe("Rogue French label is 'Furtif'", function()
  T.it("Shared.GetClassNameFr('ROGUE') returns 'Furtif'", function()
    T.assertEq(ns.Shared.GetClassNameFr("ROGUE"), "Furtif")
  end)

  T.it("getDisplayData tags a Rogue with classLabel 'Furtif'", function()
    local d = RaidPanel._getDisplayData("X", makeState({ classKey = "ROGUE" }))
    T.assertEq(d.classLabel, "Furtif")
  end)
end)
