---@diagnostic disable: undefined-global
local T = _G.T
local ns = _G.NS
local Core = ns.Core
local Grimoire = ns.Grimoire
local Shared = ns.Shared
local Comm = ns.Comm
local GrimoireIcons = ns.GrimoireIcons

local function reset(classKey)
  Core.ResetToDefaults()
  if classKey then Core.SetClassKey(classKey) end
end

local function create(title, description, extra)
  extra = extra or {}
  extra.title = title
  extra.description = description
  local technique, err = Grimoire.CreateTechnique(extra)
  T.assertNotNil(technique, err)
  return technique
end

T.describe("Grimoire initialization and migration", function()
  T.it("creates a valid empty Grimoire by default", function()
    reset()
    T.assertEq(type(Core.state.grimoire), "table")
    T.assertEq(type(Core.state.grimoire.techniques), "table")
    T.assertEq(#Core.state.grimoire.techniques, 0)
    T.assertEq(Core.state.grimoire.nextTechniqueId, 1)
  end)

  T.it("normalizes malformed structures without throwing", function()
    local state = { classKey = "MAGE", grimoire = { techniques = "bad", nextTechniqueId = -8 } }
    local ok = pcall(Grimoire.EnsureState, state)
    T.assertTrue(ok)
    T.assertEq(#state.grimoire.techniques, 0)
    T.assertEq(state.grimoire.nextTechniqueId, 1)
  end)

  T.it("assigns unique stable IDs to legacy entries and is idempotent", function()
    local state = {
      classKey = "MAGE",
      grimoire = {
        nextTechniqueId = 1,
        techniques = {
          { title = "Sans ID", description = "A" },
          { id = 7, title = "Stable", description = "B" },
          { id = 7, title = "Doublon", description = "C" },
        },
      },
    }
    Grimoire.EnsureState(state)
    local a, b, c = state.grimoire.techniques[1], state.grimoire.techniques[2], state.grimoire.techniques[3]
    T.assertNeq(a.id, b.id)
    T.assertNeq(b.id, c.id)
    T.assertNeq(a.id, c.id)
    T.assertEq(b.id, 7)
    local ids = { a.id, b.id, c.id }
    local nextId = state.grimoire.nextTechniqueId
    Grimoire.EnsureState(state)
    for i = 1, 3 do T.assertEq(state.grimoire.techniques[i].id, ids[i]) end
    T.assertEq(state.grimoire.nextTechniqueId, nextId)
  end)

  T.it("preserves text and order while degrading invalid optional metadata", function()
    local state = {
      classKey = "MAGE",
      grimoire = { techniques = {
        { id = 2, title = "Deux", description = "Seconde", usesPerMission = 0, damageHealing = 0,
          cost = { classKey = "MAGE", resourceIdx = 99, amount = 4 }, icon = { name = {} } },
        { id = 1, title = "Un", description = "Première", usesPerMission = 3, damageHealing = 120 },
      } },
    }
    Grimoire.EnsureState(state)
    T.assertEq(state.grimoire.techniques[1].title, "Deux")
    T.assertEq(state.grimoire.techniques[2].title, "Un")
    T.assertNil(state.grimoire.techniques[1].usesPerMission)
    T.assertNil(state.grimoire.techniques[1].cost)
    T.assertNil(state.grimoire.techniques[1].icon)
    T.assertNil(state.grimoire.techniques[1].damageHealing)
    T.assertEq(state.grimoire.techniques[2].usesPerMission, 3)
    T.assertEq(state.grimoire.techniques[2].damageHealing, 120)
  end)

  T.it("retains a legacy icon name with a safe normalized fallback", function()
    local state = {
      classKey = "MAGE",
      grimoire = { techniques = {
        { title = "Icône", description = "", icon = { name = "LegacyIconName" } },
      } },
    }
    Grimoire.EnsureState(state)
    T.assertEq(state.grimoire.techniques[1].icon.name, "LegacyIconName")
    T.assertEq(state.grimoire.techniques[1].icon.type, "file")
    T.assertNil(state.grimoire.techniques[1].icon.file)
  end)

  T.it("Core_Init performs Grimoire migration idempotently", function()
    local db = ns.GetDB()
    db.state = {
      hp = 50, maxHp = 50, classKey = "MAGE", wounds = {}, pet = {}, history = {},
      grimoire = { techniques = { { title = "Héritage", description = "Texte" } } },
    }
    ns.Core_Init()
    local id = Core.state.grimoire.techniques[1].id
    ns.Core_Init()
    T.assertEq(Core.state.grimoire.techniques[1].id, id)
    T.assertEq(#Core.state.grimoire.techniques, 1)
    reset()
  end)
end)

T.describe("Grimoire CRUD and ordering", function()
  T.it("creates, reads and allocates stable increasing IDs", function()
    reset("MAGE")
    local a = create("Charge", "Fonce.")
    local b = create("Barrière", "Protège.")
    T.assertEq(#Grimoire.GetTechniques(), 2)
    T.assertTrue(b.id > a.id)
    T.assertEq(Grimoire.GetTechniqueById(a.id).title, "Charge")
  end)

  T.it("updates every authored field and can clear optionals", function()
    reset("MAGE")
    local a = create("Ancien", "Texte")
    local updated, err = Grimoire.UpdateTechnique(a.id, {
      title = "Nouveau", description = "Description",
      icon = { name = "INV_Misc_QuestionMark", type = "file", file = 134400 },
      cost = { classKey = "MAGE", resourceIdx = 1, amount = 3 },
      usesPerMission = 2,
      damageHealing = 120,
    })
    T.assertNotNil(updated, err)
    T.assertEq(updated.title, "Nouveau")
    T.assertEq(updated.description, "Description")
    T.assertEq(updated.icon.file, 134400)
    T.assertEq(updated.cost.classKey, "MAGE")
    T.assertEq(updated.cost.resourceIdx, 1)
    T.assertEq(updated.cost.amount, 3)
    T.assertEq(updated.usesPerMission, 2)
    T.assertEq(updated.damageHealing, 120)
    Grimoire.UpdateTechnique(a.id, {
      icon = { name = "AtlasIcon", type = "atlas", atlas = "some-atlas" },
    })
    T.assertEq(updated.icon.type, "atlas")
    T.assertEq(updated.icon.atlas, "some-atlas")
    T.assertNil(updated.icon.file)
    Grimoire.UpdateTechnique(a.id, {
      icon = false, cost = false, usesPerMission = false, damageHealing = false,
    })
    T.assertNil(updated.icon)
    T.assertNil(updated.cost)
    T.assertNil(updated.usesPerMission)
    T.assertNil(updated.damageHealing)
  end)

  T.it("an isolated editor draft does not mutate persisted state", function()
    reset("MAGE")
    local a = create("Persisté", "Original", {
      icon = { name = "A", type = "atlas", atlas = "some-atlas" },
      cost = { classKey = "MAGE", resourceIdx = 1, amount = 2 },
      damageHealing = 80,
    })
    local draft = Grimoire.CopyTechnique(a)
    draft.title = "Annulé"
    draft.icon.atlas = "changed"
    draft.cost.amount = 99
    draft.damageHealing = 999
    local persisted = Grimoire.GetTechniqueById(a.id)
    T.assertEq(persisted.title, "Persisté")
    T.assertEq(persisted.icon.atlas, "some-atlas")
    T.assertEq(persisted.cost.amount, 2)
    T.assertEq(persisted.damageHealing, 80)
  end)

  T.it("deletes exactly the requested stable ID", function()
    reset("MAGE")
    local a = create("A", "a")
    local b = create("B", "b")
    local c = create("C", "c")
    T.assertTrue(Grimoire.DeleteTechnique(b.id))
    local list = Grimoire.GetTechniques()
    T.assertEq(#list, 2)
    T.assertEq(list[1].id, a.id)
    T.assertEq(list[2].id, c.id)
  end)

  T.it("moves within bounds and preserves order across normalization", function()
    reset("MAGE")
    local a = create("A", "")
    local b = create("B", "")
    local c = create("C", "")
    T.assertFalse(Grimoire.MoveTechnique(a.id, -1))
    T.assertFalse(Grimoire.MoveTechnique(c.id, 1))
    T.assertTrue(Grimoire.MoveTechnique(c.id, -1))
    T.assertEq(Grimoire.GetTechniques()[2].id, c.id)
    T.assertEq(Grimoire.GetTechniques()[3].id, b.id)
    Grimoire.EnsureState(Core.state)
    T.assertEq(Grimoire.GetTechniques()[2].id, c.id)
    Grimoire.UpdateTechnique(c.id, { title = "C modifié" })
    T.assertEq(Grimoire.GetTechniques()[2].title, "C modifié")
    T.assertEq(Grimoire.GetTechniques()[3].id, b.id)
  end)

  T.it("undo restores nested Grimoire data without aliasing", function()
    reset("MAGE")
    local a = create("Avant", "Texte", {
      icon = { name = "old", type = "file", file = 1 },
      cost = { classKey = "MAGE", resourceIdx = 1, amount = 2 },
      damageHealing = 40,
    })
    Core.BreakUndoCoalesce()
    Grimoire.UpdateTechnique(a.id, {
      title = "Après",
      icon = { name = "new", type = "file", file = 2 },
      cost = { classKey = "MAGE", resourceIdx = 2, amount = 5 },
      damageHealing = 120,
    })
    Core.Undo()
    local restored = Grimoire.GetTechniqueById(a.id)
    T.assertEq(restored.title, "Avant")
    T.assertEq(restored.icon.file, 1)
    T.assertEq(restored.cost.resourceIdx, 1)
    T.assertEq(restored.cost.amount, 2)
    T.assertEq(restored.damageHealing, 40)
  end)
end)

T.describe("Grimoire resources and informational semantics", function()
  T.it("sources current-class resources from Shared and excludes pet authority", function()
    reset("MAGE")
    Core.SetPetEnabled(true)
    Core.SetPetAuthorityEnabled(true)
    local resources = Grimoire.GetAvailableCostResources()
    local shared = Shared.GetResProfile({ classKey = "MAGE" })
    T.assertEq(resources[1].label, shared[1].label)
    for i = 1, #resources do T.assertTrue(resources[i].idx <= 4) end
  end)

  T.it("accepts no cost and a valid current-class cost", function()
    reset("MAGE")
    T.assertTrue(Grimoire.ValidateCost(Core.state, nil))
    local ok = Grimoire.ValidateCost(Core.state, { classKey = "MAGE", resourceIdx = 1, amount = 3 })
    T.assertTrue(ok)
  end)

  T.it("does not reinterpret a stored cost after a class change", function()
    reset("MAGE")
    local a = create("Sort", "", { cost = { classKey = "MAGE", resourceIdx = 1, amount = 3 } })
    Core.SetClassKey("WARLOCK")
    T.assertEq(a.cost.classKey, "MAGE")
    T.assertEq(Grimoire.GetCostResource(a.cost.classKey, a.cost.resourceIdx).label, "Mana")
    local ok = Grimoire.ValidateCost(Core.state, a.cost)
    T.assertFalse(ok)
    local result = Grimoire.UpdateTechnique(a.id, { title = "Doit rechoisir" })
    T.assertNil(result, "editing a stale cost must require clearing or reselecting it")
    T.assertNotNil(Grimoire.UpdateTechnique(a.id, { title = "Rechoisi", cost = false }))
  end)

  T.it("cost and use limits never spend or decrement automatically", function()
    reset("MAGE")
    Core.SetHP(50, 50)
    Core.SetResIndex(1, 10, 20)
    local a = create("Info", "", {
      cost = { classKey = "MAGE", resourceIdx = 1, amount = 4 },
      usesPerMission = 2, damageHealing = 120,
    })
    local before = Core.state.res
    Core.DamageTrue(1)
    T.assertEq(Core.state.res, before)
    T.assertEq(a.usesPerMission, 2)
    T.assertEq(a.damageHealing, 120)
  end)

  T.it("rejects invalid finite uses and cost amounts", function()
    reset("MAGE")
    T.assertNil(Grimoire.CreateTechnique({ title = "X", usesPerMission = 0 }))
    T.assertNil(Grimoire.CreateTechnique({ title = "X", usesPerMission = 1.5 }))
    T.assertNil(Grimoire.CreateTechnique({ title = "X", damageHealing = 0 }))
    T.assertNil(Grimoire.CreateTechnique({ title = "X", damageHealing = 1.5 }))
    T.assertNil(Grimoire.CreateTechnique({
      title = "X", cost = { classKey = "MAGE", resourceIdx = 1, amount = -1 },
    }))
    local malformed = {
      classKey = "MAGE",
      grimoire = { techniques = { {
        title = "X", cost = { classKey = "NOT_A_CLASS", resourceIdx = 1, amount = 2 },
      } } },
    }
    Grimoire.EnsureState(malformed)
    T.assertNil(malformed.grimoire.techniques[1].cost)
  end)
end)

T.describe("Grimoire copy and communication boundary", function()
  T.it("formats the exact required representation", function()
    T.assertEq(
      Grimoire.FormatTechniqueForCopy({
        title = "Charge", description = "Fonce vers la cible.", damageHealing = 120,
      }),
      "[Charge : Fonce vers la cible.]"
    )
    T.assertEq(Grimoire.FormatTechniqueForCopy({ title = "Silence", description = "" }), "[Silence : ]")
  end)

  T.it("never includes Grimoire content in Comm payloads", function()
    reset("MAGE")
    create("SECRET_GRIMOIRE_TITLE", "SECRET_GRIMOIRE_DESCRIPTION")
    local serialized = Comm.SerializeState(Core.state)
    T.assertNotNil(serialized)
    T.assertNil(serialized:find("SECRET_GRIMOIRE_TITLE", 1, true))
    local out = Comm:DeserializeState("STATE_DATA", serialized, "Tester")
    T.assertNotNil(out)
    T.assertNil(out.grimoire)
    T.assertEq(out.hp, Core.state.hp)
  end)
end)

T.describe("Grimoire native icon catalogue", function()
  T.it("retains every theme and covers all retail classes with unique file icons", function()
    T.assertTrue(#GrimoireIcons >= 8)
    local total = 0
    local spellTotal = 0
    local seen = {}
    local categories = {}
    local classes = {}
    local prefix = "Interface\\Icons\\"
    for i = 1, #GrimoireIcons do
      local category = GrimoireIcons[i]
      T.assertTrue(type(category.category) == "string" and category.category ~= "")
      categories[category.category] = #category.icons
      T.assertTrue(#category.icons >= 8)
      for j = 1, #category.icons do
        local icon = category.icons[j]
        total = total + 1
        T.assertEq(icon.type, "file")
        T.assertEq(icon.file:sub(1, #prefix), prefix)
        T.assertFalse(seen[icon.name], "duplicate icon name: " .. tostring(icon.name))
        seen[icon.name] = true
        if icon.spellId then
          spellTotal = spellTotal + 1
          T.assertEq(icon.name, "spell:" .. tostring(icon.spellId))
          T.assertTrue(type(icon.classLabel) == "string" and icon.classLabel ~= "")
          classes[icon.classKey] = true
        end
      end
    end
    for _, name in ipairs({ "Combat", "Magie", "Défense", "Soins", "Mouvement", "Contrôle", "Utilitaire" }) do
      T.assertNotNil(categories[name], "missing retained category: " .. name)
    end
    T.assertTrue((categories["Potions & bandages"] or 0) >= 40)
    T.assertTrue(total >= 200)
    T.assertTrue(spellTotal >= 100)
    for _, classKey in ipairs({
      "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
      "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
    }) do
      T.assertTrue(classes[classKey], "missing class icons: " .. classKey)
    end
  end)
end)

T.describe("Grimoire UI builder smoke", function()
  T.it("builds empty and populated reusable list state against frame mocks", function()
    reset("MAGE")
    local oldUI = ns.UI
    local oldSpellAPI = rawget(_G, "C_Spell")
    local mock = _G.MOCKS
    ns.UI = {}

    local colors = {
      GOLD = { 1, 0.7, 0.1 }, GOLD_BRIGHT = { 1, 0.8, 0.2 }, GOLD_LIGHT = { 1, 0.9, 0.5 },
      GOLD_MUTED = { 0.5, 0.4, 0.2 }, BROWN_DEEP = { 0.08, 0.05, 0.02 },
      BROWN_DARK = { 0.14, 0.09, 0.04 }, TEXT_TITLE = { 1, 0.8, 0.3 },
      TEXT_BRIGHT = { 1, 0.95, 0.8 }, TEXT_NORMAL = { 0.9, 0.8, 0.7 },
      TEXT_LABEL = { 0.8, 0.7, 0.5 }, TEXT_DIM = { 0.6, 0.5, 0.4 },
      GOLD_DIM = { 0.8, 0.7, 0.4 },
    }
    local function buttonFactory(_, label)
      local button = mock.makeFrame()
      button._fs = mock.makeFrame()
      button._label = label
      return button
    end
    local function editFactory()
      local edit = mock.makeFrame()
      edit._wrap = mock.makeFrame()
      return edit
    end
    local ok, err = pcall(ns.UI_BuildGrimoireTab, {
      page = mock.makeFrame(), C = colors,
      TEX = { FLAT = "flat", BG_DARK = "dark" },
      Core = Core, Grimoire = Grimoire, GrimoireIcons = GrimoireIcons,
      mkButton = buttonFactory, mkEdit = editFactory,
      setButtonEnabled = function() end,
      CONTENT_W = 500,
    })
    T.assertTrue(ok, err)
    T.assertNotNil(ns.UI.refreshGrimoire)
    T.assertNotNil(ns.UI.openGrimoireEditor)
    T.assertNotNil(ns.UI.openGrimoireIconPicker)
    ns.UI.refreshGrimoire(Core.state)
    for i = 1, 6 do create("Technique " .. i, string.rep("Longue description ", 5)) end
    ns.UI.refreshGrimoire(Core.state)
    T.assertTrue(#ns.UI.grimoireRows >= 6)
    T.assertEq(ns.UI.grimoireRows[1].upBtn._label, "Haut")
    T.assertEq(ns.UI.grimoireRows[1].downBtn._label, "Bas")
    ns.UI.openGrimoireEditor(Grimoire.GetTechniques()[1].id)
    T.assertTrue(ns.UI.grimoireEditorOpen)
    local oldTRPBrowser = rawget(_G, "TRP3_IconBrowser")
    rawset(_G, "TRP3_IconBrowser", nil)
    rawset(_G, "C_Spell", {
      GetSpellTexture = function(spellId) return 1000000 + spellId end,
    })
    ns.UI.openGrimoireIconPicker(nil, function() end)
    T.assertNotNil(ns.UI.grimoireIconPicker)
    local expectedIconCount = 0
    for i = 1, #GrimoireIcons do
      expectedIconCount = expectedIconCount + #GrimoireIcons[i].icons
    end
    T.assertEq(#ns.UI.grimoireIconPicker.buttons, expectedIconCount)
    local resolvedSpellButton
    for i = 1, #ns.UI.grimoireIconPicker.buttons do
      if ns.UI.grimoireIconPicker.buttons[i]._iconInfo.spellId then
        resolvedSpellButton = ns.UI.grimoireIconPicker.buttons[i]
        break
      end
    end
    T.assertNotNil(resolvedSpellButton)
    T.assertEq(resolvedSpellButton._resolvedFile, 1000000 + resolvedSpellButton._iconInfo.spellId)
    rawset(_G, "C_Spell", oldSpellAPI)
    rawset(_G, "TRP3_IconBrowser", oldTRPBrowser)
    ns.UI = oldUI
    reset()
  end)
end)
