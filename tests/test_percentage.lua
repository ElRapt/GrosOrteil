---@diagnostic disable: undefined-global
local T = _G.T
local ns = _G.NS
local Core = ns.Core
local History = ns.History

local function reset()
  Core.ResetToDefaults()
  Core.SetHP(100, 200)
  Core.SetPetEnabled(true)
  Core.SetPetHP(50, 100)
  Core.BreakUndoCoalesce()
end

T.describe("Signed percentage actions", function()
  T.it("emits the actual signed HP change for the correct sheet and omits zero changes", function()
    reset()
    local events={}
    Core.SetCombatTextHandler(function(kind,amount,subject) events[#events+1]={kind,amount,subject} end)
    Core.PercentageHeal(-15)
    Core.PercentageHeal(100)
    Core.PercentageHeal(15) -- already full
    Core.PercentageHeal("invalid")
    Core.PetPercentageHeal(-100)
    Core.PetPercentageHeal(-15) -- already zero
    Core.PetPercentageHeal(15)
    Core.SetCombatTextHandler(nil)
    T.assertEq(#events,4)
    local expected={{"DAMAGE",30,"CHAR"},{"HEAL",130,"CHAR"},{"DAMAGE",50,"PET"},{"HEAL",15,"PET"}}
    for i,event in ipairs(expected) do
      for j,value in ipairs(event) do T.assertEq(events[i][j],value) end
    end
  end)

  T.it("accepts both signs and preserves fractional percentages", function()
    for _, case in ipairs({ {-100, 0, 0}, {-15, 70, 35}, {-1, 98, 49},
        {1, 102, 51}, {15, 130, 65}, {100, 200, 100},
        {-12.5, 75, 37.5}, {12.5, 125, 62.5}, {"+15", 130, 65}, {"-15", 70, 35} }) do
      reset()
      T.assertTrue(Core.PercentageHeal(case[1]))
      T.assertTrue(Core.PetPercentageHeal(case[1]))
      T.assertEq(Core.state.hp, case[2])
      T.assertEq(Core.state.pet.hp, case[3])
    end
  end)

  T.it("rejects invalid percentages without HP, history or revision changes", function()
    reset()
    local invalid = { 0, 0.5, -0.5, 101, -101, 1e20, -1e20, math.huge, -math.huge, 0 / 0, "", "abc", "--15", "+-15", {}, true }
    local hp, petHp, historyCount, rev = Core.state.hp, Core.state.pet.hp, #Core.state.history, Core.state.rev
    for _, value in ipairs(invalid) do
      T.assertFalse(Core.PercentageHeal(value))
      T.assertFalse(Core.PetPercentageHeal(value))
    end
    T.assertFalse(Core.PercentageHeal(nil))
    T.assertFalse(Core.PetPercentageHeal(nil))
    T.assertEq(Core.state.hp, hp)
    T.assertEq(Core.state.pet.hp, petHp)
    T.assertEq(#Core.state.history, historyCount)
    T.assertEq(Core.state.rev, rev)
  end)

  T.it("keeps both meter counters unchanged across percentage actions and undo", function()
    reset()
    Core.CreditHealGiven(23)
    Core.DamageDirect(7)
    local dmg, heal = Core.state.meter.dmg, Core.state.meter.heal
    for _, action in ipairs({ Core.PercentageHeal, Core.PetPercentageHeal }) do
      for _, value in ipairs({ -15, 15, -100, -15, 100, 15 }) do
        Core.BreakUndoCoalesce()
        T.assertTrue(action(value))
        T.assertEq(Core.state.meter.dmg, dmg)
        T.assertEq(Core.state.meter.heal, heal)
        Core.Undo()
        T.assertEq(Core.state.meter.dmg, dmg)
        T.assertEq(Core.state.meter.heal, heal)
        Core.Redo()
        T.assertEq(Core.state.meter.dmg, dmg)
        T.assertEq(Core.state.meter.heal, heal)
      end
    end
  end)

  T.it("preserves fractional applied amounts in history and floating feedback", function()
    reset()
    Core.SetHP(99.5, 100); Core.SetPetHP(0.25, 100)
    local events = {}
    Core.SetCombatTextHandler(function(kind, amount, subject)
      events[#events + 1] = { kind, amount, subject }
    end)
    Core.PercentageHeal(12.5)
    Core.PetPercentageHeal(-12.5)
    Core.SetCombatTextHandler(nil)
    T.assertEq(Core.state.hp, 100); T.assertEq(Core.state.pet.hp, 0)
    T.assertEq(Core.state.history[2].applied, 0.5)
    T.assertEq(Core.state.history[1].applied, 0.25)
    T.assertEq(events[1][1], "HEAL"); T.assertEq(events[1][2], 0.5); T.assertEq(events[1][3], "CHAR")
    T.assertEq(events[2][1], "DAMAGE"); T.assertEq(events[2][2], 0.25); T.assertEq(events[2][3], "PET")
  end)

  T.it("heals from maximum HP for unsigned and explicitly positive input", function()
    reset()
    T.assertTrue(Core.PercentageHeal("15"))
    T.assertEq(Core.state.hp, 130)
    T.assertTrue(Core.PercentageHeal("+15"))
    T.assertEq(Core.state.hp, 160)
    T.assertEq(Core.state.history[1].kind, "PERCENT_HEAL")
    T.assertEq(Core.state.history[1].applied, 30)
  end)

  T.it("damages player HP directly and preserves armor and shields", function()
    reset()
    Core.SetArmor(100, 100)
    Core.SetTempArmor(100)
    Core.SetMagicShield(100, 100, 100)
    T.assertTrue(Core.PercentageHeal("-15"))
    T.assertEq(Core.state.hp, 70)
    T.assertEq(Core.state.maxHp, 200)
    T.assertEq(Core.state.armor, 100)
    T.assertEq(Core.state.trueArmor, 100)
    T.assertEq(Core.state.tempArmor, 100)
    T.assertEq(Core.state.magicShield.hp, 100)
    T.assertEq(Core.state.history[1].kind, "PERCENT_DAMAGE")
    T.assertEq(Core.state.history[1].percent, -15)
    T.assertEq(Core.state.history[1].applied, 30)
  end)

  T.it("clamps player changes at zero and max HP and records actual amounts", function()
    reset()
    T.assertTrue(Core.PercentageHeal(-100))
    T.assertEq(Core.state.hp, 0)
    T.assertEq(Core.state.history[1].applied, 100)
    T.assertTrue(Core.state.wounds.hit10)
    T.assertTrue(Core.PercentageHeal(100))
    T.assertEq(Core.state.hp, 200)
    T.assertEq(Core.state.history[1].applied, 200)
    T.assertFalse(Core.state.wounds.hit10)
    T.assertTrue(Core.PercentageHeal(15))
    T.assertEq(Core.state.hp, 200)
    T.assertEq(Core.state.history[1].applied, 0)
  end)

  T.it("applies both signs to the pet independently and respects pet HP bounds", function()
    reset()
    Core.SetPetArmor(100, 100)
    Core.SetPetTempArmor(100)
    Core.SetPetMagicShield(100, 100, 100)
    T.assertTrue(Core.PetPercentageHeal("-15"))
    T.assertEq(Core.state.pet.hp, 35)
    T.assertEq(Core.state.pet.armor, 100)
    T.assertEq(Core.state.pet.trueArmor, 100)
    T.assertEq(Core.state.pet.tempArmor, 100)
    T.assertEq(Core.state.pet.magicShield.hp, 100)
    T.assertEq(Core.state.history[1].subject, "PET")
    T.assertEq(Core.state.history[1].applied, 15)
    T.assertTrue(Core.PetPercentageHeal("+15"))
    T.assertEq(Core.state.pet.hp, 50)
    T.assertTrue(Core.PetPercentageHeal(-100))
    T.assertEq(Core.state.pet.hp, 0)
    T.assertEq(Core.state.history[1].applied, 50)
    T.assertTrue(Core.state.pet.wounds.hit10)
    T.assertTrue(Core.PetPercentageHeal(100))
    T.assertEq(Core.state.pet.hp, 100)
    T.assertFalse(Core.state.pet.wounds.hit10)
    T.assertEq(Core.state.hp, 100)
  end)

  T.it("does not modify a disabled pet", function()
    reset()
    Core.SetPetEnabled(false)
    local historyCount, rev = #Core.state.history, Core.state.rev
    T.assertFalse(Core.PetPercentageHeal(-15))
    T.assertFalse(Core.PetPercentageHeal(15))
    T.assertEq(Core.state.pet.hp, 50)
    T.assertEq(#Core.state.history, historyCount)
    T.assertEq(Core.state.rev, rev)
  end)

  T.it("rejects uninitialized state and missing or malformed pets", function()
    local state = Core.state
    Core.state = nil
    local playerResult, petResult = Core.PercentageHeal(15), Core.PetPercentageHeal(-15)
    Core.state = state
    T.assertFalse(playerResult); T.assertFalse(petResult)
    reset()
    local pet, rev, count = Core.state.pet, Core.state.rev, #Core.state.history
    for _, invalidPet in ipairs({ false, "pet", 1 }) do
      Core.state.pet = invalidPet
      local result = Core.PetPercentageHeal(15)
      Core.state.pet = pet
      T.assertFalse(result)
    end
    Core.state.pet = nil
    petResult = Core.PetPercentageHeal(-15)
    Core.state.pet = pet
    T.assertFalse(petResult)
    T.assertEq(Core.state.rev, rev); T.assertEq(#Core.state.history, count)
  end)

  T.it("rejects invalid HP states before adding history", function()
    local invalid = { math.huge, -math.huge, 0 / 0, 1e20, -1, "abc" }
    for _, field in ipairs({ "hp", "maxHp" }) do
      for _, value in ipairs(invalid) do
        reset()
        Core.state[field] = value
        Core.state.pet[field] = value
        local historyCount, rev = #Core.state.history, Core.state.rev
        T.assertFalse(Core.PercentageHeal(-15))
        T.assertFalse(Core.PetPercentageHeal(15))
        T.assertEq(#Core.state.history, historyCount)
        T.assertEq(Core.state.rev, rev)
      end
    end
    reset()
  end)

  T.it("undoes and redoes independent player and pet percentage changes", function()
    reset()
    T.assertTrue(Core.PercentageHeal(-15))
    Core.BreakUndoCoalesce()
    T.assertTrue(Core.PetPercentageHeal(15))
    T.assertEq(Core.state.hp, 70)
    T.assertEq(Core.state.pet.hp, 65)
    Core.Undo()
    T.assertEq(Core.state.pet.hp, 50)
    T.assertEq(Core.state.hp, 70)
    Core.Undo()
    T.assertEq(Core.state.hp, 100)
    Core.Redo()
    T.assertEq(Core.state.hp, 70)
    Core.Redo()
    T.assertEq(Core.state.pet.hp, 65)
  end)

  T.it("formats signed damage history and retains existing healing history", function()
    reset()
    Core.PetPercentageHeal(-15)
    local damage = History.FormatEntry(Core.state.history[1])
    T.assertTrue(damage:find("[Familier] Dégâts en pourcentage", 1, true) ~= nil)
    T.assertTrue(damage:find("Pourcentage -15%", 1, true) ~= nil)
    T.assertTrue(damage:find("Résultat 15", 1, true) ~= nil)
    Core.PercentageHeal(15)
    local heal = History.FormatEntry(Core.state.history[1])
    T.assertTrue(heal:find("Soin en pourcentage", 1, true) ~= nil)
    T.assertTrue(heal:find("Plafond bypassé", 1, true) ~= nil)
    T.assertTrue(History.FormatEntry({kind="DIVINE_HEAL",applied=10}):find("Soins divins", 1, true) ~= nil)
  end)
end)
