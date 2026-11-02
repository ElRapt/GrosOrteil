local ns, T = NS, T
local Core, Affixes = ns.Core, ns.Affixes
local function reset()
  Core.ResetToDefaults()
  Core.SetPetEnabled(true)
end
local function definition(effects, duration)
  return { name = "Bénédiction", color = { r = .2, g = .5, b = .8 },
    duration = duration, effects = effects or {
      { stat = "armor", value = 5 }, { stat = "dodge", value = 10 },
      { stat = "regenParTour", value = 2 },
    } }
end
local function create(input, pet)
  Core.BreakUndoCoalesce()
  local key, err = Core.SaveCustomAffix(input or definition(), nil, pet)
  T.assertNotNil(key, err)
  return key
end
local function toggle(key, pet)
  Core.BreakUndoCoalesce()
  if pet then Core.TogglePetAffix(key) else Core.ToggleAffix(key) end
end
T.describe("Custom affix definitions and effects", function()
  T.it("creates an inactive multi-stat definition without changing built-ins or sharing input tables", function()
    reset()
    local input = definition()
    local key = create(input)
    input.effects[1].value = 500; input.color.r = 1
    local def = Affixes.Find(Core.state, key)
    T.assertEq(#def.effects, 3); T.assertEq(def.effects[1].value, 5)
    T.assertNear(def.color.r, .2); T.assertFalse(Core.IsAffixActive(key))
    T.assertEq(Core.state.armor, 0); T.assertEq(#Core.state.pet.customAffixes, 0)
    toggle(key)
    T.assertTrue(Core.IsAffixActive(key)); T.assertEq(Core.state.armor, 5)
    T.assertEq(Core.state.dodge, 10); T.assertEq(Core.state.regenParTour, 3)
    toggle(key)
    T.assertEq(Core.state.armor, 0); T.assertEq(Core.state.dodge, 0)
    T.assertEq(Core.state.regenParTour, 1)
    Core.ToggleAffix("CAMBUSE_ATTAQUE"); T.assertEq(Core.state.dodge, 10)
  end)
  T.it("rejects invalid definitions atomically", function()
    reset()
    local cases = {
      function(d) d.name = "  " end,
      function(d) d.name = "|cffff0000bad" end,
      function(d) d.name = string.rep("é", 81) end,
      function(d) d.effects = {} end,
      function(d) d.effects = { {stat="unknown", value=3} } end,
      function(d) d.effects[2].stat = "armor" end,
      function(d) d.effects[1].value = 0 end,
      function(d) d.effects[1].value = 0/0 end,
      function(d) d.effects[1].value = math.huge end,
      function(d) d.effects[1].value = "5" end,
      function(d) d.effects[1].value = -1e10 end,
      function(d) d.effects = {[2]={stat="armor",value=5}} end,
      function(d) d.color.r = 2 end,
      function(d) d.color = {} end,
      function(d) d.duration = 0 end,
      function(d) d.duration = 1.5 end,
      function(d) d.duration = 10000 end,
    }
    local rev = Core.state.rev
    for _, corrupt in ipairs(cases) do
      local input = definition(); corrupt(input)
      local key, err = Core.SaveCustomAffix(input)
      T.assertNil(key); T.assertNotNil(err)
      T.assertEq(#Core.state.customAffixes, 0); T.assertEq(Core.state.rev, rev)
    end
    T.assertNil(Core.SaveCustomAffix(definition(), "CAMBUSE_PV"))
    T.assertFalse(Core.DeleteCustomAffix("CAMBUSE_PV"))
  end)
  T.it("supports every player stat and fractional/signed values with reversible floors", function()
    reset(); Core.SetHP(40, 50); Core.SetArmor(3, 2)
    local effects = {}
    for _, stat in ipairs(Affixes.STATS) do
      effects[#effects+1] = { stat=stat.key, value=stat.key=="armor" and -10 or 2.5 }
    end
    local key = create(definition(effects)); toggle(key)
    T.assertEq(Core.state.armor, 0); T.assertEq(Core.state.hp, 42.5)
    T.assertEq(Core.state.maxHp, 52.5); T.assertEq(Core.state.perception, 2.5)
    T.assertEq(Core.state.trueArmor, 4.5); T.assertEq(Core.state.tempArmor, 2.5)
    toggle(key)
    T.assertEq(Core.state.hp, 40); T.assertEq(Core.state.maxHp, 50)
    T.assertEq(Core.state.armor, 3); T.assertEq(Core.state.trueArmor, 2)
    T.assertEq(Core.state.perception, 0); T.assertEq(Core.state.tempArmor, 0)
  end)
  T.it("applies distance bonuses to all ranges and serializes only effective stats", function()
    reset(); Core.SetAttaque(10, 12)
    local range = ns.Shared.RANGED_ATTACKS[1].key
    Core.SetRangedAttack(range, 25)
    local key = create(definition({{stat="attaqueDistance",value=8},{stat="attaqueMelee",value=4}}, 2))
    toggle(key); T.assertEq(Core.GetRangedAttack(Core.state, range), 33)
    local wire = ns.Comm:DeserializeState("STATE_DATA", ns.Comm.SerializeState(Core.state), "Other-Realm")
    T.assertEq(Core.GetRangedAttack(wire, range),33)
    T.assertNil(wire.customAffixes); T.assertNil(wire.affixApplied)
    Core.NextTurn(); Core.NextTurn()
    T.assertEq(Core.GetRangedAttack(Core.state,range),25); T.assertEq(Core.state.attaqueMelee,10)
  end)
  T.it("keeps distance debuffs independent of a capped general attack", function()
    reset(); Core.SetAttaque(0, 2)
    local range = ns.Shared.RANGED_ATTACKS[1].key
    Core.SetRangedAttack(range,30)
    local key=create(definition({{stat="attaqueDistance",value=-10}}))
    toggle(key); T.assertEq(Core.state.attaqueDistance,0)
    T.assertEq(Core.GetRangedAttack(Core.state,range),20)
    Core.SetRangedAttack(range,40); toggle(key)
    T.assertEq(Core.GetRangedAttack(Core.state,range),50)
    T.assertEq(Core.state.attaqueDistance,2)
  end)
  T.it("removes opposing capped bonuses in either order without manufacturing stats", function()
    for _, base in ipairs({5,1e9-5}) do
      for order=1,2 do
        reset(); Core.SetArmor(base,0)
        local positive=create(definition({{stat="armor",value=10}}))
        local negative=create(definition({{stat="armor",value=-30}}))
        toggle(positive); toggle(negative)
        toggle(order==1 and positive or negative)
        ns.Core_Init() -- adjusted applied deltas must survive reload too
        toggle(order==1 and negative or positive)
        T.assertEq(Core.state.armor,base)
      end
    end
  end)
  T.it("expires at exactly the selected duration and leaves unlimited definitions reusable", function()
    reset()
    local timed = create(definition(nil,2))
    local unlimited = create(definition({{stat="attaqueMelee",value=7}}))
    toggle(timed); toggle(unlimited)
    Core.NextTurn(); T.assertEq(Core.state.affixTurns[timed],1)
    Core.NextTurn(); T.assertFalse(Core.IsAffixActive(timed))
    T.assertEq(Core.state.armor,0); T.assertTrue(Core.IsAffixActive(unlimited))
    T.assertNotNil(Affixes.Find(Core.state,timed))
    toggle(timed); T.assertEq(Core.state.affixTurns[timed],2)
    toggle(timed); T.assertNil(Core.state.affixTurns[timed])
  end)
  T.it("advances custom and built-in timers together on both sheets, including a hidden pet", function()
    reset()
    local player=create(definition(nil,1)); local pet=create(definition(nil,2),true)
    toggle(player); toggle(pet,true); Core.ToggleAffix("ELIXIR_RESISTANCE")
    Core.SetPetEnabled(false); Core.NextTurn()
    T.assertEq(Core.state.armor,6); T.assertEq(Core.state.affixTurns.ELIXIR_RESISTANCE,2)
    T.assertEq(Core.state.pet.affixTurns[pet],1); T.assertEq(Core.state.pet.armor,5)
    Core.NextTurn(); T.assertEq(Core.state.pet.armor,0)
    T.assertNil(Core.SaveCustomAffix(definition({{stat="perception",value=1}}),nil,true))
    toggle(pet,true); T.assertNil(Core.state.pet.affixes[pet])
  end)
  T.it("preserves definitions, active deltas and remaining turns across repeated reloads", function()
    reset()
    local key=create(definition(nil,3)); toggle(key); Core.NextTurn()
    ns.Core_Init(); ns.Core_Init()
    T.assertEq(Core.state.armor,5); T.assertEq(Core.state.affixTurns[key],2)
    T.assertEq(Affixes.Find(Core.state,key).name,"Bénédiction")
    toggle(key); T.assertEq(Core.state.armor,0)
  end)
  T.it("removes corrupt custom definitions and expires invalid saved timers without reapplying", function()
    reset()
    local key=create(definition(nil,3)); toggle(key)
    Core.state.customAffixes[1].color.r=2
    ns.Core_Init()
    T.assertEq(#Core.state.customAffixes,0); T.assertEq(Core.state.armor,0)
    key=create(definition(nil,3)); toggle(key); Core.state.affixTurns[key]=math.huge
    ns.Core_Init(); T.assertFalse(Core.IsAffixActive(key)); T.assertEq(Core.state.armor,0)
  end)
  T.it("edits live names/colors without touching wounded HP, deltas or the countdown", function()
    reset()
    local input=definition({{stat="maxHp",value=25},{stat="armor",value=2}},3)
    local key=create(input); toggle(key); Core.DamageDirect(60); Core.NextTurn()
    local hp, armor, maxHp=Core.state.hp,Core.state.armor,Core.state.maxHp
    input.name="Vigueur"; input.color.r=.9
    T.assertEq(Core.SaveCustomAffix(input,key),key)
    T.assertEq(Core.state.hp,hp); T.assertEq(Core.state.maxHp,maxHp)
    T.assertEq(Core.state.armor,armor); T.assertEq(Core.state.affixTurns[key],2)
    input.effects[2].value=5
    local saved, err=Core.SaveCustomAffix(input,key)
    T.assertNil(saved); T.assertNotNil(err); T.assertEq(Core.state.armor,armor)
    T.assertEq(Affixes.Find(Core.state,key).effects[2].value,2)
    toggle(key); T.assertEq(Core.SaveCustomAffix(input,key),key)
    toggle(key); T.assertEq(Core.state.armor,5)
  end)
  T.it("deleting an active affix reverses every effect and undo restores its definition and timer", function()
    reset(); local key=create(definition(nil,3)); toggle(key); Core.NextTurn()
    Core.BreakUndoCoalesce(); T.assertTrue(Core.DeleteCustomAffix(key))
    T.assertEq(Core.state.armor,0); T.assertNil(Affixes.Find(Core.state,key))
    Core.Undo(); T.assertEq(Core.state.armor,5); T.assertEq(Core.state.affixTurns[key],2)
    T.assertNotNil(Affixes.Find(Core.state,key))
    Core.Redo(); T.assertEq(Core.state.armor,0); T.assertNil(Affixes.Find(Core.state,key))
  end)
  T.it("undoes authoring and expiry without sharing nested tables or reusing deleted IDs", function()
    reset(); local input=definition(nil,1); local key=create(input)
    Core.Undo(); T.assertNil(Affixes.Find(Core.state,key)); Core.Redo()
    input.effects[1].value=9; Core.BreakUndoCoalesce(); Core.SaveCustomAffix(input,key)
    Core.Undo(); T.assertEq(Affixes.Find(Core.state,key).effects[1].value,5)
    Core.Redo(); T.assertEq(Affixes.Find(Core.state,key).effects[1].value,9)
    toggle(key); Core.BreakUndoCoalesce(); Core.NextTurn()
    T.assertEq(Core.state.armor,0); Core.Undo(); T.assertEq(Core.state.armor,9)
    Core.Redo(); T.assertEq(Core.state.armor,0)
    local other=create(); Core.Undo()
    local replacement=create(); T.assertNeq(other,replacement)
    T.assertNil(Core.SaveCustomAffix(input,other))
  end)
  T.it("keeps shaman Fire's saved armor in step with custom expiry", function()
    reset(); Core.SetArmor(7,0); Core.SetShamanPosture("FEU")
    local key=create(definition({{stat="armor",value=3}},1)); toggle(key)
    Core.NextTurn(); Core.SetShamanPosture(nil)
    T.assertEq(Core.state.armor,7)
  end)
  T.it("shares pet affix stats with a linked active mount", function()
    reset()
    _G.IsMounted=function() return true end
    _G.C_MountJournal={GetMountIDs=function() return {1} end,
      GetMountInfoByID=function() return "Cheval",1,1,true end}
    ns.Mounts.Sync(); ns.Mounts.SetPetLink(true)
    local key=create(definition(nil,1),true); toggle(key,true)
    T.assertEq(ns.Mounts.GetActive().armor,5)
    Core.NextTurn(); T.assertEq(ns.Mounts.GetActive().armor,0)
    _G.IsMounted=function() return false end; ns.Mounts.Sync()
  end)
end)
