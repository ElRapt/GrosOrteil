---@diagnostic disable: undefined-global
-- Tests for GrosOrteil_GMMarkers.lua
-- Run via: lua tests/run.lua [-v]

local T          = _G.T
local ns         = _G.NS
local GMMarkers  = ns.GMMarkers

local function reset(idx)
  GMMarkers.ResetMarker(idx or 1)
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

T.describe("GMMarkers init", function()
  T.it("creates state for all 8 markers", function()
    for i = 1, 8 do
      T.assertNotNil(GMMarkers.states[i])
    end
  end)

  T.it("default HP is 50 / 50", function()
    reset(1)
    T.assertEq(GMMarkers.states[1].hp,    50)
    T.assertEq(GMMarkers.states[1].maxHp, 50)
  end)

  T.it("wounds default to false", function()
    reset(1)
    T.assertEq(GMMarkers.states[1].wounds.hit25, false)
    T.assertEq(GMMarkers.states[1].wounds.hit10, false)
  end)

  T.it("default resource is 20 / 20", function()
    reset(1)
    T.assertEq(GMMarkers.states[1].res,    20)
    T.assertEq(GMMarkers.states[1].maxRes, 20)
  end)
end)

---------------------------------------------------------------------------
-- SetHP
---------------------------------------------------------------------------

T.describe("GMMarkers.SetHP", function()
  T.it("sets hp and maxHp", function()
    reset(1)
    GMMarkers.SetHP(1, 80, 100)
    T.assertEq(GMMarkers.states[1].hp,    80)
    T.assertEq(GMMarkers.states[1].maxHp, 100)
  end)

  T.it("clamps hp above maxHp to maxHp", function()
    reset(1)
    GMMarkers.SetHP(1, 9999, 100)
    T.assertEq(GMMarkers.states[1].hp, 100)
  end)

  T.it("clamps negative hp to 0", function()
    reset(1)
    GMMarkers.SetHP(1, -5, 100)
    T.assertEq(GMMarkers.states[1].hp, 0)
  end)

  T.it("recomputes wounds: hit25 when hp <= 25%", function()
    reset(1)
    GMMarkers.SetHP(1, 20, 100)
    T.assertTrue(GMMarkers.states[1].wounds.hit25)
    T.assertFalse(GMMarkers.states[1].wounds.hit10)
  end)

  T.it("recomputes wounds: hit10 when hp <= 10%", function()
    reset(1)
    GMMarkers.SetHP(1, 5, 100)
    T.assertTrue(GMMarkers.states[1].wounds.hit25)
    T.assertTrue(GMMarkers.states[1].wounds.hit10)
  end)

  T.it("clears wounds when hp > 25%", function()
    reset(1)
    GMMarkers.SetHP(1, 5, 100)   -- set wounds
    GMMarkers.SetHP(1, 60, 100)  -- recompute → no wounds
    T.assertFalse(GMMarkers.states[1].wounds.hit25)
    T.assertFalse(GMMarkers.states[1].wounds.hit10)
  end)
end)

---------------------------------------------------------------------------
-- DamageWithArmor
---------------------------------------------------------------------------

T.describe("GMMarkers.DamageWithArmor", function()
  T.it("reduces hp by mitigated amount", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.SetArmor(1, 10, 0)
    GMMarkers.DamageWithArmor(1, 30)   -- 30 - 10 = 20 damage
    T.assertEq(GMMarkers.states[1].hp, 80)
  end)

  T.it("dodge absorbs hits at or below dodge value", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.SetDodge(1, 15)
    GMMarkers.DamageWithArmor(1, 15)   -- amount == dodge → fully dodged
    T.assertEq(GMMarkers.states[1].hp, 100)
  end)

  T.it("hit above dodge is not dodged", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.SetDodge(1, 15)
    GMMarkers.DamageWithArmor(1, 16)   -- > dodge → not dodged
    T.assertTrue(GMMarkers.states[1].hp < 100)
  end)

  T.it("tempBlock reduces damage and is consumed", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.SetTempBlock(1, 20)
    GMMarkers.DamageWithArmor(1, 50)  -- block 20 → 30 remain → no armor → hp=70
    T.assertEq(GMMarkers.states[1].hp,       70)
    T.assertEq(GMMarkers.states[1].tempBlock, 0)
  end)

  T.it("magic shield absorbs before hp", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.SetMagicShield(1, 20, 20, 0)
    GMMarkers.DamageWithArmor(1, 15)  -- shield absorbs all 15 → hp unchanged
    T.assertEq(GMMarkers.states[1].hp,                 100)
    T.assertEq(GMMarkers.states[1].magicShield.hp,       5)
  end)

  T.it("magic shield armor reduces damage before shield hp", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.SetMagicShield(1, 20, 20, 10) -- shield armor=10
    GMMarkers.DamageWithArmor(1, 12)  -- after shieldArmor=10: 2 absorbed by shield
    T.assertEq(GMMarkers.states[1].hp,               100)
    T.assertEq(GMMarkers.states[1].magicShield.hp,    18)
  end)

  T.it("wounds are sticky after damage crosses threshold", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.DamageWithArmor(1, 80)  -- hp=20, 20% → hit25=true
    T.assertTrue(GMMarkers.states[1].wounds.hit25)
    -- Partial heal stays capped: wound cap is 50% = 50
    GMMarkers.Heal(1, 100)
    T.assertEq(GMMarkers.states[1].hp, 50)
    T.assertTrue(GMMarkers.states[1].wounds.hit25)  -- still sticky
  end)

  T.it("pushes DAMAGE_ARMOR entry to history", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.DamageWithArmor(1, 20)
    T.assertTrue(#GMMarkers.states[1].history >= 1)
    T.assertEq(GMMarkers.states[1].history[1].kind, "DAMAGE_ARMOR")
  end)
end)

---------------------------------------------------------------------------
-- DamageTrue
---------------------------------------------------------------------------

T.describe("GMMarkers.DamageTrue", function()
  T.it("ignores armor but applies trueArmor", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.SetArmor(1, 50, 5)  -- armor=50 ignored, trueArmor=5 applies
    GMMarkers.DamageTrue(1, 20)   -- 20 - 5 = 15 damage
    T.assertEq(GMMarkers.states[1].hp, 85)
  end)

  T.it("applies tempArmor on true damage", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.SetArmor(1, 0, 0)
    GMMarkers.SetTempArmor(1, 8)
    GMMarkers.DamageTrue(1, 20)   -- 20 - 8 = 12 damage
    T.assertEq(GMMarkers.states[1].hp, 88)
  end)

  T.it("pushes DAMAGE_TRUE entry to history", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.DamageTrue(1, 10)
    T.assertEq(GMMarkers.states[1].history[1].kind, "DAMAGE_TRUE")
  end)
end)

---------------------------------------------------------------------------
-- Heal
---------------------------------------------------------------------------

T.describe("GMMarkers.Heal", function()
  T.it("normal heal increases hp", function()
    reset(1)
    GMMarkers.SetHP(1, 40, 100)
    GMMarkers.Heal(1, 20)
    T.assertEq(GMMarkers.states[1].hp, 60)
  end)

  T.it("heal is capped at wound threshold (hit25 → 50%)", function()
    reset(1)
    GMMarkers.SetHP(1, 10, 100)   -- 10% → both wounds
    GMMarkers.Heal(1, 90)         -- wound cap hit10 → 25% = 25; proposed=100 > 25
    T.assertEq(GMMarkers.states[1].hp, 25)
  end)

  T.it("heal is capped at maxHp", function()
    reset(1)
    GMMarkers.SetHP(1, 90, 100)
    GMMarkers.Heal(1, 50)         -- would go to 140, capped at 100
    T.assertEq(GMMarkers.states[1].hp, 100)
  end)
end)

---------------------------------------------------------------------------
-- DivineHeal
---------------------------------------------------------------------------

T.describe("GMMarkers.DivineHeal", function()
  T.it("restores 75% of maxHp ignoring wound cap", function()
    reset(1)
    GMMarkers.SetHP(1, 5, 100)    -- wound state active
    GMMarkers.DivineHeal(1)       -- gain = 75; 5+75=80
    T.assertEq(GMMarkers.states[1].hp, 80)
  end)

  T.it("does not exceed maxHp", function()
    reset(1)
    GMMarkers.SetHP(1, 90, 100)
    GMMarkers.DivineHeal(1)       -- 90+75=165, capped at 100
    T.assertEq(GMMarkers.states[1].hp, 100)
  end)
end)

---------------------------------------------------------------------------
-- Surgery
---------------------------------------------------------------------------

T.describe("GMMarkers.Surgery", function()
  T.it("restores 50% of maxHp ignoring wound cap", function()
    reset(1)
    GMMarkers.SetHP(1, 5, 100)
    GMMarkers.Surgery(1)          -- gain = 50; 5+50=55
    T.assertEq(GMMarkers.states[1].hp, 55)
  end)
end)

---------------------------------------------------------------------------
-- RestoreHP
---------------------------------------------------------------------------

T.describe("GMMarkers.RestoreHP", function()
  T.it("restores hp to maxHp", function()
    reset(1)
    GMMarkers.SetHP(1, 20, 100)
    GMMarkers.RestoreHP(1)
    T.assertEq(GMMarkers.states[1].hp, 100)
  end)

  T.it("clears wounds", function()
    reset(1)
    GMMarkers.SetHP(1, 5, 100)    -- both wounds set
    T.assertTrue(GMMarkers.states[1].wounds.hit25)
    GMMarkers.RestoreHP(1)
    T.assertFalse(GMMarkers.states[1].wounds.hit25)
    T.assertFalse(GMMarkers.states[1].wounds.hit10)
  end)
end)

---------------------------------------------------------------------------
-- DailyRegenHP
---------------------------------------------------------------------------

T.describe("GMMarkers.DailyRegenHP", function()
  T.it("adds 10% of maxHp rounded", function()
    reset(1)
    GMMarkers.SetHP(1, 50, 100)
    GMMarkers.DailyRegenHP(1)     -- gain = round(10) = 10
    T.assertEq(GMMarkers.states[1].hp, 60)
  end)

  T.it("does not exceed maxHp", function()
    reset(1)
    GMMarkers.SetHP(1, 98, 100)
    GMMarkers.DailyRegenHP(1)     -- +10 would give 108, clamped to 100
    T.assertEq(GMMarkers.states[1].hp, 100)
  end)
end)

---------------------------------------------------------------------------
-- SetRes / AddRes
---------------------------------------------------------------------------

T.describe("GMMarkers.SetRes / AddRes", function()
  T.it("SetRes clamps to maxRes", function()
    reset(1)
    GMMarkers.SetRes(1, 9999, 20)
    T.assertEq(GMMarkers.states[1].res,    20)
    T.assertEq(GMMarkers.states[1].maxRes, 20)
  end)

  T.it("AddRes increments and clamps at maxRes", function()
    reset(1)
    GMMarkers.SetRes(1, 18, 20)
    GMMarkers.AddRes(1, 5)
    T.assertEq(GMMarkers.states[1].res, 20)
  end)

  T.it("AddRes with negative decrements", function()
    reset(1)
    GMMarkers.SetRes(1, 15, 20)
    GMMarkers.AddRes(1, -5)
    T.assertEq(GMMarkers.states[1].res, 10)
  end)

  T.it("AddRes clamps at 0", function()
    reset(1)
    GMMarkers.SetRes(1, 3, 20)
    GMMarkers.AddRes(1, -100)
    T.assertEq(GMMarkers.states[1].res, 0)
  end)
end)

---------------------------------------------------------------------------
-- OnChange observer
---------------------------------------------------------------------------

T.describe("GMMarkers.OnChange", function()
  T.it("listener is called on state change", function()
    reset(1)
    local called = 0
    local unreg = GMMarkers.OnChange(1, function() called = called + 1 end)
    GMMarkers.SetHP(1, 80, 100)
    T.assertEq(called, 1)
    unreg()
    GMMarkers.SetHP(1, 60, 100)
    T.assertEq(called, 1)  -- not called after unregister
  end)

  T.it("multiple listeners fire independently", function()
    reset(1)
    local a, b = 0, 0
    local unregA = GMMarkers.OnChange(1, function() a = a + 1 end)
    local unregB = GMMarkers.OnChange(1, function() b = b + 1 end)
    GMMarkers.SetHP(1, 70, 100)
    T.assertEq(a, 1)
    T.assertEq(b, 1)
    unregA()
    GMMarkers.SetHP(1, 50, 100)
    T.assertEq(a, 1)  -- stopped
    T.assertEq(b, 2)  -- still firing
    unregB()
  end)
end)

---------------------------------------------------------------------------
-- Isolation between markers
---------------------------------------------------------------------------

T.describe("GMMarkers isolation", function()
  T.it("actions on marker 2 do not affect marker 1", function()
    reset(1); reset(2)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.SetHP(2, 100, 100)
    GMMarkers.DamageWithArmor(2, 30)
    T.assertEq(GMMarkers.states[1].hp, 100)
    T.assertEq(GMMarkers.states[2].hp,  70)
  end)

  T.it("marker 8 is independent from marker 1", function()
    reset(1); reset(8)
    GMMarkers.SetHP(8, 50, 100)
    GMMarkers.DamageWithArmor(8, 20)
    T.assertEq(GMMarkers.states[1].hp, 50)  -- reset default
    T.assertEq(GMMarkers.states[8].hp, 30)
  end)
end)

---------------------------------------------------------------------------
-- History
---------------------------------------------------------------------------

T.describe("GMMarkers history", function()
  T.it("DamageWithArmor pushes DAMAGE_ARMOR entry", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.DamageWithArmor(1, 20)
    T.assertTrue(#GMMarkers.states[1].history >= 1)
    T.assertEq(GMMarkers.states[1].history[1].kind, "DAMAGE_ARMOR")
  end)

  T.it("ClearHistory empties ring-buffer", function()
    reset(1)
    GMMarkers.SetHP(1, 100, 100)
    GMMarkers.DamageWithArmor(1, 10)
    GMMarkers.DamageWithArmor(1, 10)
    T.assertTrue(#GMMarkers.states[1].history >= 1)
    GMMarkers.ClearHistory(1)
    T.assertEq(#GMMarkers.states[1].history, 0)
  end)
end)

---------------------------------------------------------------------------
-- Shared helpers (Shared.lua functions used by GMMarkers)
---------------------------------------------------------------------------

T.describe("Shared.GetWoundCap", function()
  local Shared = ns.Shared

  T.it("returns 1.0 when no wounds", function()
    T.assertNear(Shared.GetWoundCap({ hit25=false, hit10=false }), 1.0, 0.001)
  end)

  T.it("returns 0.5 when hit25 only", function()
    T.assertNear(Shared.GetWoundCap({ hit25=true, hit10=false }), 0.5, 0.001)
  end)

  T.it("returns 0.25 when hit10", function()
    T.assertNear(Shared.GetWoundCap({ hit25=true, hit10=true }), 0.25, 0.001)
  end)
end)

T.describe("Shared.ConsumeMagicShield", function()
  local Shared = ns.Shared

  T.it("shield armor reduces incoming before shield hp absorbs", function()
    local ms = { hp=20, maxHp=20, armor=5 }
    local overflow, absorbed = Shared.ConsumeMagicShield(ms, 10)
    -- after shield armor: 10-5=5 reaches shield hp; absorbed=5
    T.assertEq(overflow,  0)
    T.assertEq(ms.hp,    15)
  end)

  T.it("overflow leaks when shield hp exhausted", function()
    local ms = { hp=3, maxHp=10, armor=0 }
    local overflow, absorbed = Shared.ConsumeMagicShield(ms, 10)
    T.assertEq(overflow,  7)
    T.assertEq(ms.hp,     0)
    T.assertEq(ms.maxHp,  0)
  end)

  T.it("no-op when shield hp is 0", function()
    local ms = { hp=0, maxHp=10, armor=0 }
    local overflow, absorbed = Shared.ConsumeMagicShield(ms, 15)
    T.assertEq(overflow, 15)
    T.assertEq(absorbed,  0)
  end)
end)
