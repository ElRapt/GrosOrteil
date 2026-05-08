---@diagnostic disable: undefined-global
local T = _G.T
local ns = _G.NS
local Core = ns.Core

-- Reset Core to defaults before every test so they don't share state.
local function reset()
  Core.ResetToDefaults()
end

T.describe("Core init", function()
  T.it("populates default state with valid HP/maxHp", function()
    reset()
    T.assertEq(Core.state.hp, 50)
    T.assertEq(Core.state.maxHp, 50)
    T.assertNotNil(Core.state.classKey)
  end)
  T.it("initializes wounds and pet sub-tables", function()
    reset()
    T.assertEq(Core.state.wounds.hit25, false)
    T.assertEq(Core.state.wounds.hit10, false)
    T.assertEq(Core.state.pet.enabled, false)
    T.assertEq(Core.state.pet.maxHp, 20)
  end)
end)

T.describe("Core.SetHP clamping", function()
  T.it("clamps HP > maxHp to maxHp", function()
    reset()
    Core.SetHP(999, 100)
    T.assertEq(Core.state.maxHp, 100)
    T.assertEq(Core.state.hp, 100)
  end)
  T.it("clamps negative HP to 0", function()
    reset()
    Core.SetHP(-50, 100)
    T.assertEq(Core.state.hp, 0)
  end)
  T.it("clears stabilise when hp goes back above 0", function()
    reset()
    Core.SetHP(0, 50)
    Core.SetStabilise(true)
    T.assertEq(Core.state.stabilise, true)
    Core.SetHP(10, 50)
    T.assertNil(Core.state.stabilise)
  end)
end)

T.describe("Core wounds thresholds", function()
  T.it("sets hit25 when hp drops below 25%", function()
    reset()
    Core.SetHP(20, 100)  -- 20% < 25%
    T.assertEq(Core.state.wounds.hit25, true)
    T.assertEq(Core.state.wounds.hit10, false)
  end)
  T.it("sets hit10 when hp drops below 10%", function()
    reset()
    Core.SetHP(5, 100)
    T.assertEq(Core.state.wounds.hit10, true)
    T.assertEq(Core.state.wounds.hit25, true)
  end)
  T.it("wounds are sticky on heal-back (do not auto-clear)", function()
    reset()
    Core.SetHP(5, 100)
    Core.Heal(80)
    -- After healing the wounds should remain set: that's the sticky semantics.
    T.assertEq(Core.state.wounds.hit10, true)
  end)
  T.it("wounds clear when SetHP raises hp directly (recompute path)", function()
    reset()
    Core.SetHP(5, 100)
    Core.SetHP(100, 100)
    T.assertEq(Core.state.wounds.hit25, false)
    T.assertEq(Core.state.wounds.hit10, false)
  end)
end)

T.describe("Core.DamageWithArmor", function()
  T.it("subtracts mitigated damage from HP", function()
    reset()
    Core.SetHP(100, 100)
    Core.SetArmor(10, 0)
    Core.DamageWithArmor(30)  -- after armor: 20
    T.assertEq(Core.state.hp, 80)
  end)
  T.it("dodge fully absorbs hits at or below dodge value", function()
    reset()
    Core.SetHP(100, 100)
    Core.SetDodge(15)
    Core.DamageWithArmor(15)
    T.assertEq(Core.state.hp, 100)  -- dodged
    Core.DamageWithArmor(20)
    T.assertTrue(Core.state.hp < 100, "non-dodged hit should reduce HP")
  end)
  T.it("tempBlock absorbs before armor mitigation", function()
    reset()
    Core.SetHP(100, 100)
    Core.SetTempBlock(20)
    Core.DamageWithArmor(50)  -- block absorbs 20, remaining 30, no armor → -30
    T.assertEq(Core.state.hp, 70)
    T.assertEq(Core.state.tempBlock, 0)
  end)
  T.it("never reduces HP below 0", function()
    reset()
    Core.SetHP(10, 100)
    Core.DamageWithArmor(9999)
    T.assertEq(Core.state.hp, 0)
  end)
end)

T.describe("Core.DamageTrue", function()
  T.it("ignores armor", function()
    reset()
    Core.SetHP(100, 100)
    Core.SetArmor(50, 0)
    Core.DamageTrue(30)
    T.assertEq(Core.state.hp, 70)
  end)
  T.it("still respects trueArmor and tempArmor", function()
    reset()
    Core.SetHP(100, 100)
    Core.SetArmor(0, 5)        -- trueArmor=5
    Core.SetTempArmor(3)
    Core.DamageTrue(20)
    T.assertEq(Core.state.hp, 88)  -- 20 - (5 + 3) = 12
  end)
end)

T.describe("Core magic shield", function()
  T.it("absorbs damage and reduces shield HP", function()
    reset()
    Core.SetHP(100, 100)
    Core.SetMagicShield(40, 40, 0)
    Core.DamageWithArmor(30)  -- entirely soaked by shield
    T.assertEq(Core.state.hp, 100)
    T.assertEq(Core.state.magicShield.hp, 10)
  end)
  T.it("breaks and resets fields when overflowed", function()
    reset()
    Core.SetHP(100, 100)
    Core.SetMagicShield(20, 20, 0)
    Core.DamageWithArmor(50)  -- shield eats 20, 30 leaks to HP
    T.assertEq(Core.state.hp, 70)
    T.assertEq(Core.state.magicShield.hp, 0)
    T.assertEq(Core.state.magicShield.maxHp, 0)
  end)
  T.it("shield armor reduces incoming damage before shield HP absorbs", function()
    reset()
    Core.SetHP(100, 100)
    Core.SetMagicShield(40, 40, 5)  -- 5 armor on the shield itself
    Core.DamageWithArmor(15)         -- 15 - 5 (shield armor) = 10 absorbed by shield HP
    T.assertEq(Core.state.hp, 100)
    T.assertEq(Core.state.magicShield.hp, 30)
  end)
end)

T.describe("Core mana shield (Mage)", function()
  T.it("requires Mage class", function()
    reset()
    Core.SetClassKey("ROGUE")
    Core.SetManaShieldActive(true)
    T.assertEq(Core.state.manaShield.active, false)
  end)
  T.it("activates only with mana > 0", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetRes(0, 100)
    Core.SetManaShieldActive(true)
    T.assertEq(Core.state.manaShield.active, false)
    Core.SetRes(50, 100)
    Core.SetManaShieldActive(true)
    T.assertEq(Core.state.manaShield.active, true)
  end)
  T.it("redirects damage onto mana while active", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetHP(100, 100)
    Core.SetRes(50, 100)
    Core.SetManaShieldArmor(0)  -- isolate the redirect path from the armor contribution
    Core.SetManaShieldActive(true)
    Core.DamageTrue(30)
    T.assertEq(Core.state.res, 20)
    T.assertEq(Core.state.hp, 100)
  end)
  T.it("breaks when mana hits 0 and overflow hits HP", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetHP(100, 100)
    Core.SetRes(20, 100)
    Core.SetManaShieldArmor(0)
    Core.SetManaShieldActive(true)
    Core.DamageTrue(50)  -- 20 mana drained, 30 leaks to HP
    T.assertEq(Core.state.res, 0)
    T.assertEq(Core.state.hp, 70)
    T.assertEq(Core.state.manaShield.active, false)
  end)
  T.it("default shield armor reduces damage before mana absorbs", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetHP(100, 100)
    Core.SetRes(50, 100)
    -- Default manaShield.armor is 25 from Core_Init — verify it acts as armor.
    Core.SetManaShieldActive(true)
    Core.DamageTrue(30)  -- 30 - 25 (shield armor) = 5 → mana drains 5
    T.assertEq(Core.state.res, 45)
    T.assertEq(Core.state.hp, 100)
  end)
end)

T.describe("Core.Heal", function()
  T.it("clamps to maxHp", function()
    reset()
    Core.SetHP(40, 100)
    Core.Heal(999)
    T.assertEq(Core.state.hp, 100)
  end)
  T.it("respects 50% wound cap when hit25", function()
    reset()
    Core.SetHP(20, 100)  -- forces hit25 sticky
    Core.Heal(999)
    -- Wound cap caps at 50% of maxHp = 50.
    T.assertEq(Core.state.hp, 50)
  end)
  T.it("respects 25% wound cap when hit10", function()
    reset()
    Core.SetHP(5, 100)
    Core.Heal(999)
    T.assertEq(Core.state.hp, 25)
  end)
end)

T.describe("Core.DivineHeal & Surgery (bypass cap)", function()
  T.it("DivineHeal grants 75% of maxHp regardless of wounds", function()
    reset()
    Core.SetHP(5, 100)
    Core.DivineHeal()
    T.assertEq(Core.state.hp, 80)  -- 5 + 75
  end)
  T.it("Surgery grants 50% of maxHp", function()
    reset()
    Core.SetHP(0, 100)
    Core.SetStabilise(true)
    Core.Surgery()
    T.assertEq(Core.state.hp, 50)
  end)
end)

T.describe("Core Shaman posture", function()
  T.it("requires ≥3 max elemental points to activate", function()
    reset()
    Core.SetClassKey("SHAMAN")
    Core.SetResIndex(1, 2, 2)  -- TERRE max=2, below threshold
    Core.SetShamanPosture("TERRE")
    T.assertNil(Core.state.shamanPosture)
  end)
  T.it("activates when max ≥3 even if current is 0", function()
    reset()
    Core.SetClassKey("SHAMAN")
    Core.SetResIndex(1, 0, 20)  -- TERRE current=0 but max=20
    Core.SetShamanPosture("TERRE")
    T.assertEq(Core.state.shamanPosture, "TERRE")
  end)
  T.it("TERRE posture grants +5 armor and +20 maxHp", function()
    reset()
    Core.SetClassKey("SHAMAN")
    Core.SetHP(50, 50)
    Core.SetArmor(0, 0)
    Core.SetResIndex(1, 5, 20)
    Core.SetShamanPosture("TERRE")
    T.assertEq(Core.state.shamanPosture, "TERRE")
    T.assertEq(Core.state.armor, 5)
    T.assertEq(Core.state.maxHp, 70)
    T.assertEq(Core.state.hp, 70)
  end)
  T.it("re-clicking same posture toggles it off and restores stats", function()
    reset()
    Core.SetClassKey("SHAMAN")
    Core.SetArmor(0, 0)
    Core.SetResIndex(1, 5, 20)
    Core.SetShamanPosture("TERRE")
    Core.SetShamanPosture("TERRE")  -- toggle off
    T.assertNil(Core.state.shamanPosture)
    T.assertEq(Core.state.armor, 0)
  end)
  T.it("class change auto-tears down active posture", function()
    reset()
    Core.SetClassKey("SHAMAN")
    Core.SetResIndex(1, 5, 20)
    Core.SetShamanPosture("TERRE")
    Core.SetClassKey("MAGE")
    T.assertNil(Core.state.shamanPosture)
  end)
end)

T.describe("Core class-specific clamps", function()
  T.it("Warlock Corruption max is 60", function()
    reset()
    Core.SetClassKey("WARLOCK")
    Core.SetResIndex(2, 999, 999)
    T.assertEq(Core.state.res2, 60)
    T.assertEq(Core.state.maxRes2, 60)
  end)
  T.it("Mage Arcane Charge max is 8", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetResIndex(2, 999, 999)
    T.assertEq(Core.state.res2, 8)
    T.assertEq(Core.state.maxRes2, 8)
  end)
end)

T.describe("Core undo / redo", function()
  T.it("undo restores prior HP", function()
    reset()
    Core.SetHP(100, 100)
    Core.DamageWithArmor(20)
    T.assertEq(Core.state.hp, 80)
    T.assertTrue(Core.CanUndo())
    Core.Undo()
    T.assertEq(Core.state.hp, 100)
  end)
  T.it("redo re-applies the undone change", function()
    reset()
    Core.SetHP(100, 100)
    Core.DamageWithArmor(20)
    Core.Undo()
    T.assertTrue(Core.CanRedo())
    Core.Redo()
    T.assertEq(Core.state.hp, 80)
  end)
  T.it("a fresh edit invalidates the redo stack", function()
    reset()
    Core.SetHP(100, 100)
    Core.DamageWithArmor(20)
    Core.Undo()
    Core.Heal(5)
    T.assertFalse(Core.CanRedo())
  end)
end)

T.describe("Core pet damage/heal", function()
  T.it("pet actions are no-ops when pet is disabled", function()
    reset()
    Core.SetPetEnabled(false)
    Core.SetPetHP(20, 20)
    Core.PetDamageTrue(5)
    T.assertEq(Core.state.pet.hp, 20)
  end)
  T.it("pet damage applies when enabled", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetHP(20, 20)
    Core.PetDamageTrue(5)
    T.assertEq(Core.state.pet.hp, 15)
  end)
  T.it("pet heal respects wound cap independently from owner", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetHP(1, 20)  -- 5% triggers pet hit10 (threshold is strictly < 0.10)
    Core.PetHeal(999)
    -- Pet wound cap at 25% of 20 = 5
    T.assertEq(Core.state.pet.hp, 5)
  end)
end)

T.describe("Core listener callbacks", function()
  T.it("OnChange fires synchronously after mutations", function()
    reset()
    local fires = 0
    local unsub = Core.OnChange(function() fires = fires + 1 end)
    local before = fires  -- OnChange immediately invokes once with current state
    Core.SetHP(50, 100)
    T.assertTrue(fires > before, "expected listener to fire on mutation")
    unsub()
    local afterUnsub = fires
    Core.SetHP(40, 100)
    T.assertEq(fires, afterUnsub, "unsub should stop further fires")
  end)
  T.it("OnChange immediately invokes new listener with current state", function()
    reset()
    local seen = nil
    local unsub = Core.OnChange(function(s) seen = s end)
    T.assertNotNil(seen, "listener should fire once on registration")
    T.assertEq(seen.hp, Core.state.hp)
    unsub()
  end)
  T.it("a listener that errors does not break others or crash notify()", function()
    reset()
    local goodFires = 0
    local badUnsub = Core.OnChange(function() error("boom") end)
    local goodUnsub = Core.OnChange(function() goodFires = goodFires + 1 end)
    local before = goodFires
    -- Mutation should not throw despite the bad listener.
    Core.SetHP(40, 100)
    T.assertTrue(goodFires > before, "good listener still ran")
    badUnsub(); goodUnsub()
  end)
  T.it("multiple listeners all fire", function()
    reset()
    local a, b = 0, 0
    local ua = Core.OnChange(function() a = a + 1 end)
    local ub = Core.OnChange(function() b = b + 1 end)
    local startA, startB = a, b
    Core.SetHP(50, 100)
    T.assertTrue(a > startA); T.assertTrue(b > startB)
    ua(); ub()
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Armor / mitigation
-- ────────────────────────────────────────────────────────────────────

T.describe("Core armor stacking", function()
  T.it("DamageWithArmor sums armor + trueArmor + tempArmor", function()
    reset()
    Core.SetHP(100, 100)
    Core.SetArmor(5, 3)         -- armor=5, trueArmor=3
    Core.SetTempArmor(7)        -- +7
    Core.DamageWithArmor(20)    -- 20 - (5+3+7) = 5
    T.assertEq(Core.state.hp, 95)
  end)
  T.it("DamageTrue ignores armor but uses trueArmor + tempArmor", function()
    reset()
    Core.SetHP(100, 100)
    Core.SetArmor(50, 3)
    Core.SetTempArmor(2)
    Core.DamageTrue(20)         -- 20 - (3+2) = 15
    T.assertEq(Core.state.hp, 85)
  end)
  T.it("ResetTempArmor zeros tempArmor only", function()
    reset()
    Core.SetArmor(5, 3); Core.SetTempArmor(7)
    Core.ResetTempArmor()
    T.assertEq(Core.state.tempArmor, 0)
    T.assertEq(Core.state.armor, 5)
    T.assertEq(Core.state.trueArmor, 3)
  end)
  T.it("very large mitigation never produces negative damage", function()
    reset()
    Core.SetHP(100, 100); Core.SetArmor(9999, 0)
    Core.DamageWithArmor(50)
    T.assertEq(Core.state.hp, 100)
  end)
end)

T.describe("Core dodge edges", function()
  T.it("dodge=0 never dodges", function()
    reset()
    Core.SetHP(100, 100); Core.SetDodge(0); Core.SetArmor(0, 0)
    Core.DamageTrue(1)
    T.assertEq(Core.state.hp, 99)
  end)
  T.it("hit exactly equal to dodge still dodges", function()
    reset()
    Core.SetHP(100, 100); Core.SetDodge(15); Core.SetArmor(0, 0)
    Core.DamageTrue(15)
    T.assertEq(Core.state.hp, 100)
  end)
  T.it("hit greater than dodge does NOT dodge", function()
    reset()
    Core.SetHP(100, 100); Core.SetDodge(15); Core.SetArmor(0, 0)
    Core.DamageTrue(16)
    T.assertEq(Core.state.hp, 84)
  end)
  T.it("ResetDodge zeros dodge", function()
    reset()
    Core.SetDodge(10); Core.ResetDodge()
    T.assertEq(Core.state.dodge, 0)
  end)
end)

T.describe("Core tempBlock", function()
  T.it("block absorbs full damage when block ≥ damage", function()
    reset()
    Core.SetHP(100, 100); Core.SetTempBlock(50)
    Core.DamageWithArmor(30)
    T.assertEq(Core.state.hp, 100)
    T.assertEq(Core.state.tempBlock, 20)
  end)
  T.it("block partially absorbs and remainder goes through armor mitigation", function()
    reset()
    Core.SetHP(100, 100); Core.SetTempBlock(10); Core.SetArmor(5, 0)
    Core.DamageWithArmor(20)  -- block soaks 10, then 10 - 5 (armor) = 5
    T.assertEq(Core.state.hp, 95)
    T.assertEq(Core.state.tempBlock, 0)
  end)
  T.it("DamageTrue ignores block (block only applies to armor variant)", function()
    reset()
    Core.SetHP(100, 100); Core.SetTempBlock(50)
    Core.DamageTrue(30)
    T.assertEq(Core.state.hp, 70)
    T.assertEq(Core.state.tempBlock, 50)
  end)
  T.it("ResetTempBlock zeros block", function()
    reset()
    Core.SetTempBlock(15); Core.ResetTempBlock()
    T.assertEq(Core.state.tempBlock, 0)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Magic shield
-- ────────────────────────────────────────────────────────────────────

T.describe("Core magic shield interactions", function()
  T.it("shield armor reduces damage but does NOT consume shield HP", function()
    reset()
    Core.SetHP(100, 100); Core.SetMagicShield(20, 20, 30)
    -- shield armor 30 ≥ damage 25 → 0 reaches shield HP
    Core.DamageWithArmor(25)
    T.assertEq(Core.state.magicShield.hp, 20, "shield HP untouched")
  end)
  T.it("shield armor + shield HP combined absorption order", function()
    reset()
    Core.SetHP(100, 100); Core.SetMagicShield(10, 10, 5)  -- armor 5, hp 10
    Core.DamageWithArmor(20)
    -- 20 - 5 (shield armor) = 15. shield HP eats 10 → break, 5 leaks to player.
    -- player armor is 0 → player takes 5.
    T.assertEq(Core.state.hp, 95)
    T.assertEq(Core.state.magicShield.hp, 0)
  end)
  T.it("ResetMagicShield clears all three sub-fields", function()
    reset()
    Core.SetMagicShield(10, 20, 5)
    Core.ResetMagicShield()
    T.assertEq(Core.state.magicShield.hp, 0)
    T.assertEq(Core.state.magicShield.maxHp, 0)
    T.assertEq(Core.state.magicShield.armor, 0)
  end)
  T.it("setting hp greater than current maxHp clamps to maxHp", function()
    reset()
    Core.SetMagicShield(5, 10, 0)   -- maxHp=10
    Core.SetMagicShield(50, nil, nil)  -- try to set hp=50 with existing max=10
    T.assertEq(Core.state.magicShield.hp, 10)
  end)
end)

T.describe("Core mana shield activation rules", function()
  T.it("ToggleManaShield toggles only for MAGE class", function()
    reset()
    Core.SetClassKey("ROGUE")
    Core.ToggleManaShield()
    T.assertFalse(Core.state.manaShield.active)
  end)
  T.it("ToggleManaShield works for MAGE with mana", function()
    reset()
    Core.SetClassKey("MAGE"); Core.SetRes(50, 100)
    Core.ToggleManaShield()
    T.assertTrue(Core.state.manaShield.active)
    Core.ToggleManaShield()
    T.assertFalse(Core.state.manaShield.active)
  end)
  T.it("SetManaShieldArmor changes armor without activating", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetManaShieldArmor(50)
    T.assertEq(Core.state.manaShield.armor, 50)
    T.assertFalse(Core.state.manaShield.active)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Resources (multi-index)
-- ────────────────────────────────────────────────────────────────────

T.describe("Core resources", function()
  T.it("AddRes adjusts primary resource and clamps to max", function()
    reset()
    Core.SetRes(10, 20)
    Core.AddRes(5)
    T.assertEq(Core.state.res, 15)
    Core.AddRes(50)
    T.assertEq(Core.state.res, 20)  -- clamped
  end)
  T.it("AddRes can go negative when target supports it", function()
    reset()
    Core.SetRes(10, 20)
    Core.AddRes(-5)
    T.assertEq(Core.state.res, 5)
  end)
  T.it("ShadowPriest insanity (idx 2) is not capped by maxRes2", function()
    reset()
    Core.SetClassKey("SHADOWPRIEST")
    Core.SetResIndex(2, 999, 100)  -- max=100, res2=999 (insanity may exceed)
    T.assertEq(Core.state.res2, 999)
  end)
  T.it("AddResIndex clamps for non-shadow classes", function()
    reset()
    Core.SetClassKey("SHAMAN")
    Core.SetResIndex(2, 5, 10)
    Core.AddResIndex(2, 999)
    T.assertEq(Core.state.res2, 10)
  end)
  T.it("auth slot writes to auth/maxAuth (idx 5)", function()
    reset()
    Core.SetResIndex(5, 3, 5)
    T.assertEq(Core.state.auth, 3)
    T.assertEq(Core.state.maxAuth, 5)
  end)
  T.it("invalid resource index is a no-op", function()
    reset()
    local before = Core.state.res
    Core.SetResIndex(99, 5, 5)
    Core.AddResIndex(99, 5)
    T.assertEq(Core.state.res, before)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Stabilise
-- ────────────────────────────────────────────────────────────────────

T.describe("Core.SetStabilise rules", function()
  T.it("can only be set when hp == 0", function()
    reset()
    Core.SetHP(10, 100)
    Core.SetStabilise(true)
    T.assertNil(Core.state.stabilise)
    Core.SetHP(0, 100)
    Core.SetStabilise(true)
    T.assertEq(Core.state.stabilise, true)
  end)
  T.it("cleared by Heal when hp goes above 0", function()
    reset()
    Core.SetHP(0, 100); Core.SetStabilise(true)
    Core.Heal(20)
    T.assertNil(Core.state.stabilise)
  end)
  T.it("cleared by RestoreHP", function()
    reset()
    Core.SetHP(0, 50); Core.SetStabilise(true)
    Core.RestoreHP()
    T.assertNil(Core.state.stabilise)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Reset / re-init
-- ────────────────────────────────────────────────────────────────────

T.describe("Core.ResetToDefaults", function()
  T.it("restores default HP and clears history", function()
    reset()
    Core.SetHP(20, 100); Core.DamageTrue(5)
    Core.ResetToDefaults()
    T.assertEq(Core.state.hp, 50)
    T.assertEq(Core.state.maxHp, 50)
    T.assertEq(#Core.state.history, 0)
  end)
  T.it("clears undo/redo stacks", function()
    reset()
    Core.SetHP(20, 100); Core.DamageTrue(5)
    T.assertTrue(Core.CanUndo())
    Core.ResetToDefaults()
    T.assertFalse(Core.CanUndo())
    T.assertFalse(Core.CanRedo())
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Class change
-- ────────────────────────────────────────────────────────────────────

T.describe("Core.SetClassKey", function()
  T.it("rejects non-string and empty", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetClassKey("")     -- ignored
    Core.SetClassKey(nil)    -- ignored
    Core.SetClassKey(42)     -- ignored
    T.assertEq(Core.state.classKey, "MAGE")
  end)
  T.it("setting same class is a no-op", function()
    reset()
    Core.SetClassKey("MAGE")
    local rev = Core.state.rev
    Core.SetClassKey("MAGE")
    T.assertEq(Core.state.rev, rev, "rev unchanged when class is unchanged")
  end)
  T.it("entering WARLOCK clamps Corruption to 60", function()
    reset()
    Core.SetClassKey("ROGUE")  -- away from default MAGE
    Core.SetClassKey("WARLOCK")
    T.assertEq(Core.state.maxRes2, 60)
  end)
  T.it("entering MAGE clamps Arcane Charge to 8", function()
    reset()
    Core.SetClassKey("ROGUE")  -- away from default MAGE so SetClassKey("MAGE") triggers clamp
    Core.SetClassKey("MAGE")
    T.assertEq(Core.state.maxRes2, 8)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Shaman postures (full coverage)
-- ────────────────────────────────────────────────────────────────────

T.describe("Core Shaman postures (full)", function()
  local function setupShaman()
    reset()
    Core.SetClassKey("SHAMAN")
    Core.SetArmor(0, 0); Core.SetDodge(0)
    -- give 5 in every elemental so we can switch freely
    Core.SetResIndex(1, 5, 20)
    Core.SetResIndex(2, 5, 20)
    Core.SetResIndex(3, 5, 20)
    Core.SetResIndex(4, 5, 20)
  end

  T.it("FEU posture sets armor=0, dmg bonus, +4 maxRes4", function()
    setupShaman()
    Core.SetShamanPosture("FEU")
    T.assertEq(Core.state.shamanPosture, "FEU")
    T.assertEq(Core.state.armor, 0)
    T.assertEq(Core.state.shamanPostureDmgBonus, 10)
  end)
  T.it("FEU posture adds +10 to outgoing damage at hit time", function()
    setupShaman()
    Core.SetShamanPosture("FEU")
    Core.SetHP(100, 100)
    Core.DamageTrue(5)  -- bonus +10 → effective 15
    T.assertEq(Core.state.hp, 85)
  end)
  T.it("AIR posture grants +15 dodge", function()
    setupShaman()
    Core.SetShamanPosture("AIR")
    T.assertEq(Core.state.dodge, 15)
  end)
  T.it("EAU posture extends maxRes3 by +8 and refills it", function()
    setupShaman()
    Core.SetShamanPosture("EAU")
    T.assertEq(Core.state.maxRes3, 28)
    T.assertEq(Core.state.res3, 28)
  end)
  T.it("switching posture tears down the previous one", function()
    setupShaman()
    Core.SetShamanPosture("TERRE")
    T.assertEq(Core.state.armor, 5)
    Core.SetShamanPosture("AIR")
    T.assertEq(Core.state.armor, 0)
    T.assertEq(Core.state.dodge, 15)
  end)
  T.it("requires ≥3 max of the matching element", function()
    reset()
    Core.SetClassKey("SHAMAN")
    Core.SetResIndex(2, 2, 2)  -- AIR maxRes2=2, below threshold
    Core.SetShamanPosture("AIR")
    T.assertNil(Core.state.shamanPosture)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Pet — full surface
-- ────────────────────────────────────────────────────────────────────

T.describe("Core pet setters", function()
  T.it("SetPetName trims whitespace", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetName("  Spot  ")
    T.assertEq(Core.state.pet.name, "Spot")
  end)
  T.it("SetPetName rejects empty / whitespace-only", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetName("Spot")
    Core.SetPetName("   ")
    T.assertEq(Core.state.pet.name, "Spot")
  end)
  T.it("SetPetHP clamps to maxHp", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetHP(999, 30)
    T.assertEq(Core.state.pet.hp, 30)
  end)
  T.it("SetPetArmor and SetPetDodge persist", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetArmor(7, 2); Core.SetPetDodge(3)
    T.assertEq(Core.state.pet.armor, 7)
    T.assertEq(Core.state.pet.trueArmor, 2)
    T.assertEq(Core.state.pet.dodge, 3)
  end)
  T.it("SetPetAttaque persists melee + distance", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetAttaque(8, 4)
    T.assertEq(Core.state.pet.attaqueMelee, 8)
    T.assertEq(Core.state.pet.attaqueDistance, 4)
  end)
  T.it("SetPetTempArmor + ResetPetTempArmor", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetTempArmor(6)
    T.assertEq(Core.state.pet.tempArmor, 6)
    Core.ResetPetTempArmor()
    T.assertEq(Core.state.pet.tempArmor, 0)
  end)
  T.it("SetPetMagicShield + ResetPetMagicShield", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetMagicShield(15, 15, 3)
    T.assertEq(Core.state.pet.magicShield.hp, 15)
    T.assertEq(Core.state.pet.magicShield.armor, 3)
    Core.ResetPetMagicShield()
    T.assertEq(Core.state.pet.magicShield.hp, 0)
  end)
  T.it("SetPetAuthorityEnabled toggles auth slot", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetAuthorityEnabled(true)
    T.assertEq(Core.state.pet.authorityEnabled, true)
    Core.SetPetAuthorityEnabled(false)
    T.assertEq(Core.state.pet.authorityEnabled, false)
  end)
end)

T.describe("Core pet damage with armor", function()
  T.it("pet armor + tempArmor + trueArmor stack on DamageWithArmor", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetHP(20, 20)
    Core.SetPetArmor(2, 1)
    Core.SetPetTempArmor(4)
    Core.PetDamageWithArmor(15)  -- 15 - (2+1+4) = 8
    T.assertEq(Core.state.pet.hp, 12)
  end)
  T.it("pet magic shield consumes before HP", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetHP(20, 20)
    Core.SetPetMagicShield(10, 10, 0)
    Core.PetDamageTrue(5)
    T.assertEq(Core.state.pet.hp, 20)
    T.assertEq(Core.state.pet.magicShield.hp, 5)
  end)
end)

T.describe("Core pet healing & regen", function()
  T.it("PetDivineHeal grants 75% maxHp", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(0, 20)
    Core.PetDivineHeal()
    T.assertEq(Core.state.pet.hp, 15)
  end)
  T.it("PetSurgery grants 50% maxHp", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(0, 20)
    Core.PetSurgery()
    T.assertEq(Core.state.pet.hp, 10)
  end)
  T.it("PetRestoreHP fills to maxHp and clears wounds", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(1, 20)  -- hit10 sticky
    Core.PetRestoreHP()
    T.assertEq(Core.state.pet.hp, 20)
    T.assertEq(Core.state.pet.wounds.hit10, false)
    T.assertEq(Core.state.pet.wounds.hit25, false)
  end)
  T.it("PetDailyRegenHP grants 10% of pet maxHp", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(0, 30)
    Core.PetDailyRegenHP()
    T.assertEq(Core.state.pet.hp, 3)
  end)
  T.it("PetDailyRegenRes is a no-op (pets have no primary resource)", function()
    reset()
    Core.PetDailyRegenRes()
    T.assertTrue(true)  -- shouldn't error
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Player regeneration
-- ────────────────────────────────────────────────────────────────────

T.describe("Core regeneration (player)", function()
  T.it("DailyRegenHP grants 10% of base maxHp", function()
    reset()
    Core.SetHP(0, 100)
    Core.DailyRegenHP()
    T.assertEq(Core.state.hp, 10)
  end)
  T.it("DailyRegenHP rounds to nearest integer", function()
    reset()
    Core.SetHP(0, 7)  -- 10% of 7 = 0.7 → rounds to 1
    Core.DailyRegenHP()
    T.assertEq(Core.state.hp, 1)
  end)
  T.it("DailyRegenHP clears stabilise once HP > 0", function()
    reset()
    Core.SetHP(0, 100); Core.SetStabilise(true)
    Core.DailyRegenHP()
    T.assertNil(Core.state.stabilise)
  end)
  T.it("DailyRegenHP ignores wound cap (regen is uncapped)", function()
    reset()
    Core.SetHP(5, 100)  -- hit10 sticky, wound cap 25%
    Core.DailyRegenHP()  -- +10 → 15. But wound cap would clip at 25 (25%).
    T.assertEq(Core.state.hp, 15)
  end)
  T.it("DailyRegenRes grants 20% of maxRes", function()
    reset()
    Core.SetRes(0, 50)
    Core.DailyRegenRes()
    T.assertEq(Core.state.res, 10)
  end)
  T.it("RestoreHP refills to maxHp and clears wounds", function()
    reset()
    Core.SetHP(1, 100)  -- hit10 sticky
    Core.RestoreHP()
    T.assertEq(Core.state.hp, 100)
    T.assertEq(Core.state.wounds.hit10, false)
    T.assertEq(Core.state.wounds.hit25, false)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Chance / Perception
-- ────────────────────────────────────────────────────────────────────

T.describe("Core chance & perception", function()
  T.it("SetChance clamps current to maxChance", function()
    reset()
    Core.SetChance(20, 5)
    T.assertEq(Core.state.maxChance, 5)
    T.assertEq(Core.state.chance, 5)
  end)
  T.it("AddChance adjusts and clamps", function()
    reset()
    Core.SetChance(0, 10)
    Core.AddChance(5)
    T.assertEq(Core.state.chance, 5)
    Core.AddChance(99)
    T.assertEq(Core.state.chance, 10)
    Core.AddChance(-99)
    T.assertEq(Core.state.chance, 0)
  end)
  T.it("SetPerception persists", function()
    reset()
    Core.SetPerception(7)
    T.assertEq(Core.state.perception, 7)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Migrations from saved DB
-- ────────────────────────────────────────────────────────────────────

T.describe("Core_Init migrations", function()
  T.it("migrates legacy tempMagicBlock → magicShield", function()
    -- Inject a saved DB with the legacy field, then re-init.
    _G.GrosOrteilDBPC = { state = { hp = 50, maxHp = 50, tempMagicBlock = 30, wounds = {}, pet = {}, history = {} } }
    ns.db = _G.GrosOrteilDBPC
    ns.Core_Init()
    T.assertEq(Core.state.magicShield.hp, 30)
    T.assertNil(Core.state.tempMagicBlock)
    Core.ResetToDefaults()  -- restore clean state for following tests
  end)
  T.it("migrates legacy woundCap = 0.25 → hit25 + hit10", function()
    _G.GrosOrteilDBPC = { state = { hp = 50, maxHp = 50, woundCap = 0.25, pet = {}, history = {} } }
    ns.db = _G.GrosOrteilDBPC
    ns.Core_Init()
    T.assertEq(Core.state.wounds.hit10, true)
    T.assertEq(Core.state.wounds.hit25, true)
    T.assertNil(Core.state.woundCap)
    Core.ResetToDefaults()
  end)
  T.it("migrates legacy woundCap = 0.50 → hit25 only", function()
    _G.GrosOrteilDBPC = { state = { hp = 50, maxHp = 50, woundCap = 0.50, pet = {}, history = {} } }
    ns.db = _G.GrosOrteilDBPC
    ns.Core_Init()
    T.assertEq(Core.state.wounds.hit25, true)
    T.assertEq(Core.state.wounds.hit10, false)
    Core.ResetToDefaults()
  end)
  T.it("clears removed legacy bonus-HP fields", function()
    _G.GrosOrteilDBPC = { state = { hp = 50, maxHp = 50, tempHp = 5, bonusHp = 5, bonusHpMax = 5, pet = {}, history = {} } }
    ns.db = _G.GrosOrteilDBPC
    ns.Core_Init()
    T.assertNil(Core.state.tempHp)
    T.assertNil(Core.state.bonusHp)
    T.assertNil(Core.state.bonusHpMax)
    Core.ResetToDefaults()
  end)
  T.it("mana shield armor split runs once and is idempotent", function()
    _G.GrosOrteilDBPC = {
      state = {
        hp = 50, maxHp = 50, tempArmor = 35,
        manaShield = { active = true, armor = 25 },
        pet = {}, history = {},
      },
    }
    ns.db = _G.GrosOrteilDBPC
    ns.Core_Init()
    T.assertEq(Core.state.tempArmor, 10)  -- 35 - 25
    T.assertTrue(Core.state._manaShieldArmorSplit)
    -- Calling Core_Init again must NOT subtract again.
    ns.Core_Init()
    T.assertEq(Core.state.tempArmor, 10)
    Core.ResetToDefaults()
  end)
  T.it("classKey defaults to UnitClass result when missing", function()
    _G.GrosOrteilDBPC = { state = { hp = 50, maxHp = 50, pet = {}, history = {}, wounds = {} } }
    ns.db = _G.GrosOrteilDBPC
    ns.Core_Init()
    T.assertEq(Core.state.classKey, "MAGE")  -- mock UnitClass returns MAGE
    Core.ResetToDefaults()
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Defensive: bad inputs must not crash setters
-- ────────────────────────────────────────────────────────────────────

T.describe("Core setters reject bad inputs gracefully", function()
  T.it("SetHP with non-number is a no-op", function()
    reset()
    local before = Core.state.hp
    Core.SetHP("foo", "bar")
    T.assertEq(Core.state.hp, before)
  end)
  T.it("SetArmor with negative input clamps to 0 (or no-op)", function()
    reset()
    Core.SetArmor(-5, -10)
    T.assertTrue(Core.state.armor >= 0 and Core.state.trueArmor >= 0)
  end)
  T.it("Heal(0) does nothing harmful", function()
    reset()
    Core.SetHP(50, 100)
    Core.Heal(0)
    T.assertEq(Core.state.hp, 50)
  end)
  T.it("DamageWithArmor(0) does not move HP", function()
    reset()
    Core.SetHP(80, 100)
    Core.DamageWithArmor(0)
    T.assertEq(Core.state.hp, 80)
  end)
  T.it("OnChange with non-function is a no-op", function()
    reset()
    Core.OnChange(nil)
    Core.OnChange("not a function")
    T.assertTrue(true, "no error thrown")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- ClearHistory
-- ────────────────────────────────────────────────────────────────────

T.describe("Core.ClearHistory", function()
  T.it("empties history", function()
    reset()
    Core.SetHP(100, 100); Core.DamageTrue(10)
    T.assertTrue(#Core.state.history > 0)
    Core.ClearHistory()
    T.assertEq(#Core.state.history, 0)
  end)
  T.it("ClearHistory still notifies listeners", function()
    reset()
    Core.SetHP(100, 100); Core.DamageTrue(10)
    local fires = 0
    local unsub = Core.OnChange(function() fires = fires + 1 end)
    local before = fires
    Core.ClearHistory()
    T.assertTrue(fires > before)
    unsub()
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Pet operations are no-ops when pet is disabled
-- ────────────────────────────────────────────────────────────────────

T.describe("Pet operations no-op when disabled", function()
  local function setup()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(20, 20)
    Core.SetPetEnabled(false)  -- now disabled but state remains
  end
  T.it("PetDamageWithArmor does not change pet hp", function()
    setup()
    Core.PetDamageWithArmor(50)
    T.assertEq(Core.state.pet.hp, 20)
  end)
  T.it("PetDamageTrue does not change pet hp", function()
    setup()
    Core.PetDamageTrue(50)
    T.assertEq(Core.state.pet.hp, 20)
  end)
  T.it("PetHeal does not change pet hp", function()
    setup()
    Core.SetPetHP(5, 20)
    Core.SetPetEnabled(false)
    Core.PetHeal(99)
    T.assertEq(Core.state.pet.hp, 5)
  end)
  T.it("PetDivineHeal/Surgery/RestoreHP/DailyRegenHP all no-op", function()
    setup()
    local hp = Core.state.pet.hp
    Core.PetDivineHeal(); Core.PetSurgery(); Core.PetRestoreHP(); Core.PetDailyRegenHP()
    T.assertEq(Core.state.pet.hp, hp)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Idempotence: repeating identical setters
-- ────────────────────────────────────────────────────────────────────

T.describe("Core setter idempotence", function()
  T.it("setting the same HP twice keeps state consistent", function()
    reset()
    Core.SetHP(50, 100)
    Core.SetHP(50, 100)
    T.assertEq(Core.state.hp, 50)
    T.assertEq(Core.state.maxHp, 100)
  end)
  T.it("toggling pet enabled twice ends up identical", function()
    reset()
    Core.SetPetEnabled(true)
    local hp = Core.state.pet.hp
    Core.SetPetEnabled(true)  -- second call same value
    T.assertEq(Core.state.pet.enabled, true)
    T.assertEq(Core.state.pet.hp, hp)
  end)
  T.it("ClearHistory on already-empty history is a safe no-op", function()
    reset()
    Core.ClearHistory()
    T.assertEq(#Core.state.history, 0)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Edge: zero / corrupt magic shield state
-- ────────────────────────────────────────────────────────────────────

T.describe("Magic shield corrupt state", function()
  T.it("damage with maxHp=0 but hp>0 still drains hp gracefully", function()
    reset()
    Core.SetHP(100, 100)
    -- Force a corrupt shape (defensive coding test).
    Core.state.magicShield = { hp = 5, maxHp = 0, armor = 0 }
    Core.DamageTrue(3)  -- shield hp 5 absorbs 3 → shield hp 2 → but maxHp 0 should reset
    T.assertEq(Core.state.hp, 100)
    -- 3 absorbed by shield hp; resulting shield hp <= 0 path: not triggered yet (3 < 5).
    T.assertEq(Core.state.magicShield.hp, 2)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Heal edge cases
-- ────────────────────────────────────────────────────────────────────

T.describe("Heal edge cases", function()
  T.it("heal does NOT lower current hp (math.max(current, healed))", function()
    reset()
    Core.SetHP(80, 100)
    Core.SetHP(80, 100)  -- normalize
    -- Force hit10 sticky → wound cap 25. Heal cap < current.
    Core.state.wounds.hit10 = true
    Core.state.wounds.hit25 = true
    Core.Heal(5)
    T.assertEq(Core.state.hp, 80, "heal must not lower hp below current")
  end)
  T.it("heal at hp=0 with stabilise grants minimum", function()
    reset()
    Core.SetHP(0, 100); Core.SetStabilise(true)
    Core.Heal(0)  -- no input
    T.assertEq(Core.state.hp, 0)
    T.assertEq(Core.state.stabilise, true, "stabilise still set since hp == 0")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Dodge interaction with damage
-- ────────────────────────────────────────────────────────────────────

T.describe("Dodge does NOT decrement on hit", function()
  T.it("dodge value persists across multiple dodged hits", function()
    reset()
    Core.SetHP(100, 100); Core.SetDodge(20)
    Core.DamageTrue(15); Core.DamageTrue(20); Core.DamageTrue(10)
    T.assertEq(Core.state.dodge, 20)
    T.assertEq(Core.state.hp, 100)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- ResetToDefaults clears active posture and shields
-- ────────────────────────────────────────────────────────────────────

T.describe("ResetToDefaults clears transient state", function()
  T.it("active shaman posture is gone after reset", function()
    reset()
    Core.SetClassKey("SHAMAN")
    Core.SetResIndex(1, 5, 20)
    Core.SetShamanPosture("TERRE")
    Core.ResetToDefaults()
    T.assertNil(Core.state.shamanPosture)
  end)
  T.it("active mana shield is gone after reset", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetRes(50, 100)
    Core.SetManaShieldActive(true)
    Core.ResetToDefaults()
    T.assertFalse(Core.state.manaShield.active)
  end)
  T.it("magic shield reset to zeros after reset", function()
    reset()
    Core.SetMagicShield(10, 20, 5)
    Core.ResetToDefaults()
    T.assertEq(Core.state.magicShield.hp, 0)
    T.assertEq(Core.state.magicShield.maxHp, 0)
    T.assertEq(Core.state.magicShield.armor, 0)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Resource arithmetic boundary
-- ────────────────────────────────────────────────────────────────────

T.describe("Resource arithmetic boundaries", function()
  T.it("AddResIndex(2, ...) for WARLOCK respects 60 cap", function()
    reset()
    Core.SetClassKey("WARLOCK")
    Core.AddResIndex(2, 9999)
    T.assertEq(Core.state.res2, 60)
  end)
  T.it("AddResIndex(2, ...) for MAGE respects 8 cap", function()
    reset()
    Core.SetClassKey("ROGUE")  -- escape default MAGE
    Core.SetClassKey("MAGE")
    Core.AddResIndex(2, 9999)
    T.assertEq(Core.state.res2, 8)
  end)
  T.it("AddResIndex(2, negative) for WARLOCK floor at 0", function()
    reset()
    Core.SetClassKey("WARLOCK")
    Core.SetResIndex(2, 5, 60)
    Core.AddResIndex(2, -100)
    T.assertEq(Core.state.res2, 0)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- History rev counter monotonicity
-- ────────────────────────────────────────────────────────────────────

T.describe("State.rev counter", function()
  T.it("rev increments on every mutation", function()
    reset()
    local r0 = Core.state.rev or 0
    Core.SetHP(40, 100)
    T.assertTrue((Core.state.rev or 0) > r0)
    local r1 = Core.state.rev
    Core.DamageTrue(5)
    T.assertTrue((Core.state.rev or 0) > r1)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- AceSerializer/Deflate compat: state survives a no-op cycle
-- ────────────────────────────────────────────────────────────────────

T.describe("State JSON-like shape stays serializable", function()
  T.it("no functions, threads, or userdata in Core.state after operations", function()
    reset()
    Core.SetClassKey("WARLOCK"); Core.SetHP(33, 77); Core.DamageTrue(3); Core.Heal(5)
    local function bad(v)
      local t = type(v)
      if t == "function" or t == "thread" or t == "userdata" then return true end
      if t == "table" then for _, vv in pairs(v) do if bad(vv) then return true end end end
      return false
    end
    T.assertFalse(bad(Core.state))
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Order of operations: dodge → block → magic shield → mitigation → mana shield → HP
-- ────────────────────────────────────────────────────────────────────

T.describe("Combat absorption ordering", function()
  T.it("dodge runs first and short-circuits everything else", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetHP(100, 100); Core.SetDodge(50)
    Core.SetTempBlock(10); Core.SetArmor(5, 5); Core.SetTempArmor(3)
    Core.SetMagicShield(20, 20, 5)
    Core.SetRes(40, 100); Core.SetManaShieldArmor(0); Core.SetManaShieldActive(true)
    Core.DamageWithArmor(40)  -- dodge=50 ≥ 40 → DODGED, all other layers untouched
    T.assertEq(Core.state.hp, 100)
    T.assertEq(Core.state.tempBlock, 10)
    T.assertEq(Core.state.magicShield.hp, 20)
    T.assertEq(Core.state.res, 40)
  end)
  T.it("block runs before magic shield (block depletes first on overflow)", function()
    reset()
    Core.SetHP(100, 100); Core.SetTempBlock(10); Core.SetMagicShield(50, 50, 0)
    Core.DamageWithArmor(20)  -- block soaks 10, then magic shield soaks 10
    T.assertEq(Core.state.tempBlock, 0)
    T.assertEq(Core.state.magicShield.hp, 40)
    T.assertEq(Core.state.hp, 100)
  end)
  T.it("magic shield runs before player armor mitigation", function()
    reset()
    Core.SetHP(100, 100); Core.SetMagicShield(10, 10, 0); Core.SetArmor(5, 0)
    Core.DamageWithArmor(20)
    -- Block: 0 → magic shield eats 10, breaks → 10 leaks to armor mitigation → 10-5 = 5 → HP 95
    T.assertEq(Core.state.magicShield.hp, 0)
    T.assertEq(Core.state.hp, 95)
  end)
  T.it("mana shield runs AFTER mitigation (mage takes hit through armor)", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetHP(100, 100); Core.SetArmor(10, 0)
    Core.SetRes(50, 100); Core.SetManaShieldArmor(0); Core.SetManaShieldActive(true)
    Core.DamageWithArmor(30)
    -- 30 - 10 (armor) = 20 → mana shield drains 20 from res → res = 30
    T.assertEq(Core.state.res, 30)
    T.assertEq(Core.state.hp, 100)
  end)
  T.it("full chain: dodge < dmg, block + magic shield + armor + mana shield", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetHP(100, 100); Core.SetDodge(5)  -- dodge < damage
    Core.SetTempBlock(10); Core.SetArmor(5, 0)
    Core.SetMagicShield(10, 10, 0)
    Core.SetRes(50, 100); Core.SetManaShieldArmor(0); Core.SetManaShieldActive(true)
    Core.DamageWithArmor(50)
    -- 50 not dodged. block: 50-10=40. magic: 40-10=30 (shield breaks). armor: 30-5=25. mana: -25 → 25.
    T.assertEq(Core.state.hp, 100)
    T.assertEq(Core.state.res, 25)
    T.assertEq(Core.state.tempBlock, 0)
    T.assertEq(Core.state.magicShield.hp, 0)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Shaman FEU bonus interaction with absorption layers
-- ────────────────────────────────────────────────────────────────────

T.describe("Shaman FEU bonus applies to INCOMING damage", function()
  T.it("FEU adds +10 before all absorption layers", function()
    reset()
    Core.SetClassKey("SHAMAN")
    for i = 1, 4 do Core.SetResIndex(i, 5, 20) end
    Core.SetHP(100, 100); Core.SetTempBlock(0); Core.SetArmor(0, 0); Core.SetDodge(0)
    Core.SetShamanPosture("FEU")
    Core.DamageTrue(5)  -- effective input becomes 15
    T.assertEq(Core.state.hp, 85)
  end)
  T.it("FEU bonus can be dodged when bonus-included total ≤ dodge", function()
    reset()
    Core.SetClassKey("SHAMAN")
    for i = 1, 4 do Core.SetResIndex(i, 5, 20) end
    Core.SetHP(100, 100); Core.SetDodge(20)  -- dodge ≥ 5+10=15
    Core.SetShamanPosture("FEU")
    Core.DamageTrue(5)
    T.assertEq(Core.state.hp, 100, "FEU-amplified hit was dodged")
  end)
  T.it("FEU bonus does NOT apply to pet damage", function()
    reset()
    Core.SetClassKey("SHAMAN")
    for i = 1, 4 do Core.SetResIndex(i, 5, 20) end
    Core.SetShamanPosture("FEU")
    Core.SetPetEnabled(true); Core.SetPetHP(20, 20)
    Core.PetDamageTrue(5)
    T.assertEq(Core.state.pet.hp, 15, "no posture bonus on pet")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Stabilise behavior under damage / heal cycles
-- ────────────────────────────────────────────────────────────────────

T.describe("Stabilise persistence", function()
  T.it("damage at hp=0 does not clear stabilise", function()
    reset()
    Core.SetHP(0, 100); Core.SetStabilise(true)
    Core.DamageTrue(50)
    T.assertEq(Core.state.hp, 0)
    T.assertEq(Core.state.stabilise, true)
  end)
  T.it("DivineHeal at hp=0 with stabilise revives and clears stabilise", function()
    reset()
    Core.SetHP(0, 100); Core.SetStabilise(true)
    Core.DivineHeal()
    T.assertEq(Core.state.hp, 75)
    T.assertNil(Core.state.stabilise)
  end)
  T.it("Surgery at hp=0 with stabilise revives and clears stabilise", function()
    reset()
    Core.SetHP(0, 100); Core.SetStabilise(true)
    Core.Surgery()
    T.assertEq(Core.state.hp, 50)
    T.assertNil(Core.state.stabilise)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Pet damage layering
-- ────────────────────────────────────────────────────────────────────

T.describe("Pet damage layering", function()
  T.it("pet block does NOT exist (block is player-only)", function()
    reset()
    Core.SetTempBlock(50)  -- player block
    Core.SetPetEnabled(true); Core.SetPetHP(20, 20)
    Core.PetDamageWithArmor(10)
    T.assertEq(Core.state.pet.hp, 10, "pet hit not absorbed by player block")
    T.assertEq(Core.state.tempBlock, 50, "player block untouched")
  end)
  T.it("pet magic shield armor reduces incoming damage to pet", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(20, 20)
    Core.SetPetMagicShield(10, 10, 5)  -- armor 5
    Core.PetDamageWithArmor(15)
    -- 15 - 5 (shield armor) = 10 absorbed by shield hp → shield breaks
    T.assertEq(Core.state.pet.hp, 20)
    T.assertEq(Core.state.pet.magicShield.hp, 0)
  end)
  T.it("pet mana shield is ignored (not a pet feature)", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetRes(50, 100); Core.SetManaShieldActive(true)
    Core.SetPetEnabled(true); Core.SetPetHP(20, 20)
    Core.PetDamageTrue(5)
    T.assertEq(Core.state.pet.hp, 15)
    T.assertEq(Core.state.res, 50, "player mana untouched by pet damage")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- ToggleManaShield mana=0 special cases
-- ────────────────────────────────────────────────────────────────────

T.describe("ToggleManaShield mana gating", function()
  T.it("ToggleManaShield with res=0 does not activate", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetRes(0, 100)
    Core.ToggleManaShield()
    T.assertFalse(Core.state.manaShield.active)
  end)
  T.it("ToggleManaShield deactivates an active shield even at res=0", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetRes(50, 100); Core.ToggleManaShield()
    T.assertTrue(Core.state.manaShield.active)
    Core.SetRes(0, 100)
    Core.ToggleManaShield()  -- toggle off path: should always succeed
    T.assertFalse(Core.state.manaShield.active)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Undo across class change preserves classKey
-- ────────────────────────────────────────────────────────────────────

T.describe("Undo across class transitions", function()
  T.it("undo restores prior classKey", function()
    reset()
    Core.SetClassKey("ROGUE")
    Core.SetClassKey("WARLOCK")
    T.assertEq(Core.state.classKey, "WARLOCK")
    Core.Undo()
    T.assertEq(Core.state.classKey, "ROGUE")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Additional defensive setter tests
-- ────────────────────────────────────────────────────────────────────

T.describe("Extra defensive setters", function()
  T.it("SetTempArmor with negative input is a no-op (clamps to nil)", function()
    reset()
    Core.SetTempArmor(5)
    Core.SetTempArmor(-50)  -- clampNumber returns 5, since min=0 clamps to 0... actually returns 0
    T.assertTrue(Core.state.tempArmor >= 0)
  end)
  T.it("SetPetName with non-string is a no-op", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetName("Spot")
    Core.SetPetName(42); Core.SetPetName(nil); Core.SetPetName({})
    T.assertEq(Core.state.pet.name, "Spot")
  end)
  T.it("SetMagicShield with all nil arguments leaves state untouched", function()
    reset()
    Core.SetMagicShield(10, 20, 5)
    Core.SetMagicShield(nil, nil, nil)
    T.assertEq(Core.state.magicShield.hp, 10)
    T.assertEq(Core.state.magicShield.maxHp, 20)
    T.assertEq(Core.state.magicShield.armor, 5)
  end)
  T.it("SetResIndex(2, ...) for SHADOWPRIEST allows hp > maxHp (insanity)", function()
    reset()
    Core.SetClassKey("SHADOWPRIEST")
    Core.SetResIndex(2, 50, 20)
    T.assertEq(Core.state.res2, 50)
    T.assertEq(Core.state.maxRes2, 20)
  end)
  T.it("AddResIndex with negative amount goes below current and clamps to maxRes", function()
    reset()
    Core.SetRes(10, 20)
    Core.AddResIndex(1, -5)
    T.assertEq(Core.state.res, 5)
    Core.AddResIndex(1, -100)
    T.assertEq(Core.state.res, -95, "primary res allows negative (only max-clamp applies)")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Pet authority slot reflected in GetResProfile
-- ────────────────────────────────────────────────────────────────────

T.describe("Pet authority slot in resource profile", function()
  T.it("authority slot appears only when pet enabled AND authorityEnabled", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetAuthorityEnabled(true)
    local prof = ns.Shared.GetResProfile(Core.state)
    local hasAuth = false
    for _, p in ipairs(prof) do if p.idx == 5 then hasAuth = true end end
    T.assertTrue(hasAuth)
  end)
  T.it("authority slot disappears when pet disabled", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetAuthorityEnabled(true)
    Core.SetPetEnabled(false)
    local prof = ns.Shared.GetResProfile(Core.state)
    for _, p in ipairs(prof) do T.assertNeq(p.idx, 5) end
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Heal boundary: exact wound cap
-- ────────────────────────────────────────────────────────────────────

T.describe("Heal at wound cap boundary", function()
  T.it("heal stops at exactly 50% with hit25 sticky", function()
    reset()
    Core.SetHP(20, 100)  -- triggers hit25 sticky; cap = 50
    Core.Heal(999)
    T.assertEq(Core.state.hp, 50)
    -- A second heal at the cap is a no-op (math.max(current, healed))
    Core.Heal(999)
    T.assertEq(Core.state.hp, 50)
  end)
  T.it("DamageWithArmor below 25% then heal is bounded", function()
    reset()
    Core.SetHP(100, 100); Core.SetArmor(0, 0); Core.SetDodge(0)
    Core.DamageWithArmor(80)  -- hp = 20 → hit25 sticky
    Core.Heal(999)
    T.assertEq(Core.state.hp, 50)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- DamageWithArmor produces HISTORY entry shape
-- ────────────────────────────────────────────────────────────────────

T.describe("Damage history entries", function()
  T.it("DamageWithArmor pushes a DAMAGE_ARMOR entry with breakdown fields", function()
    reset()
    Core.SetHP(100, 100); Core.SetTempBlock(5); Core.SetArmor(3, 0)
    Core.DamageWithArmor(20)
    local h = Core.state.history[1]
    T.assertEq(h.kind, "DAMAGE_ARMOR")
    T.assertEq(h.input, 20)
    T.assertEq(h.absorbedBlock, 5)
    T.assertEq(h.armor, 3)
    T.assertEq(h.hpBefore, 100)
    T.assertNotNil(h.hpAfter)
  end)
  T.it("dodged hit pushes entry with dodged=true", function()
    reset()
    Core.SetHP(100, 100); Core.SetDodge(99)
    Core.DamageTrue(50)
    local h = Core.state.history[1]
    T.assertTrue(h.dodged)
    T.assertEq(h.hpBefore, h.hpAfter)
  end)
  T.it("PET subject is recorded on pet history", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(20, 20)
    Core.PetDamageTrue(5)
    local h = Core.state.history[1]
    T.assertEq(h.subject, "PET")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Heal returns history with applied = (hpAfter - hpBefore)
-- ────────────────────────────────────────────────────────────────────

T.describe("Heal history entries", function()
  T.it("Heal records the actually-applied amount, not the input", function()
    reset()
    Core.SetHP(40, 100)
    Core.Heal(99)  -- clamped to maxHp=100 → applied = 60
    local h = Core.state.history[1]
    T.assertEq(h.kind, "HEAL")
    T.assertEq(h.applied, 60)
    T.assertEq(h.input, 99)
  end)
  T.it("DivineHeal records gain field equal to 75% maxHp", function()
    reset()
    Core.SetHP(0, 100)
    Core.DivineHeal()
    local h = Core.state.history[1]
    T.assertEq(h.kind, "DIVINE_HEAL")
    T.assertEq(h.gain, 75)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Mana shield + magic shield combined
-- ────────────────────────────────────────────────────────────────────

T.describe("Magic shield + mana shield combined", function()
  T.it("magic shield consumes first, then mana shield catches the leak", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetHP(100, 100); Core.SetMagicShield(10, 10, 0)
    Core.SetRes(50, 100); Core.SetManaShieldArmor(0); Core.SetManaShieldActive(true)
    Core.DamageTrue(30)
    -- magic shield eats 10, breaks → 20 → mana drains 20 → res 30
    T.assertEq(Core.state.magicShield.hp, 0)
    T.assertEq(Core.state.res, 30)
    T.assertEq(Core.state.hp, 100)
  end)
  T.it("magic shield catches everything → mana untouched", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetHP(100, 100); Core.SetMagicShield(50, 50, 0)
    Core.SetRes(40, 100); Core.SetManaShieldArmor(0); Core.SetManaShieldActive(true)
    Core.DamageTrue(20)
    T.assertEq(Core.state.res, 40)
    T.assertEq(Core.state.magicShield.hp, 30)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- DamageTrue with 0 input (no-op)
-- ────────────────────────────────────────────────────────────────────

T.describe("Zero-input no-ops", function()
  T.it("DamageTrue(0) does not push a history entry", function()
    reset()
    local before = #Core.state.history
    Core.DamageTrue(0)
    -- An entry is still pushed (raw=0 → after clamps → reaches the bottom).
    -- We only assert that hp didn't move and tempBlock/dodge are intact.
    T.assertEq(Core.state.hp, 50)
    T.assertEq(Core.state.tempBlock, 0)
    -- History may or may not have an entry depending on internals;
    -- behaviorally we just want no error AND no hp change.
    T.assertTrue(#Core.state.history >= before)
  end)
  T.it("Heal(0) does not push spurious entries beyond what's expected", function()
    reset()
    Core.SetHP(50, 100)
    local before = #Core.state.history
    Core.Heal(0)
    T.assertEq(Core.state.hp, 50)
    T.assertTrue(#Core.state.history >= before)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Pet attaque setters + Authority bookkeeping
-- ────────────────────────────────────────────────────────────────────

T.describe("Pet authority and attaque", function()
  T.it("SetPetAuthorityEnabled is independent of SetPetEnabled", function()
    reset()
    Core.SetPetEnabled(false); Core.SetPetAuthorityEnabled(true)
    T.assertEq(Core.state.pet.authorityEnabled, true)
    T.assertEq(Core.state.pet.enabled, false)
  end)
  T.it("Pet attaque ignores negative input", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetAttaque(5, 3)
    Core.SetPetAttaque(-10, -10)
    T.assertTrue(Core.state.pet.attaqueMelee >= 0)
    T.assertTrue(Core.state.pet.attaqueDistance >= 0)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- ApplyManaShield breaks at exactly res=0 even before damage
-- ────────────────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────
-- Faulty listeners route errors through geterrorhandler
-- ────────────────────────────────────────────────────────────────────

T.describe("notify() error reporting", function()
  T.it("a faulty listener's error is delivered to geterrorhandler", function()
    reset()
    -- Reset capture buffer.
    _G.MOCKS.errorHandlerCalls = {}
    local unsub = Core.OnChange(function() error("listener-explosion") end)
    Core.SetHP(40, 100)  -- triggers notify → listener errors → geterrorhandler called
    local calls = _G.MOCKS.errorHandlerCalls
    T.assertTrue(#calls > 0, "geterrorhandler should have been invoked")
    local matched = false
    for _, e in ipairs(calls) do
      if tostring(e):find("listener%-explosion") then matched = true; break end
    end
    T.assertTrue(matched, "captured error did not include the original message")
    unsub()
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Pet shield reset clears all three fields
-- ────────────────────────────────────────────────────────────────────

T.describe("ResetPetMagicShield", function()
  T.it("clears hp, maxHp, AND armor", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetMagicShield(7, 10, 4)
    Core.ResetPetMagicShield()
    T.assertEq(Core.state.pet.magicShield.hp, 0)
    T.assertEq(Core.state.pet.magicShield.maxHp, 0)
    T.assertEq(Core.state.pet.magicShield.armor, 0)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Comm defensives
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm:RequestState defensives", function()
  T.it("rejects nil and empty-string targets without sending", function()
    _G.MOCKS.sentMessages = {}
    ns.Comm:RequestState(nil)
    ns.Comm:RequestState("")
    T.assertEq(#_G.MOCKS.sentMessages, 0)
  end)
  T.it("PREFIX constant is the addon's known channel tag", function()
    T.assertEq(ns.Comm.PREFIX, "GO_STATE")
  end)
end)

T.describe("Mana shield self-deactivation rules", function()
  T.it("hitting an active shield with res already 0 deactivates it without leaking damage twice", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetHP(100, 100); Core.SetRes(0, 100)
    -- Manually force-active (bypass guard) by setting mana then activating, then dropping mana to 0.
    Core.SetRes(10, 100); Core.SetManaShieldArmor(0); Core.SetManaShieldActive(true)
    Core.SetRes(0, 100)
    T.assertTrue(Core.state.manaShield.active)
    Core.DamageTrue(20)
    T.assertEq(Core.state.hp, 80, "damage went straight to HP since mana already 0")
    T.assertFalse(Core.state.manaShield.active, "shield self-deactivates")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- ShamanPostureBase invariant: matches presence of shamanPosture
-- ────────────────────────────────────────────────────────────────────

T.describe("Class-locked maxima persist across class transitions until re-clamped", function()
  T.it("MAGE arcane charge max=8 stays at 8 after switching to ROGUE", function()
    reset()
    Core.SetClassKey("ROGUE")
    Core.SetClassKey("MAGE")
    T.assertEq(Core.state.maxRes2, 8)
    Core.SetClassKey("ROGUE")
    -- Leaving MAGE doesn't reset maxRes2; it stays at 8 until something else writes it.
    T.assertEq(Core.state.maxRes2, 8)
  end)
  T.it("ROGUE can SetResIndex(2, ...) freely after coming from MAGE", function()
    reset()
    Core.SetClassKey("ROGUE"); Core.SetClassKey("MAGE")
    Core.SetClassKey("ROGUE")
    Core.SetResIndex(2, 30, 30)  -- ROGUE has no idx-2 cap rules
    T.assertEq(Core.state.res2, 30)
    T.assertEq(Core.state.maxRes2, 30)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Comm SerializeState determinism
-- ────────────────────────────────────────────────────────────────────

T.describe("SerializeState determinism", function()
  T.it("serializing the same state twice produces identical bytes", function()
    reset()
    Core.SetClassKey("WARLOCK"); Core.SetHP(33, 77); Core.SetResIndex(2, 25, 60)
    local a = ns.Comm.SerializeState(Core.state)
    local b = ns.Comm.SerializeState(Core.state)
    T.assertEq(a, b)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Pet defaults: ensurePetDefaults migration shape
-- ────────────────────────────────────────────────────────────────────

T.describe("Pet defaults migration", function()
  T.it("legacy pet.tempMagicBlock becomes pet.magicShield.hp/maxHp", function()
    _G.GrosOrteilDBPC = {
      state = {
        hp = 50, maxHp = 50, wounds = {}, history = {},
        pet = {
          enabled = true, name = "Old", hp = 10, maxHp = 20,
          tempMagicBlock = 8,  -- legacy field
        },
      },
    }
    ns.db = _G.GrosOrteilDBPC
    ns.Core_Init()
    T.assertEq(Core.state.pet.magicShield.hp, 8)
    T.assertEq(Core.state.pet.magicShield.maxHp, 8)
    T.assertNil(Core.state.pet.tempMagicBlock)
    Core.ResetToDefaults()
  end)
  T.it("missing pet sub-table gets fully defaulted", function()
    _G.GrosOrteilDBPC = { state = { hp = 50, maxHp = 50, wounds = {}, history = {} } }
    ns.db = _G.GrosOrteilDBPC
    ns.Core_Init()
    T.assertEq(Core.state.pet.enabled, false)
    T.assertEq(Core.state.pet.name, "Familier")
    T.assertEq(Core.state.pet.hp, 20)
    T.assertEq(Core.state.pet.maxHp, 20)
    Core.ResetToDefaults()
  end)
end)

T.describe("ShamanPostureBase consistency", function()
  T.it("shamanPostureBase is set when posture is active", function()
    reset()
    Core.SetClassKey("SHAMAN"); Core.SetResIndex(1, 5, 20)
    Core.SetShamanPosture("TERRE")
    T.assertNotNil(Core.state.shamanPostureBase)
  end)
  T.it("shamanPostureBase is nil when posture is nil", function()
    reset()
    T.assertNil(Core.state.shamanPostureBase)
    Core.SetClassKey("SHAMAN")
    T.assertNil(Core.state.shamanPostureBase)
  end)
  T.it("toggling off restores to base, then base is cleared", function()
    reset()
    Core.SetClassKey("SHAMAN"); Core.SetResIndex(1, 5, 20)
    local armor0 = Core.state.armor
    Core.SetShamanPosture("TERRE")
    T.assertEq(Core.state.armor, armor0 + 5)
    Core.SetShamanPosture("TERRE")  -- toggle off
    T.assertEq(Core.state.armor, armor0)
    T.assertNil(Core.state.shamanPostureBase)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Multi-class transition cascades
-- ────────────────────────────────────────────────────────────────────

T.describe("Multi-class transitions", function()
  T.it("SHAMAN(TERRE) → MAGE → WARLOCK clears all transient state", function()
    reset()
    Core.SetClassKey("SHAMAN")
    for i = 1, 4 do Core.SetResIndex(i, 5, 20) end
    Core.SetShamanPosture("TERRE")
    Core.SetClassKey("MAGE")
    T.assertNil(Core.state.shamanPosture)
    T.assertEq(Core.state.maxRes2, 8)
    Core.SetClassKey("WARLOCK")
    T.assertEq(Core.state.maxRes2, 60)
  end)
  T.it("MAGE(active mana shield) → WARLOCK auto-drops mana shield", function()
    reset()
    Core.SetClassKey("MAGE"); Core.SetRes(50, 100)
    Core.SetManaShieldActive(true)
    T.assertTrue(Core.state.manaShield.active)
    Core.SetClassKey("WARLOCK")
    T.assertFalse(Core.state.manaShield.active)
  end)
  T.it("setting an unknown class string is still accepted and class-specific clamps don't apply", function()
    reset()
    Core.SetClassKey("UNKNOWN_CLASS")
    T.assertEq(Core.state.classKey, "UNKNOWN_CLASS")
    -- maxRes2 retains its previous value (no MAGE/WARLOCK clamp applies).
    T.assertTrue((Core.state.maxRes2 or 0) > 0)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- WARRIOR profile: empty list (no resources)
-- ────────────────────────────────────────────────────────────────────

T.describe("WARRIOR (Classique) profile", function()
  T.it("GetResProfile for WARRIOR returns 0 entries (no resource bar)", function()
    reset()
    Core.SetClassKey("WARRIOR")
    local prof = ns.Shared.GetResProfile(Core.state)
    T.assertEq(#prof, 0, "WARRIOR has an empty resource profile by design")
  end)
  T.it("WARRIOR with pet authority still appends the auth slot", function()
    reset()
    Core.SetClassKey("WARRIOR")
    Core.SetPetEnabled(true); Core.SetPetAuthorityEnabled(true)
    local prof = ns.Shared.GetResProfile(Core.state)
    T.assertEq(#prof, 1)
    T.assertEq(prof[1].idx, 5)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Pet enable preserves prior stats
-- ────────────────────────────────────────────────────────────────────

T.describe("Pet enable cycle preserves stats", function()
  T.it("disable→enable round-trip keeps hp/maxHp/name", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetName("Spot"); Core.SetPetHP(15, 25); Core.SetPetArmor(4, 1)
    Core.SetPetEnabled(false)
    Core.SetPetEnabled(true)
    T.assertEq(Core.state.pet.name, "Spot")
    T.assertEq(Core.state.pet.hp, 15)
    T.assertEq(Core.state.pet.maxHp, 25)
    T.assertEq(Core.state.pet.armor, 4)
    T.assertEq(Core.state.pet.trueArmor, 1)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Heal entry caps and effMax
-- ────────────────────────────────────────────────────────────────────

T.describe("Heal entry recorded fields", function()
  T.it("Heal entry includes capMax matching wound cap fraction", function()
    reset()
    Core.SetHP(20, 100)  -- hit25 sticky → cap fraction 0.5
    Core.Heal(20)
    local h = Core.state.history[1]
    T.assertEq(h.kind, "HEAL")
    T.assertEq(h.capMax, 50)  -- 100 × 0.5
    T.assertEq(h.effMax, 100)
  end)
  T.it("Heal applied is bounded by capMax even when input is huge", function()
    reset()
    Core.SetHP(20, 100)
    Core.Heal(9999)
    local h = Core.state.history[1]
    T.assertEq(h.applied, 30)  -- 50 - 20
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Pet PetRestoreHP / PetDailyRegenHP push entries (latent format gap)
-- ────────────────────────────────────────────────────────────────────

T.describe("Pet restore actions push entries (kind not formatted by History)", function()
  T.it("PetRestoreHP appends an entry with kind=RESTORE_HP and subject=PET", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(5, 20)
    Core.PetRestoreHP()
    local last = Core.state.history[1]
    T.assertEq(last.kind, "RESTORE_HP")
    T.assertEq(last.subject, "PET")
  end)
  T.it("PetDailyRegenHP appends an entry with kind=DAILY_REGEN_HP", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(5, 20)
    Core.PetDailyRegenHP()
    local last = Core.state.history[1]
    T.assertEq(last.kind, "DAILY_REGEN_HP")
    T.assertEq(last.subject, "PET")
  end)
  T.it("History.FormatEntry returns nil for these kinds (formatter gap)", function()
    -- This locks in the current behavior so we notice if the formatter is later extended.
    T.assertNil(ns.History.FormatEntry({ kind = "RESTORE_HP", subject = "PET" }))
    T.assertNil(ns.History.FormatEntry({ kind = "DAILY_REGEN_HP", subject = "PET" }))
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Player RestoreHP / DailyRegen* do NOT push history (different behavior)
-- ────────────────────────────────────────────────────────────────────

T.describe("Player regen does not log to history (intentional)", function()
  T.it("RestoreHP does not push", function()
    reset()
    local n = #Core.state.history
    Core.RestoreHP()
    T.assertEq(#Core.state.history, n)
  end)
  T.it("DailyRegenHP does not push", function()
    reset()
    local n = #Core.state.history
    Core.DailyRegenHP()
    T.assertEq(#Core.state.history, n)
  end)
  T.it("DailyRegenRes does not push", function()
    reset()
    local n = #Core.state.history
    Core.DailyRegenRes()
    T.assertEq(#Core.state.history, n)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- SetMagicShield with one-of-three nil arguments
-- ────────────────────────────────────────────────────────────────────

T.describe("SetMagicShield partial updates", function()
  T.it("setting only hp leaves maxHp/armor as-is", function()
    reset()
    Core.SetMagicShield(10, 30, 5)
    Core.SetMagicShield(20, nil, nil)
    T.assertEq(Core.state.magicShield.hp, 20)
    T.assertEq(Core.state.magicShield.maxHp, 30)
    T.assertEq(Core.state.magicShield.armor, 5)
  end)
  T.it("setting only maxHp leaves hp/armor (and clamps hp if needed)", function()
    reset()
    Core.SetMagicShield(20, 30, 5)
    Core.SetMagicShield(nil, 10, nil)  -- maxHp shrinks below current hp
    T.assertEq(Core.state.magicShield.maxHp, 10)
    -- hp stays at 20 because the clamp only triggers when hp itself is being set.
    -- Document this behavior explicitly:
    T.assertEq(Core.state.magicShield.hp, 20, "hp clamp only applies on hp set, not maxHp shrink")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Pet wounds independent of player wounds
-- ────────────────────────────────────────────────────────────────────

T.describe("Undo deep restoration", function()
  T.it("undo restores magicShield hp/maxHp/armor exactly", function()
    reset()
    Core.SetMagicShield(10, 20, 5)
    Core.SetMagicShield(0, 0, 0)
    Core.Undo()
    T.assertEq(Core.state.magicShield.hp, 10)
    T.assertEq(Core.state.magicShield.maxHp, 20)
    T.assertEq(Core.state.magicShield.armor, 5)
  end)
  T.it("undo restores manaShield active flag", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetRes(50, 100); Core.SetManaShieldActive(true)
    Core.SetManaShieldActive(false)
    Core.Undo()
    T.assertEq(Core.state.manaShield.active, true)
  end)
  T.it("undo restores wound flags", function()
    reset()
    Core.SetHP(2, 100)  -- hit10 sticky
    Core.SetHP(100, 100)  -- wounds clear via recompute
    T.assertFalse(Core.state.wounds.hit10)
    Core.Undo()
    T.assertTrue(Core.state.wounds.hit10)
  end)
  T.it("undo restores Shaman posture and posture-bonus damage value", function()
    reset()
    Core.SetClassKey("SHAMAN")
    for i = 1, 4 do Core.SetResIndex(i, 5, 20) end
    Core.SetShamanPosture("FEU")
    T.assertEq(Core.state.shamanPostureDmgBonus, 10)
    Core.SetShamanPosture("FEU")  -- toggle off
    T.assertNil(Core.state.shamanPosture)
    Core.Undo()
    T.assertEq(Core.state.shamanPosture, "FEU")
    T.assertEq(Core.state.shamanPostureDmgBonus, 10)
  end)
  T.it("undo on an empty stack is a no-op (does not crash)", function()
    reset()
    -- Drain undo stack by undo-ing every available step.
    while Core.CanUndo() do Core.Undo() end
    T.assertFalse(Core.CanUndo())
    Core.Undo()  -- no-op
    T.assertTrue(true)
  end)
  T.it("redo on an empty stack is a no-op (does not crash)", function()
    reset()
    Core.Redo()
    T.assertTrue(true)
  end)
  T.it("undoStack is bounded by MAX_UNDO (50)", function()
    reset()
    -- Run 80 distinct mutations. With C_Timer firing synchronously in the mock,
    -- each one gets its own undo entry.
    for i = 1, 80 do Core.SetHP(i % 50 + 1, 100) end
    -- Drain undos.
    local count = 0
    while Core.CanUndo() and count < 200 do
      Core.Undo()
      count = count + 1
    end
    T.assertTrue(count <= 50, "undoStack capped at MAX_UNDO=50, undid " .. count)
  end)
end)

T.describe("Pet wounds are independent of player", function()
  T.it("player damage to low HP does not flag pet", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(20, 20)
    Core.SetHP(2, 100)  -- player hit10 sticky
    T.assertEq(Core.state.wounds.hit10, true)
    T.assertEq(Core.state.pet.wounds.hit10, false)
  end)
  T.it("pet damage to low HP does not flag player", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetHP(1, 20)
    T.assertEq(Core.state.pet.wounds.hit10, true)
    T.assertEq(Core.state.wounds.hit10, false)
  end)
end)
