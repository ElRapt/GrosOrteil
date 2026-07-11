-- GrosOrteil/Core.lua
local _, ns = ...

local Core = {}
ns.Core = Core

local History = ns.History

local listeners = {}
local nextListenerId = 0

local function playFirstSoundKit(keys)
  if type(PlaySound) ~= "function" then return end
  if type(SOUNDKIT) ~= "table" then return end
  if type(keys) ~= "table" then return end
  for i = 1, #keys do
    local k = keys[i]
    local id = SOUNDKIT[k]
    if type(id) == "number" then
      pcall(PlaySound, id, "SFX")
      return
    end
  end
end

local function playSoundFileId(fileId)
  if type(fileId) ~= "number" then return false end
  if type(PlaySoundFile) ~= "function" then return false end
  local ok = pcall(PlaySoundFile, fileId, "SFX")
  return ok
end

local function sfxDamage()
  -- User-provided sound FileID
  if playSoundFileId(1305792) then return end
  playFirstSoundKit({ "SFX_GLUEGENERICBUTTON_PRESS", "IG_MAINMENU_OPTION_CHECKBOX_ON" })
end

local function sfxBlock()
  if playSoundFileId(1353843) then return end
  playFirstSoundKit({ "IG_MAINMENU_OPTION_CHECKBOX_ON" })
end

local function sfxMagicShield()
  if playSoundFileId(1708158) then return end
  playFirstSoundKit({ "IG_MAINMENU_OPTION_CHECKBOX_ON" })
end

local function sfxDodge()
  -- User-provided sound FileID (dodge/parry style)
  if playSoundFileId(567836) then return end
  playFirstSoundKit({ "IG_MAINMENU_OPTION_CHECKBOX_OFF", "IG_MAINMENU_OPTION_CHECKBOX_ON" })
end

local function sfxHealLight()
  -- User-provided sound FileID
  if playSoundFileId(1693996) then return end
  playFirstSoundKit({ "SPELL_HOLY_HEAL", "SPELL_HOLY_FLASH_HEAL", "IG_SPELLBOOK_OPEN" })
end

local function sfxLayOnHands()
  -- User-provided sound FileID
  if playSoundFileId(1955776) then return end
  playFirstSoundKit({ "SPELL_HOLY_LAY_ON_HANDS", "SPELL_HOLY_REDEMPTION", "RAID_WARNING" })
end

-- Floating combat text: the UI registers a handler that shows rising/fading
-- feedback above the HP bar. Kinds: "DAMAGE" (amount), "HEAL" (amount),
-- "BLOCK" (hit fully absorbed/mitigated), "DODGE". No-op until registered.
local combatTextHandler = nil

function Core.SetCombatTextHandler(fn)
  combatTextHandler = (type(fn) == "function") and fn or nil
end

local function emitCombatText(kind, amount)
  if combatTextHandler then pcall(combatTextHandler, kind, amount) end
end

-- Listener errors are non-fatal: notify() pcalls each callback so a single
-- bad listener can't break the chain. Errors flow through geterrorhandler
-- (Blizzard's default error display in WoW; mocked for offline tests),
-- unless a caller has installed a quiet handler via Core.SetListenerErrorHandler
-- (used by /grostest's listener-safety test to skip the popup).
local listenerErrorHandler = nil

local function reportError(err)
  if listenerErrorHandler then
    listenerErrorHandler(err)
    return
  end
  if type(geterrorhandler) == "function" then
    local h = geterrorhandler()
    if type(h) == "function" then
      h(err)
      return
    end
  end
  if type(print) == "function" then
    print("|cffff0000GrosOrteil error:|r " .. tostring(err))
  end
end

-- Override the listener-error reporter (or pass nil to restore default).
function Core.SetListenerErrorHandler(fn)
  listenerErrorHandler = (type(fn) == "function") and fn or nil
end

local function notify()
  local s = Core.state
  if not s then return end

  -- pairs() over a counter-keyed map: stable under unregister, no sparse-array footgun.
  for _, fn in pairs(listeners) do
    local ok, err = pcall(fn, s)
    if not ok then
      reportError(err)
    end
  end
end

function Core.OnChange(fn)
  if type(fn) ~= "function" then return end
  nextListenerId = nextListenerId + 1
  local id = nextListenerId
  listeners[id] = fn

  -- Important: Core_Init() may have already fired notify() before UI registers.
  -- Push the current cached state immediately so the UI is correct on /reload.
  if Core.state then
    local ok, err = pcall(fn, Core.state)
    if not ok then reportError(err) end
  end

  return function() listeners[id] = nil end
end

-- ── Undo / Redo ─────────────────────────────────────────────────────────
local undoStack = {}
local redoStack = {}
local MAX_UNDO = 50
local undoCoalesce = false
local prevSnapshot = nil

local SNAPSHOT_SCALARS = {
  "hp", "maxHp", "stabilise", "classKey",
  "res", "maxRes", "res2", "maxRes2", "res3", "maxRes3", "res4", "maxRes4",
  "auth", "maxAuth",
  "armor", "trueArmor", "tempArmor",
  "dodge", "tempBlock", "rev",
  "shamanPosture", "shamanPostureDmgBonus",
  -- Attack stats are mutated by the zone affixes and the insanity tier bonus;
  -- snapshotting them keeps an undone toggle consistent with its recorded
  -- applied deltas.
  "attaqueMelee", "attaqueDistance", "insanityAtkApplied",
}
local SNAPSHOT_PET_FIELDS = {
  "enabled", "name", "hp", "maxHp",
  "armor", "trueArmor", "dodge",
  "attaqueMelee", "attaqueDistance", "tempArmor",
  "authorityEnabled",
}
local SNAPSHOT_POSTURE_BASE = {
  "armor", "dodge", "maxHp",
  "maxRes", "maxRes2", "maxRes3", "maxRes4",
}

local function copyKeys(src, keys)
  local out = {}
  for i = 1, #keys do out[keys[i]] = src[keys[i]] end
  return out
end

local function copyAffixTables(src)
  local affixes, applied = nil, nil
  if type(src.affixes) == "table" then
    affixes = {}
    for k, v in pairs(src.affixes) do affixes[k] = v end
  end
  if type(src.affixApplied) == "table" then
    applied = {}
    for k, deltas in pairs(src.affixApplied) do
      local d = {}
      for f, v in pairs(deltas) do d[f] = v end
      applied[k] = d
    end
  end
  return affixes, applied
end

local function deepCopyState(s)
  local c = copyKeys(s, SNAPSHOT_SCALARS)
  c.affixes, c.affixApplied = copyAffixTables(s)
  local ms = s.magicShield
  c.magicShield = ms and { hp = ms.hp, maxHp = ms.maxHp, armor = ms.armor } or nil
  local mns = s.manaShield
  c.manaShield = mns and { active = mns.active, armor = mns.armor } or nil
  local spb = s.shamanPostureBase
  c.shamanPostureBase = spb and copyKeys(spb, SNAPSHOT_POSTURE_BASE) or nil
  c.wounds = { hit25 = s.wounds.hit25, hit10 = s.wounds.hit10 }
  local mt = s.meter
  c.meter = mt and { dmg = mt.dmg or 0, heal = mt.heal or 0 } or nil
  local p = s.pet or {}
  local pc = copyKeys(p, SNAPSHOT_PET_FIELDS)
  local pw = p.wounds or {}
  pc.wounds = { hit25 = pw.hit25, hit10 = pw.hit10 }
  local pms = p.magicShield
  pc.magicShield = pms and { hp = pms.hp, maxHp = pms.maxHp, armor = pms.armor } or { hp = 0, maxHp = 0, armor = 0 }
  c.pet = pc
  return c
end

local function restoreSnapshot(snap)
  local s = Core.state
  for i = 1, #SNAPSHOT_SCALARS do
    local k = SNAPSHOT_SCALARS[i]
    s[k] = snap[k]
  end
  if snap.magicShield then
    s.magicShield = s.magicShield or {}
    s.magicShield.hp    = snap.magicShield.hp    or 0
    s.magicShield.maxHp = snap.magicShield.maxHp or 0
    s.magicShield.armor = snap.magicShield.armor or 0
  else
    s.magicShield = { hp = 0, maxHp = 0, armor = 0 }
  end
  if snap.manaShield then
    s.manaShield = s.manaShield or {}
    s.manaShield.active = snap.manaShield.active and true or false
    s.manaShield.armor  = snap.manaShield.armor or 0
  else
    s.manaShield = { active = false, armor = 0 }
  end
  local spb = snap.shamanPostureBase
  s.shamanPostureBase = spb and copyKeys(spb, SNAPSHOT_POSTURE_BASE) or nil
  local affixes, affixApplied = copyAffixTables(snap)
  s.affixes      = affixes      or {}
  s.affixApplied = affixApplied or {}
  s.wounds.hit25 = snap.wounds.hit25
  s.wounds.hit10 = snap.wounds.hit10
  if snap.meter then
    s.meter = s.meter or {}
    s.meter.dmg  = snap.meter.dmg  or 0
    s.meter.heal = snap.meter.heal or 0
  else
    s.meter = { dmg = 0, heal = 0 }
  end
  local p = s.pet; local sp = snap.pet
  for i = 1, #SNAPSHOT_PET_FIELDS do
    local k = SNAPSHOT_PET_FIELDS[i]
    p[k] = sp[k]
  end
  p.wounds.hit25 = sp.wounds.hit25; p.wounds.hit10 = sp.wounds.hit10
  local spms = sp.magicShield
  p.magicShield = p.magicShield or {}
  p.magicShield.hp    = spms and spms.hp    or 0
  p.magicShield.maxHp = spms and spms.maxHp or 0
  p.magicShield.armor = spms and spms.armor or 0
  s.rev = (s.rev or 0) + 1
end

function Core.Undo()
  if #undoStack == 0 or not Core.state then return end
  redoStack[#redoStack + 1] = deepCopyState(Core.state)
  local snap = table.remove(undoStack)
  restoreSnapshot(snap)
  prevSnapshot = deepCopyState(Core.state)
  notify()
end

function Core.Redo()
  if #redoStack == 0 or not Core.state then return end
  undoStack[#undoStack + 1] = deepCopyState(Core.state)
  local snap = table.remove(redoStack)
  restoreSnapshot(snap)
  prevSnapshot = deepCopyState(Core.state)
  notify()
end

function Core.CanUndo() return #undoStack > 0 end
function Core.CanRedo() return #redoStack > 0 end
function Core.GetUndoDepth() return #redoStack end

-- Test/scripting helper: drop the in-frame coalesce flag so the next bump()
-- creates a fresh undo entry. C_Timer.After(0, ...) only fires on the next
-- frame, which never happens during synchronous /grostest execution; without
-- this escape hatch every test mutation merges into a single undo step.
function Core.BreakUndoCoalesce()
  undoCoalesce = false
end

-- bump() is called AFTER state is modified. We save the PREVIOUS
-- post-change snapshot as the undo target, then record the new
-- post-change snapshot for the next undo.
local function bump()
  if not Core.state then return end
  if prevSnapshot and not undoCoalesce then
    undoCoalesce = true
    undoStack[#undoStack + 1] = prevSnapshot
    if #undoStack > MAX_UNDO then table.remove(undoStack, 1) end
    for i = #redoStack, 1, -1 do redoStack[i] = nil end
    C_Timer.After(0, function() undoCoalesce = false end)
  end
  Core.state.rev = (Core.state.rev or 0) + 1
  prevSnapshot = deepCopyState(Core.state)
end

-- Forward declarations: defined later but referenced by setters.
local applyManaShieldActive
local deactivateShamanPosture
local reapplyClassAffixes

local function clampNumber(x, minv, maxv)
  if type(x) ~= "number" then return nil end
  if minv and x < minv then x = minv end
  if maxv and x > maxv then x = maxv end
  return x
end

local function trimString(v)
  if type(v) ~= "string" then return nil end
  v = v:gsub("^%s+", ""):gsub("%s+$", "")
  if v == "" then return nil end
  return v
end

local function ensureHistory(s)
  if History and History.EnsureState then
    History.EnsureState(s)
  else
    if not s then return end
    if type(s.history) ~= "table" then s.history = {} end
  end
end

local function pushHistory(entry)
  local s = Core.state
  if not s then return end
  if type(entry) ~= "table" then return end
  if History and History.Push then
    History.Push(s, entry)
  else
    ensureHistory(s)
    table.insert(s.history, 1, entry)
    while #s.history > 60 do table.remove(s.history) end
  end
end

local function getWoundCap(s)
  return ns.Shared.WoundCap(s and s.wounds)
end

local function woundsFromPct(p)
  if p <= 0.10 then return true, true end
  if p <= 0.25 then return true, false end
  return false, false
end

local function ensureWoundsTable(t)
  if type(t.wounds) ~= "table" then
    t.wounds = { hit25 = false, hit10 = false }
  end
end

-- sticky=true: only upgrades wound flags (never clears them)
local function applyWounds(t, sticky)
  ensureWoundsTable(t)
  if not t.maxHp or t.maxHp <= 0 then
    if not sticky then t.wounds.hit25 = false; t.wounds.hit10 = false end
    return
  end
  local p = (t.hp or 0) / t.maxHp
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  local hit25, hit10 = woundsFromPct(p)
  if sticky then
    if hit10 then t.wounds.hit10 = true; t.wounds.hit25 = true
    elseif hit25 then t.wounds.hit25 = true end
  else
    t.wounds.hit10 = hit10
    t.wounds.hit25 = hit25
  end
end

local function updateWoundsSticky(t) applyWounds(t, true) end
local function recomputeWounds(t)    applyWounds(t, false) end

local function clampHpToEffectiveMax(s)
  if not s then return end
  if type(s.hp) == "number" and s.hp < 0 then
    s.hp = 0
  end
  local baseMax = s.maxHp
  if type(baseMax) ~= "number" or baseMax <= 0 then return end
  if type(s.hp) == "number" and s.hp > baseMax then
    s.hp = baseMax
  end
end

local function clampToMax(s, valueKey, maxKey)
  local maxv = s[maxKey]
  local v = s[valueKey]
  if type(maxv) == "number" and type(v) == "number" and v > maxv then
    s[valueKey] = maxv
  end
end

local function ensurePetDefaults(pet)
  if type(pet) ~= "table" then pet = {} end
  if type(pet.enabled) ~= "boolean" then pet.enabled = false end
  if type(pet.name) ~= "string" or pet.name == "" then pet.name = "Familier" end
  if type(pet.hp) ~= "number" then pet.hp = 20 end
  if type(pet.maxHp) ~= "number" or pet.maxHp <= 0 then pet.maxHp = 20 end
  if pet.hp < 0 then pet.hp = 0 end
  if pet.hp > pet.maxHp then pet.hp = pet.maxHp end
  if type(pet.armor) ~= "number" or pet.armor < 0 then pet.armor = 0 end
  if type(pet.trueArmor) ~= "number" or pet.trueArmor < 0 then pet.trueArmor = 0 end
  if type(pet.dodge) ~= "number" or pet.dodge < 0 then pet.dodge = 0 end
  if type(pet.attaqueMelee) ~= "number" or pet.attaqueMelee < 0 then pet.attaqueMelee = 0 end
  if type(pet.attaqueDistance) ~= "number" or pet.attaqueDistance < 0 then pet.attaqueDistance = 0 end
  if type(pet.tempArmor) ~= "number" or pet.tempArmor < 0 then pet.tempArmor = 0 end
  -- migrate legacy flat tempMagicBlock to magicShield sub-table
  if type(pet.magicShield) ~= "table" then
    local legacy = tonumber(pet.tempMagicBlock) or 0
    pet.magicShield = { hp = legacy, maxHp = legacy, armor = 0 }
  else
    if type(pet.magicShield.hp)    ~= "number" then pet.magicShield.hp    = 0 end
    if type(pet.magicShield.maxHp) ~= "number" then pet.magicShield.maxHp = pet.magicShield.hp or 0 end
    if type(pet.magicShield.armor) ~= "number" then pet.magicShield.armor = 0 end
  end
  pet.tempMagicBlock = nil
  if type(pet.authorityEnabled) ~= "boolean" then pet.authorityEnabled = false end
  if type(pet.wounds) ~= "table" then pet.wounds = {} end
  pet.wounds.hit25 = not not pet.wounds.hit25
  pet.wounds.hit10 = not not pet.wounds.hit10
  return pet
end

local function ensurePet(s)
  if not s then return nil end
  s.pet = ensurePetDefaults(s.pet)
  return s.pet
end

local function getPetWoundCap(p)
  return ns.Shared.WoundCap(p and p.wounds)
end

local function updatePetWoundsSticky(p) if p then applyWounds(p, true)  end end
local function recomputePetWounds(p)    if p then applyWounds(p, false) end end

local WARLOCK_CORRUPTION_MAX  = 60
local MAGE_ARCANE_CHARGE_MAX  = 8

local function clampWarlockCorruption(s)
  if not s then return end
  s.maxRes2 = WARLOCK_CORRUPTION_MAX
  if type(s.res2) ~= "number" then s.res2 = 0 end
  if s.res2 < 0 then s.res2 = 0 elseif s.res2 > WARLOCK_CORRUPTION_MAX then s.res2 = WARLOCK_CORRUPTION_MAX end
end

local function clampMageArcaneCharge(s)
  if not s then return end
  s.maxRes2 = MAGE_ARCANE_CHARGE_MAX
  if type(s.res2) ~= "number" then s.res2 = 0 end
  if s.res2 < 0 then s.res2 = 0 elseif s.res2 > MAGE_ARCANE_CHARGE_MAX then s.res2 = MAGE_ARCANE_CHARGE_MAX end
end

-- Prêtre ombre : les paliers d'Insanité augmentent le jet d'attaque de base
-- (palier 2 : +10, palier 3 : +15). Le bonus est réellement appliqué aux deux
-- stats d'attaque ; s.insanityAtkApplied garde la part actuellement appliquée
-- pour n'ajuster que la différence quand l'Insanité ou la classe change.
local function insanityTierAtkBonus(s)
  if s.classKey ~= "SHADOWPRIEST" then return 0 end
  local ins = tonumber(s.res2) or 0
  if ins >= 18 then return 15 end
  if ins >= 11 then return 10 end
  return 0
end

local function updateInsanityAtkBonus(s)
  if not s then return end
  local target  = insanityTierAtkBonus(s)
  local applied = tonumber(s.insanityAtkApplied) or 0
  if target == applied then
    s.insanityAtkApplied = applied
    return
  end
  local delta = target - applied
  s.attaqueMelee    = math.max(0, (s.attaqueMelee or 0) + delta)
  s.attaqueDistance = math.max(0, (s.attaqueDistance or 0) + delta)
  s.insanityAtkApplied = target
end

local function effDmg(dmg, mitigation)
  dmg = math.max(0, dmg or 0)
  mitigation = math.max(0, mitigation or 0)
  local eff = dmg - mitigation
  if eff < 0 then eff = 0 end
  return eff
end

function ns.Core_Init()
  -- Reset undo/redo on (re-)init so ResetToDefaults can't replay pre-reset
  -- snapshots back into the freshly-defaulted state.
  for i = #undoStack, 1, -1 do undoStack[i] = nil end
  for i = #redoStack, 1, -1 do redoStack[i] = nil end
  prevSnapshot = nil
  undoCoalesce = false

  local db = (ns.GetDB and ns.GetDB()) or rawget(_G, "GrosOrteilDBPC") or rawget(_G, "GrosOrteilDB") or {}

  db.state = db.state or {
    hp = 50, maxHp = 50,
    classKey = nil,
    res = 20, maxRes = 20,
    res2 = 0, maxRes2 = 20,
    res3 = 0, maxRes3 = 20,
    res4 = 0, maxRes4 = 20,
    auth = 0, maxAuth = 5,
    armor = 0, trueArmor = 0, tempArmor = 0,
    dodge = 0,
    tempBlock = 0,
    magicShield = { hp = 0, maxHp = 0, armor = 0 },
    manaShield  = { active = false, armor = 25 },

    wounds = { hit25 = false, hit10 = false },

    pet = {
      enabled = false,
      name = "Familier",
      hp = 20,
      maxHp = 20,
      armor = 0,
      trueArmor = 0,
      dodge = 0,
      attaqueMelee = 0,
      attaqueDistance = 0,
      tempArmor = 0,
      magicShield = { hp = 0, maxHp = 0, armor = 0 },
      wounds = { hit25 = false, hit10 = false },
    },

    attaqueMelee = 0, attaqueDistance = 0,
    chance = 1, maxChance = 1,
    perception = 0,

    affixes = {}, affixApplied = {},

    history = {},

    -- Running totals for the raid-panel group meter (damage taken / healing
    -- received, character + pet combined). Kept inside the state so undo/redo
    -- snapshots roll them back together with the HP they explain.
    meter = { dmg = 0, heal = 0 },

    rev = 0,
  }

  -- Default class selection (used by UI to label/color the resource bar).
  if type(db.state.classKey) ~= "string" or db.state.classKey == "" then
    local fallback = "MAGE"
    if type(UnitClass) == "function" then
      local _, classFile = UnitClass("player")
      if type(classFile) == "string" and classFile ~= "" then
        fallback = classFile
      end
    end
    db.state.classKey = fallback
  end

  -- Migration depuis l'ancien champ woundCap si présent
  if db.state.wounds == nil then
    db.state.wounds = { hit25 = false, hit10 = false }
  end
  if db.state.woundCap ~= nil then
    local cap = db.state.woundCap
    if cap <= 0.25 then
      db.state.wounds.hit10 = true
      db.state.wounds.hit25 = true
    elseif cap <= 0.50 then
      db.state.wounds.hit25 = true
    end
    db.state.woundCap = nil
  end

  if db.state.dodge == nil then db.state.dodge = 0 end
  if db.state.tempArmor == nil then db.state.tempArmor = 0 end
  -- Migration: tempMagicBlock -> magicShield.hp
  if type(db.state.magicShield) ~= "table" then
    local legacy = tonumber(db.state.tempMagicBlock) or 0
    db.state.magicShield = { hp = legacy, maxHp = legacy, armor = 0 }
  else
    if type(db.state.magicShield.hp)    ~= "number" then db.state.magicShield.hp    = 0 end
    if type(db.state.magicShield.maxHp) ~= "number" then db.state.magicShield.maxHp = db.state.magicShield.hp or 0 end
    if type(db.state.magicShield.armor) ~= "number" then db.state.magicShield.armor = 0 end
  end
  db.state.tempMagicBlock = nil
  if type(db.state.manaShield) ~= "table" then
    db.state.manaShield = { active = false, armor = 25 }
  else
    db.state.manaShield.active = db.state.manaShield.active and true or false
    if type(db.state.manaShield.armor) ~= "number" then db.state.manaShield.armor = 25 end
  end
  -- Mana shield armor used to be folded into s.tempArmor on activation. The model
  -- now keeps it separate (added to mitigation at hit time). For old saves that
  -- were captured while the shield was active, peel the contribution back out
  -- once so the displayed tempArmor matches the user's intent.
  if not db.state._manaShieldArmorSplit then
    if db.state.manaShield.active then
      local contrib = math.max(0, db.state.manaShield.armor or 0)
      db.state.tempArmor = math.max(0, (db.state.tempArmor or 0) - contrib)
    end
    db.state._manaShieldArmorSplit = true
  end
  ensureHistory(db.state)
  ensurePet(db.state)

  -- Meter counters (added later): normalize old saves.
  if type(db.state.meter) ~= "table" then db.state.meter = {} end
  db.state.meter.dmg  = tonumber(db.state.meter.dmg)  or 0
  db.state.meter.heal = tonumber(db.state.meter.heal) or 0

  -- Ensure multi-resource fields exist (Warlock/Shadow Priest/Shaman).
  if db.state.res2 == nil then db.state.res2 = 0 end
  if db.state.maxRes2 == nil then db.state.maxRes2 = db.state.maxRes or 20 end
  if db.state.res3 == nil then db.state.res3 = 0 end
  if db.state.maxRes3 == nil then db.state.maxRes3 = db.state.maxRes or 20 end
  if db.state.res4 == nil then db.state.res4 = 0 end
  if db.state.maxRes4 == nil then db.state.maxRes4 = db.state.maxRes or 20 end
  if db.state.auth == nil then db.state.auth = 0 end
  if db.state.maxAuth == nil then db.state.maxAuth = 5 end
  if db.state.shamanPostureDmgBonus == nil then db.state.shamanPostureDmgBonus = 0 end
  -- Migration: drop legacy bonus HP fields (feature removed).
  db.state.tempHp = nil
  db.state.bonusHp = nil
  db.state.bonusHpMax = nil
  if db.state.attaqueMelee    == nil then db.state.attaqueMelee    = 0 end
  if db.state.attaqueDistance == nil then db.state.attaqueDistance = 0 end
  if db.state.chance          == nil then db.state.chance          = 1 end
  if db.state.maxChance       == nil then db.state.maxChance       = 1 end
  if db.state.perception      == nil then db.state.perception      = 0 end
  if db.state.regenParTour    == nil then db.state.regenParTour    = 1 end
  -- Affixes de zone (added later): ensure the maps exist on old saves.
  if type(db.state.affixes)      ~= "table" then db.state.affixes      = {} end
  if type(db.state.affixApplied) ~= "table" then db.state.affixApplied = {} end
  -- Bonus d'attaque des paliers d'Insanité : applique la part manquante sur
  -- les vieilles sauvegardes (insanityAtkApplied absent = rien d'appliqué).
  if type(db.state.insanityAtkApplied) ~= "number" then db.state.insanityAtkApplied = 0 end
  updateInsanityAtkBonus(db.state)
  -- stabilise is only valid when hp == 0; clear it on load if hp > 0.
  if (db.state.hp or 0) > 0 then db.state.stabilise = nil end
  clampHpToEffectiveMax(db.state)

  -- Popup settings defaults.
  db.settings = db.settings or {}
  if db.settings.popupOnTarget == nil then db.settings.popupOnTarget = true end

  Core.state = db.state
  updateWoundsSticky(Core.state)
  prevSnapshot = deepCopyState(Core.state)
  notify()
end

function Core.GetHistory()
  local s = Core.state
  if not s then return {} end
  ensureHistory(s)
  return s.history
end

function Core.ClearHistory()
  local s = Core.state
  if not s then return end
  if History and History.Clear then
    History.Clear(s)
  else
    s.history = {}
  end
  bump(); notify()
end

function Core.SetClassKey(classKey)
  local s = Core.state
  if not s then return end
  if type(classKey) ~= "string" or classKey == "" then return end
  if s.classKey == classKey then return end

  -- Leaving SHAMAN: tear down any active posture (stat bumps + posture bonuses)
  -- before changing class, otherwise the bumps leak into the new class.
  if s.classKey == "SHAMAN" then
    deactivateShamanPosture(s)
  end

  -- Leaving MAGE: drop any active mana shield so it can't trigger from non-MAGE state.
  if s.classKey == "MAGE" and s.manaShield and s.manaShield.active then
    applyManaShieldActive(s, false)
  end

  s.classKey = classKey

  -- Warlock: Corruption has a fixed max of 60.
  -- Mage: Arcane Charge has a fixed max of 8.
  -- Other classes: ensure res2 ≤ maxRes2. SHADOWPRIEST's insanity (res2)
  -- is intentionally allowed to exceed maxRes2; everywhere else, leaving
  -- a stale insanity value over the new class's cap is a bug.
  if classKey == "WARLOCK" then
    clampWarlockCorruption(s)
  elseif classKey == "MAGE" then
    clampMageArcaneCharge(s)
  elseif classKey ~= "SHADOWPRIEST" then
    clampToMax(s, "res2", "maxRes2")
  end

  -- Beledar Jour flips bonus/malus depending on class: recompute it in place.
  reapplyClassAffixes(s)
  -- Entering/leaving SHADOWPRIEST applies/removes the insanity attack bonus.
  updateInsanityAtkBonus(s)
  bump(); notify()
end

function Core.GetPet()
  local s = Core.state
  if not s then return nil end
  return ensurePet(s)
end

function Core.SetPetEnabled(enabled)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  local v = not not enabled
  if p.enabled == v then return end
  p.enabled = v
  bump(); notify()
end

function Core.SetPetAuthorityEnabled(enabled)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  local v = not not enabled
  if p.authorityEnabled == v then return end
  p.authorityEnabled = v
  bump(); notify()
end

function Core.SetPetName(name)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  local v = trimString(name)
  if not v then return end
  if p.name == v then return end
  p.name = v
  bump(); notify()
end

function Core.SetPetHP(hp, maxHp)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  hp = clampNumber(hp, 0, 1e9)
  maxHp = clampNumber(maxHp, 1, 1e9)
  if maxHp then p.maxHp = maxHp end
  if hp then p.hp = hp end
  if p.hp > p.maxHp then p.hp = p.maxHp end
  recomputePetWounds(p)
  bump(); notify()
end

function Core.SetPetArmor(armor, trueArmor)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  armor = clampNumber(armor, 0, 1e9)
  trueArmor = clampNumber(trueArmor, 0, 1e9)
  if armor then p.armor = armor end
  if trueArmor then p.trueArmor = trueArmor end
  bump(); notify()
end

function Core.SetPetDodge(v)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  v = clampNumber(v, 0, 1e9)
  if v then p.dodge = v end
  bump(); notify()
end

function Core.SetPetAttaque(melee, dist)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  melee = clampNumber(melee, 0, 1e9)
  dist  = clampNumber(dist,  0, 1e9)
  if melee then p.attaqueMelee    = melee end
  if dist  then p.attaqueDistance = dist  end
  bump(); notify()
end

function Core.SetPetTempArmor(v)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  v = clampNumber(v, 0, 1e9)
  if v then p.tempArmor = v end
  bump(); notify()
end

function Core.ResetPetTempArmor()
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  p.tempArmor = 0
  bump(); notify()
end

function Core.SetPetMagicShield(hp, maxHp, armor)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  p.magicShield = p.magicShield or { hp = 0, maxHp = 0, armor = 0 }
  hp    = clampNumber(hp,    0, 1e9)
  maxHp = clampNumber(maxHp, 0, 1e9)
  armor = clampNumber(armor, 0, 1e9)
  if maxHp then p.magicShield.maxHp = maxHp end
  if hp then
    local cap = p.magicShield.maxHp or 0
    if cap > 0 and hp > cap then hp = cap end
    p.magicShield.hp = hp
  end
  if armor then p.magicShield.armor = armor end
  bump(); notify()
end

function Core.ResetPetMagicShield()
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  p.magicShield = { hp = 0, maxHp = 0, armor = 0 }
  bump(); notify()
end

-- Setters
function Core.SetHP(hp, maxHp)
  local s = Core.state
  if not s then return end
  hp = clampNumber(hp, 0, 1e9)
  maxHp = clampNumber(maxHp, 1, 1e9)
  if maxHp then s.maxHp = maxHp end
  if hp then s.hp = hp end

  clampHpToEffectiveMax(s)
  recomputeWounds(s)
  if (s.hp or 0) > 0 then s.stabilise = nil end
  bump(); notify()
end

function Core.SetStabilise(v)
  local s = Core.state
  if not s then return end
  if (s.hp or 0) > 0 then return end
  local nv = v and true or false
  if (not not s.stabilise) == nv then return end
  s.stabilise = nv
  pushHistory({ kind = "STABILISE", on = nv })
  bump(); notify()
end

function Core.SetRes(res, maxRes)
  local s = Core.state
  if not s then return end
  res = clampNumber(res, -1e9, 1e9)
  maxRes = clampNumber(maxRes, 1, 1e9)
  if maxRes then s.maxRes = maxRes end
  if res then s.res = res end

  clampToMax(s, "res", "maxRes")

  bump(); notify()
end

local resKeysForIndex = ns.Shared.GetKeysForIdx

function Core.SetResIndex(i, res, maxRes)
  local s = Core.state
  if not s then return end
  local resKey, maxKey = resKeysForIndex(i)
  if not resKey then return end
  if not maxKey then return end

  -- Some resources have fixed maxima.
  local isWarlockCorruption = (i == 2 and s.classKey == "WARLOCK")
  local isShadowInsanity    = (i == 2 and s.classKey == "SHADOWPRIEST")
  local isMageArcaneCharge  = (i == 2 and s.classKey == "MAGE")

  if isWarlockCorruption then
    maxRes = WARLOCK_CORRUPTION_MAX
    res = clampNumber(res, 0, WARLOCK_CORRUPTION_MAX)
  elseif isMageArcaneCharge then
    maxRes = MAGE_ARCANE_CHARGE_MAX
    res = clampNumber(res, 0, MAGE_ARCANE_CHARGE_MAX)
  else
    local isShamanElemental = (s.classKey == "SHAMAN" and i >= 1 and i <= 4)
    res = clampNumber(res, -1e9, 1e9)
    maxRes = clampNumber(maxRes, isShamanElemental and 0 or 1, 1e9)
  end

  if maxRes then s[maxKey] = maxRes end
  if res then s[resKey] = res end
  if not isShadowInsanity then
    clampToMax(s, resKey, maxKey)
  end

  if isWarlockCorruption then
    clampWarlockCorruption(s)
  elseif isMageArcaneCharge then
    clampMageArcaneCharge(s)
  end
  if isShadowInsanity then updateInsanityAtkBonus(s) end
  bump(); notify()
end

function Core.AddResIndex(i, amount)
  local s = Core.state
  if not s then return end
  local resKey, maxKey = resKeysForIndex(i)
  if not resKey then return end

  local isWarlockCorruption = (i == 2 and s.classKey == "WARLOCK")
  local isShadowInsanity    = (i == 2 and s.classKey == "SHADOWPRIEST")
  local isMageArcaneCharge  = (i == 2 and s.classKey == "MAGE")
  amount = clampNumber(amount, -1e9, 1e9) or 0
  s[resKey] = (s[resKey] or 0) + amount

  if isWarlockCorruption then
    clampWarlockCorruption(s)
  elseif isMageArcaneCharge then
    clampMageArcaneCharge(s)
  elseif not isShadowInsanity then
    clampToMax(s, resKey, maxKey)
  end
  if isShadowInsanity then updateInsanityAtkBonus(s) end
  bump(); notify()
end

function Core.SetArmor(armor, trueArmor)
  local s = Core.state
  if not s then return end
  armor = clampNumber(armor, 0, 1e9)
  trueArmor = clampNumber(trueArmor, 0, 1e9)
  if armor then s.armor = armor end
  if trueArmor then s.trueArmor = trueArmor end
  bump(); notify()
end

function Core.SetTempArmor(v)
  local s = Core.state
  if not s then return end
  v = clampNumber(v, 0, 1e9)
  if v then s.tempArmor = v end
  bump(); notify()
end

function Core.ResetTempArmor()
  if not Core.state then return end
  Core.state.tempArmor = 0
  bump(); notify()
end

function Core.SetTempBlock(v)
  local s = Core.state
  if not s then return end
  v = clampNumber(v, 0, 1e9)
  if v then s.tempBlock = v end
  bump(); notify()
end

-- Bouclier magique générique
function Core.SetMagicShield(hp, maxHp, armor)
  local s = Core.state
  if not s then return end
  s.magicShield = s.magicShield or { hp = 0, maxHp = 0, armor = 0 }
  hp    = clampNumber(hp,    0, 1e9)
  maxHp = clampNumber(maxHp, 0, 1e9)
  armor = clampNumber(armor, 0, 1e9)
  if maxHp then s.magicShield.maxHp = maxHp end
  if hp then
    local cap = s.magicShield.maxHp or 0
    if cap > 0 and hp > cap then hp = cap end
    s.magicShield.hp = hp
  end
  if armor then s.magicShield.armor = armor end
  bump(); notify()
end

function Core.ResetMagicShield()
  local s = Core.state
  if not s then return end
  s.magicShield = { hp = 0, maxHp = 0, armor = 0 }
  bump(); notify()
end

-- Bouclier de mana (mage uniquement)

-- Interne : change l'état actif du bouclier de mana et synchronise tempArmor.
-- Mana shield is now treated as an additive armor contribution computed at hit time
-- (see manaShieldArmorContribution() in applyHit). Activating/deactivating no longer
-- mutates s.tempArmor, eliminating desync when the user edits tempArmor directly.
applyManaShieldActive = function(s, newActive)
  local mns = s.manaShield
  if not mns then return end
  mns.active = not not newActive
end

function Core.SetManaShieldArmor(v)
  local s = Core.state
  if not s then return end
  s.manaShield = s.manaShield or { active = false, armor = 25 }
  v = clampNumber(v, 0, 1e9)
  if v then s.manaShield.armor = v end
  bump(); notify()
end

function Core.ToggleManaShield()
  local s = Core.state
  if not s then return end
  s.manaShield = s.manaShield or { active = false, armor = 25 }
  if s.classKey ~= "MAGE" then
    applyManaShieldActive(s, false)
  else
    local wantActive = not s.manaShield.active
    -- Refuse activation sans mana.
    if wantActive and (s.res or 0) <= 0 then wantActive = false end
    applyManaShieldActive(s, wantActive)
  end
  bump(); notify()
end

function Core.SetManaShieldActive(active)
  local s = Core.state
  if not s then return end
  s.manaShield = s.manaShield or { active = false, armor = 25 }
  if s.classKey ~= "MAGE" then
    applyManaShieldActive(s, false)
  else
    local wantActive = active and true or false
    if wantActive and (s.res or 0) <= 0 then wantActive = false end
    applyManaShieldActive(s, wantActive)
  end
  bump(); notify()
end

function Core.SetDodge(v)
  local s = Core.state
  if not s then return end
  v = clampNumber(v, 0, 1e9)
  if v then s.dodge = v end
  bump(); notify()
end

function Core.ResetDodge()
  if not Core.state then return end
  Core.state.dodge = 0
  bump(); notify()
end

function Core.SetAttaque(melee, dist)
  local s = Core.state
  if not s then return end
  melee = clampNumber(melee, 0, 1e9)
  dist  = clampNumber(dist,  0, 1e9)
  if melee then s.attaqueMelee    = melee end
  if dist  then s.attaqueDistance = dist  end
  bump(); notify()
end

function Core.SetChance(cur, maxv)
  local s = Core.state
  if not s then return end
  cur  = clampNumber(cur,  0, 1e9)
  maxv = clampNumber(maxv, 0, 1e9)
  if maxv then s.maxChance = maxv end
  if cur then
    local cap = s.maxChance or 0
    if cap > 0 and cur > cap then cur = cap end
    s.chance = cur
  end
  bump(); notify()
end

function Core.SetPerception(v)
  local s = Core.state
  if not s then return end
  v = clampNumber(v, 0, 1e9)
  if v then s.perception = v end
  bump(); notify()
end

function Core.AddChance(delta)
  local s = Core.state
  if not s then return end
  delta = tonumber(delta) or 0
  local cur = (tonumber(s.chance) or 0) + delta
  local cap = tonumber(s.maxChance) or 0
  if cur < 0 then cur = 0 end
  if cap > 0 and cur > cap then cur = cap end
  s.chance = cur
  bump(); notify()
end

function Core.ResetToDefaults()
  local db = (ns.GetDB and ns.GetDB()) or rawget(_G, "GrosOrteilDBPC") or rawget(_G, "GrosOrteilDB")
  if not db then return end
  db.state = nil
  if ns.Core_Init then ns.Core_Init() end
end

function Core.ResetTempBlock()
  if not Core.state then return end
  Core.state.tempBlock = 0
  bump(); notify()
end

-- Helpers boucliers magiques

-- Absorbe `amount` via le bouclier magique et renvoie (reste, absorbéTotal).
-- L'armure du bouclier réduit les dégâts AVANT qu'ils n'entament les PV du bouclier.
-- L'armure du joueur s'applique ensuite uniquement sur le surplus qui dépasse le bouclier.
local function consumeMagicShield(s, amount)
  local ms = s.magicShield
  if not ms or amount <= 0 then return amount, 0 end
  local cur = math.max(0, ms.hp or 0)
  if cur <= 0 then return amount, 0 end

  -- 1. L'armure du bouclier réduit les dégâts entrants.
  local shieldArmor = math.max(0, ms.armor or 0)
  local afterArmor  = math.max(0, amount - shieldArmor)

  -- 2. Les PV du bouclier absorbent ce qui reste.
  local absorbed = math.min(cur, afterArmor)
  ms.hp = cur - absorbed

  if ms.hp <= 0 then
    ms.hp    = 0
    ms.armor = 0
    ms.maxHp = 0
  end

  local overflow    = afterArmor - absorbed
  local totalEaten  = amount - overflow   -- armor reduction + hp absorbed
  return overflow, totalEaten
end

-- Redirige les dégâts vers le mana (mage) ; renvoie le surplus à infliger aux PV
local function applyManaShield(s, dmg)
  if dmg <= 0 then return 0, 0, false end
  local mns = s.manaShield
  if not mns or not mns.active or s.classKey ~= "MAGE" then
    return dmg, 0, false
  end
  local mana = math.max(0, s.res or 0)
  if mana <= 0 then
    mns.active = false
    return dmg, 0, true
  end
  local drained = math.min(mana, dmg)
  s.res = mana - drained
  local remaining = dmg - drained
  local broke = false
  if (s.res or 0) <= 0 then
    s.res = 0
    applyManaShieldActive(s, false)
    broke = true
  end
  return remaining, drained, broke
end

-- opts: { armor=bool, isPet=bool, historyKind=str, subject=str|nil,
--         ignoreDodge=bool, direct=bool }
-- For player targets `t` is Core.state; for pet targets `t` is Core.state.pet.
-- Player-only features (Shaman posture, mana shield) are skipped when isPet=true.
-- ignoreDodge skips the dodge check; direct additionally bypasses block, magic
-- shield, mana shield and ALL armor (normal + invulnerable + temp) — straight to HP.
local function applyHit(s, t, rawAmount, opts)
  rawAmount = clampNumber(rawAmount, 0, 1e9) or 0

  if not opts.isPet and s.shamanPosture == "FEU" then
    rawAmount = rawAmount + (s.shamanPostureDmgBonus or 10)
  end

  local hpBefore    = t.hp or 0
  local maxBefore   = t.maxHp or 0
  local dodgeBefore = math.max(0, t.dodge or 0)
  local manaBefore  = (not opts.isPet) and (s.res or 0) or nil

  -- Dodge
  if not opts.ignoreDodge and rawAmount > 0 and dodgeBefore > 0 and rawAmount <= dodgeBefore then
    sfxDodge()
    pushHistory({
      kind      = opts.historyKind,
      subject   = opts.subject,
      input     = rawAmount,
      dodged    = true,
      dodge     = dodgeBefore,
      armor     = opts.armor and (t.armor or 0) or nil,
      trueArmor = t.trueArmor or 0,
      tempArmor = opts.armor and math.max(0, t.tempArmor or 0) or nil,
      hpBefore  = hpBefore,
      hpAfter   = hpBefore,
      maxHp     = maxBefore,
    })
    emitCombatText("DODGE")
    bump(); notify()
    return
  end

  local amount = rawAmount
  local absorbedBlock = 0
  local absorbedMagic

  -- Block (player DamageWithArmor only)
  if opts.armor and not opts.isPet then
    local block = math.max(0, s.tempBlock or 0)
    if block > 0 and amount > 0 then
      absorbedBlock = math.min(block, amount)
      s.tempBlock = block - absorbedBlock
      amount = amount - absorbedBlock
    end
  end

  -- Magic absorption
  if opts.direct then
    absorbedMagic = 0
  elseif opts.isPet then
    amount, absorbedMagic = consumeMagicShield(t, amount)
  else
    amount, absorbedMagic = consumeMagicShield(s, amount)
  end

  -- SFX
  if absorbedMagic > 0 then sfxMagicShield()
  elseif absorbedBlock > 0 then sfxBlock()
  elseif amount > 0 then sfxDamage() end

  -- Mitigation
  local mit
  if opts.direct then
    mit = 0
  elseif opts.isPet then
    if opts.armor then
      mit = math.max(0, (t.armor or 0) + (t.trueArmor or 0) + math.max(0, t.tempArmor or 0))
    else
      mit = math.max(0, (t.trueArmor or 0) + math.max(0, t.tempArmor or 0))
    end
  else
    local armorVal = opts.armor and ((t.armor or 0) + (t.trueArmor or 0) + math.max(0, t.tempArmor or 0))
                                 or ((t.trueArmor or 0) + math.max(0, t.tempArmor or 0))
    -- Active mana shield (Mage only) adds armor to mitigation. This used to be
    -- folded into tempArmor on (de)activation, which desynced when the user
    -- edited tempArmor manually.
    local mns = s.manaShield
    if mns and mns.active and s.classKey == "MAGE" then
      armorVal = armorVal + math.max(0, mns.armor or 0)
    end
    mit = armorVal
  end

  local afterAbsorb = amount
  local dmg = effDmg(amount, mit)

  local manaAbsorbed, manaBroke = 0, false
  if not opts.isPet and not opts.direct and dmg > 0 then
    dmg, manaAbsorbed, manaBroke = applyManaShield(s, dmg)
  end

  if dmg > 0 then
    if opts.isPet then
      t.hp = math.max(0, (t.hp or 0) - dmg)
    else
      t.hp = (t.hp or 0) - dmg
      clampHpToEffectiveMax(s)
    end
    -- Group-meter counter: effective damage taken (same value the history
    -- entry reports as "Résultat"). Pet hits count toward the owner.
    if type(s.meter) ~= "table" then s.meter = {} end
    s.meter.dmg = (s.meter.dmg or 0) + dmg
  end

  if dmg > 0 then
    emitCombatText("DAMAGE", dmg)
  elseif rawAmount > 0 then
    emitCombatText("BLOCK")
  end

  local entry = {
    kind          = opts.historyKind,
    subject       = opts.subject,
    input         = rawAmount,   -- original after posture bonus, before absorptions
    afterAbsorb   = afterAbsorb,
    absorbedBlock = absorbedBlock,
    absorbedMagic = absorbedMagic,
    dodge         = dodgeBefore,
    dodged        = false,
    armor         = opts.armor and (not opts.isPet) and (s.armor or 0) or nil,
    trueArmor     = t.trueArmor or 0,
    tempArmor     = opts.armor and (not opts.isPet) and math.max(0, t.tempArmor or 0) or nil,
    mitigation    = mit,
    damage        = dmg,
    hpBefore      = hpBefore,
    hpAfter       = t.hp or 0,
    maxHp         = maxBefore,
  }
  if not opts.isPet then
    -- input stays as rawAmount (the value the user typed, after Shaman-FEU bonus),
    -- matching pet history. The breakdown lines already report block/magic/mit.
    entry.manaAbsorbed = manaAbsorbed
    entry.manaBroke    = manaBroke
    entry.manaBefore   = manaBefore
    entry.manaAfter    = s.res or 0
  end
  pushHistory(entry)

  if opts.isPet then
    updatePetWoundsSticky(t)
  else
    updateWoundsSticky(s)
  end
  bump(); notify()
end

-- Actions
function Core.DamageWithArmor(amount)
  local s = Core.state
  if not s then return end
  applyHit(s, s, amount, { armor = true,  historyKind = "DAMAGE_ARMOR" })
end

function Core.DamageTrue(amount)
  local s = Core.state
  if not s then return end
  applyHit(s, s, amount, { armor = false, historyKind = "DAMAGE_TRUE" })
end

-- Direct damage: bypasses every defense (dodge, block, magic shield, mana
-- shield, and all armor including invulnerable) — applied straight to HP.
function Core.DamageDirect(amount)
  local s = Core.state
  if not s then return end
  applyHit(s, s, amount, { armor = false, ignoreDodge = true, direct = true, historyKind = "DAMAGE_DIRECT" })
end

-- opts: { kind=str, isPet=bool, gainRatio=number|nil, woundCapFn=fn|nil, subject=str|nil }
-- gainRatio: fixed fraction of maxHp (DivineHeal=0.75, Surgery=0.50); nil = normal heal with cap
local function applyHeal(s, t, amount, opts)
  amount = clampNumber(amount, 0, 1e9) or 0

  local hpBefore  = t.hp or 0
  local maxBefore = t.maxHp or 0

  local woundCapFn = opts.woundCapFn or (opts.isPet and getPetWoundCap or getWoundCap)
  local target = opts.isPet and t or s  -- woundCapFn expects the wounds-bearing table

  if opts.gainRatio then
    -- Bypass heal: fixed ratio, ignores wound cap
    sfxLayOnHands()
    local gain = maxBefore * opts.gainRatio
    t.hp = math.min((t.hp or 0) + gain, maxBefore)
    if not opts.isPet then clampHpToEffectiveMax(s) end
    pushHistory({ kind = opts.kind, subject = opts.subject, gain = gain,
                  hpBefore = hpBefore, hpAfter = t.hp or 0, maxHp = maxBefore })
    recomputeWounds(t)
    local applied = (t.hp or 0) - hpBefore
    if applied > 0 then emitCombatText("HEAL", applied) end
  else
    -- Normal heal: capped by wound threshold
    if amount > 0 then sfxHealLight() end
    local current  = t.hp or 0
    local proposed = current + amount
    local capMax   = maxBefore * woundCapFn(target)
    local healed   = math.min(proposed, capMax, maxBefore)
    t.hp = math.max(current, healed)
    if not opts.isPet then clampHpToEffectiveMax(s) end
    pushHistory({ kind = opts.kind, subject = opts.subject, input = amount,
                  current = current, proposed = proposed,
                  capMax = capMax, effMax = maxBefore,
                  applied = (t.hp or 0) - hpBefore,
                  hpBefore = hpBefore, hpAfter = t.hp or 0, maxHp = maxBefore,
                  woundCap = woundCapFn(target), healer = opts.healer })
    updateWoundsSticky(t)
    local appliedHeal = (t.hp or 0) - hpBefore
    if appliedHeal > 0 then emitCombatText("HEAL", appliedHeal) end
  end

  if (t.hp or 0) > 0 and not opts.isPet then s.stabilise = nil end
  bump(); notify()
end

function Core.Heal(amount)
  local s = Core.state
  if not s then return end
  applyHeal(s, s, amount, { kind = "HEAL" })
end

-- Same as Core.Heal but records who cast it (raid-panel heal accepted from a
-- remote healer). The history entry is credited to `healerName`.
function Core.HealFrom(amount, healerName)
  local s = Core.state
  if not s then return end
  applyHeal(s, s, amount, { kind = "HEAL", healer = healerName })
end

-- Group-meter "Soins" counter: heals GIVEN to others. Credited when a target
-- accepts a heal-others request and reports back the amount actually applied
-- (post wound-cap). Self, divine, surgery and pet heals deliberately don't
-- count — the meter measures help provided to the group.
function Core.CreditHealGiven(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, 0, 1e9) or 0
  if amount <= 0 then return end
  if type(s.meter) ~= "table" then s.meter = {} end
  s.meter.heal = (s.meter.heal or 0) + amount
  bump(); notify()
end

function Core.DivineHeal()
  local s = Core.state
  if not s then return end
  applyHeal(s, s, 0, { kind = "DIVINE_HEAL", gainRatio = 0.75 })
end

function Core.Surgery()
  local s = Core.state
  if not s then return end
  applyHeal(s, s, 0, { kind = "SURGERY", gainRatio = 0.50 })
end

function Core.AddRes(amount)
  Core.AddResIndex(1, amount)
end

deactivateShamanPosture = function(s)
  if not s or not s.shamanPosture then return end
  local base = s.shamanPostureBase or {}
  if s.shamanPosture == "FEU" then
    s.armor = base.armor or s.armor
    s.shamanPostureDmgBonus = 0
    s.maxRes4 = base.maxRes4 or s.maxRes4
    clampToMax(s, "res4", "maxRes4")
  elseif s.shamanPosture == "TERRE" then
    s.armor = math.max(0, (s.armor or 0) - 5)
    s.maxHp = math.max(1, (s.maxHp or 0) - 20)
    if (s.hp or 0) > s.maxHp then s.hp = s.maxHp end
    recomputeWounds(s)
    s.maxRes = base.maxRes or s.maxRes
    clampToMax(s, "res", "maxRes")
  elseif s.shamanPosture == "AIR" then
    s.dodge = math.max(0, (s.dodge or 0) - 15)
    s.maxRes2 = base.maxRes2 or s.maxRes2
    clampToMax(s, "res2", "maxRes2")
  elseif s.shamanPosture == "EAU" then
    s.maxRes3 = base.maxRes3 or s.maxRes3
    clampToMax(s, "res3", "maxRes3")
  end
  s.shamanPosture = nil
  s.shamanPostureBase = nil
end

function Core.SetShamanPosture(posture)
  local s = Core.state
  if not s or s.classKey ~= "SHAMAN" then return end
  -- Toggle off if same posture clicked again
  if s.shamanPosture == posture then posture = nil end

  deactivateShamanPosture(s)

  if not posture then bump(); notify(); return end

  -- Check requirement: ≥ 3 max points in the matching element
  -- (the cap matters, not the spent/available value)
  local reqKeys = { TERRE = "maxRes", AIR = "maxRes2", EAU = "maxRes3", FEU = "maxRes4" }
  local reqKey = reqKeys[posture]
  if not reqKey or (s[reqKey] or 0) < 3 then bump(); notify(); return end

  -- Save base stats before modifying them
  s.shamanPostureBase = {
    armor = s.armor, dodge = s.dodge, maxHp = s.maxHp,
    maxRes = s.maxRes, maxRes2 = s.maxRes2, maxRes3 = s.maxRes3, maxRes4 = s.maxRes4,
  }
  s.shamanPosture = posture

  if posture == "FEU" then
    s.armor = 0
    s.shamanPostureDmgBonus = 10
    s.maxRes4 = (s.maxRes4 or 0) + 4
    s.res4 = s.maxRes4
  elseif posture == "TERRE" then
    s.armor = (s.armor or 0) + 5
    s.maxHp = (s.maxHp or 0) + 20
    s.hp = (s.hp or 0) + 20
    clampHpToEffectiveMax(s)
    recomputeWounds(s)
    s.maxRes = (s.maxRes or 0) + 4
    s.res = s.maxRes
  elseif posture == "AIR" then
    s.dodge = (s.dodge or 0) + 15
    s.maxRes2 = (s.maxRes2 or 0) + 4
    s.res2 = s.maxRes2
  elseif posture == "EAU" then
    s.maxRes3 = (s.maxRes3 or 0) + 8
    s.res3 = s.maxRes3
  end

  bump(); notify()
end

-- ── Affixes de zone ──────────────────────────────────────────────────────
-- Toggles (Beledar Jour/Nuit, Cambuse) qui modifient la fiche tant qu'ils
-- sont actifs. Chaque activation enregistre dans s.affixApplied les deltas
-- réellement appliqués (après clamp à 0), pour que la désactivation restaure
-- exactement les valeurs d'origine même si un clamp a tronqué le malus.
local AFFIX_EXCLUSIVE = {
  BELEDAR_JOUR = "BELEDAR_NUIT",
  BELEDAR_NUIT = "BELEDAR_JOUR",
}

-- Deltas par champ pour un affixe, selon la classe courante. L'attaque couvre
-- CaC et distance. Beledar Jour devient un malus pour démoniste/prêtre ombre.
local function affixDeltas(s, key)
  if key == "BELEDAR_JOUR" then
    local sign = (s.classKey == "WARLOCK" or s.classKey == "SHADOWPRIEST") and -1 or 1
    return { attaqueMelee = 5 * sign, attaqueDistance = 5 * sign, dodge = 5 * sign, armor = 1 * sign }
  elseif key == "BELEDAR_NUIT" then
    return { attaqueMelee = -10, attaqueDistance = -10, dodge = -10, armor = -2 }
  elseif key == "CAMBUSE_ATTAQUE" then
    return { attaqueMelee = 10, attaqueDistance = 10, dodge = 5 }
  elseif key == "CAMBUSE_PV" then
    return { maxHp = 20, hp = 20 }
  end
  return nil
end

local function ensureAffixTables(s)
  if type(s.affixes)      ~= "table" then s.affixes      = {} end
  if type(s.affixApplied) ~= "table" then s.affixApplied = {} end
end

local function affixFieldMin(field)
  return (field == "maxHp") and 1 or 0
end

local function applyAffixField(s, applied, field, delta)
  local old = s[field] or 0
  local new = old + delta
  local minv = affixFieldMin(field)
  if new < minv then new = minv end
  s[field] = new
  applied[field] = new - old
end

local function applyAffix(s, key)
  local deltas = affixDeltas(s, key)
  if not deltas then return end
  local applied = {}
  -- maxHp d'abord, pour que le clamp des PV voie le nouveau plafond.
  if deltas.maxHp then applyAffixField(s, applied, "maxHp", deltas.maxHp) end
  for field, delta in pairs(deltas) do
    if field ~= "maxHp" then applyAffixField(s, applied, field, delta) end
  end
  if deltas.maxHp or deltas.hp then
    clampHpToEffectiveMax(s)
    recomputeWounds(s)
  end
  s.affixApplied[key] = applied
end

local function removeAffix(s, key)
  local applied = s.affixApplied[key]
  s.affixApplied[key] = nil
  if not applied then return end
  local touchedHp = false
  for field, delta in pairs(applied) do
    local new = (s[field] or 0) - delta
    local minv = affixFieldMin(field)
    if new < minv then new = minv end
    s[field] = new
    if field == "maxHp" or field == "hp" then touchedHp = true end
  end
  if touchedHp then
    clampHpToEffectiveMax(s)
    recomputeWounds(s)
  end
end

reapplyClassAffixes = function(s)
  if type(s.affixes) ~= "table" then return end
  if s.affixes.BELEDAR_JOUR then
    ensureAffixTables(s)
    removeAffix(s, "BELEDAR_JOUR")
    applyAffix(s, "BELEDAR_JOUR")
  end
end

function Core.IsAffixActive(key)
  local s = Core.state
  return (s and type(s.affixes) == "table" and s.affixes[key]) and true or false
end

function Core.ToggleAffix(key)
  local s = Core.state
  if not s then return end
  if type(key) ~= "string" or not affixDeltas(s, key) then return end
  ensureAffixTables(s)

  if s.affixes[key] then
    removeAffix(s, key)
    s.affixes[key] = nil
  else
    local other = AFFIX_EXCLUSIVE[key]
    if other and s.affixes[other] then
      removeAffix(s, other)
      s.affixes[other] = nil
    end
    applyAffix(s, key)
    s.affixes[key] = true
    -- Prêtre ombre : la nuit de Beledar nourrit l'Insanité, une fois par toggle.
    if key == "BELEDAR_NUIT" and s.classKey == "SHADOWPRIEST" then
      s.res2 = (s.res2 or 0) + 2
      updateInsanityAtkBonus(s)
    end
  end
  bump(); notify()
end

-- Restaure les PV au maximum.
function Core.RestoreHP()
  local s = Core.state
  if not s then return end
  local hpBefore = s.hp or 0
  local baseMax = math.max(1, s.maxHp or 1)
  s.hp = baseMax
  clampHpToEffectiveMax(s)
  recomputeWounds(s)
  s.stabilise = nil
  pushHistory({ kind = "RESTORE_HP",
                hpBefore = hpBefore, hpAfter = s.hp, maxHp = baseMax })
  bump(); notify()
end

function Core.SetRegenParTour(v)
  local s = Core.state
  if not s then return end
  s.regenParTour = math.floor(clampNumber(v, 0, 1e9) + 0.5)
  bump(); notify()
end

function Core.RegenParTour()
  local s = Core.state
  if not s then return end
  applyHeal(s, s, s.regenParTour or 0, { kind = "HEAL" })
end

-- Régénération quotidienne PV : +10 % du max de base, ignore les seuils de PV.
function Core.DailyRegenHP()
  local s = Core.state
  if not s then return end
  local hpBefore = s.hp or 0
  local baseMax = math.max(1, s.maxHp or 1)
  local gain    = math.floor(baseMax * 0.10 + 0.5)
  s.hp = math.min((s.hp or 0) + gain, baseMax)
  clampHpToEffectiveMax(s)
  recomputeWounds(s)
  if (s.hp or 0) > 0 then s.stabilise = nil end
  pushHistory({ kind = "DAILY_REGEN_HP",
                gain = gain, hpBefore = hpBefore, hpAfter = s.hp, maxHp = baseMax })
  bump(); notify()
end

-- Régénération quotidienne mystique : +20 % de la ressource principale (idx 1).
function Core.DailyRegenRes()
  local s = Core.state
  if not s then return end
  local resBefore = s.res or 0
  local maxRes = math.max(1, s.maxRes or 1)
  local gain   = math.floor(maxRes * 0.20 + 0.5)
  s.res = math.min((s.res or 0) + gain, maxRes)
  pushHistory({ kind = "DAILY_REGEN_RES",
                gain = gain, resBefore = resBefore, resAfter = s.res, maxRes = maxRes })
  bump(); notify()
end

function Core.PetDamageWithArmor(amount)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end
  applyHit(s, p, amount, { armor = true,  isPet = true, historyKind = "DAMAGE_ARMOR", subject = "PET" })
end

function Core.PetDamageTrue(amount)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end
  applyHit(s, p, amount, { armor = false, isPet = true, historyKind = "DAMAGE_TRUE",  subject = "PET" })
end

-- Direct damage on the pet: bypasses dodge, magic shield and all armor.
function Core.PetDamageDirect(amount)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end
  applyHit(s, p, amount, { armor = false, ignoreDodge = true, direct = true, isPet = true,
                           historyKind = "DAMAGE_DIRECT", subject = "PET" })
end

function Core.PetHeal(amount)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end
  applyHeal(s, p, amount, { kind = "HEAL",        isPet = true, subject = "PET" })
end

-- Pet counterpart of Core.HealFrom: a heal offered by another player and
-- accepted for the pet (raid-panel pet card handshake).
function Core.PetHealFrom(amount, healerName)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end
  applyHeal(s, p, amount, { kind = "HEAL", isPet = true, subject = "PET", healer = healerName })
end

function Core.PetDivineHeal()
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end
  applyHeal(s, p, 0, { kind = "DIVINE_HEAL", isPet = true, subject = "PET", gainRatio = 0.75 })
end

function Core.PetSurgery()
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end
  applyHeal(s, p, 0, { kind = "SURGERY",    isPet = true, subject = "PET", gainRatio = 0.50 })
end

function Core.PetRestoreHP()
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end
  local hpBefore = p.hp or 0
  local maxHp    = p.maxHp or 0
  p.hp = maxHp
  recomputePetWounds(p)
  pushHistory({ kind = "RESTORE_HP", subject = "PET",
                hpBefore = hpBefore, hpAfter = p.hp, maxHp = maxHp })
  bump(); notify()
end

function Core.PetDailyRegenHP()
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end
  local hpBefore = p.hp or 0
  local baseMax  = math.max(1, p.maxHp or 1)
  local gain     = math.floor(baseMax * 0.10 + 0.5)
  p.hp = math.min((p.hp or 0) + gain, p.maxHp)
  recomputePetWounds(p)
  pushHistory({ kind = "DAILY_REGEN_HP", subject = "PET",
                gain = gain, hpBefore = hpBefore, hpAfter = p.hp, maxHp = p.maxHp })
  bump(); notify()
end

function Core.PetDailyRegenRes()
  -- Pets have no primary resource; no-op kept for button symmetry.
end

-- ── Public API for companion addons ─────────────────────────────────────
-- The addon namespace (`ns`) is private to GrosOrteil, so sister addons
-- get this intentionally tiny global surface instead of a copy of
-- the resource system. Resources are identified by profile index (see
-- Shared.RES_PROFILES_BY_CLASS; SHAMAN: 1=Terre, 2=Air, 3=Eau, 4=Feu).
-- Note: AddResIndex does not floor at zero — callers must validate before
-- spending (Edith does).
local API = rawget(_G, "GrosOrteilAPI") or {}
_G.GrosOrteilAPI = API

API.version = 1

-- Returns current, max for resource index i, or nil before Core_Init.
function API.GetResIndex(i)
  local s = Core.state
  if not s then return nil end
  local resKey, maxKey = ns.Shared.GetKeysForIdx(i)
  if not resKey then return nil end
  return tonumber(s[resKey]) or 0, tonumber(s[maxKey]) or 0
end

function API.AddResIndex(i, amount)
  Core.AddResIndex(i, amount)
end

function API.GetClassKey()
  local s = Core.state
  return s and s.classKey or nil
end

-- Melee / ranged attack stats already live on the GrosOrteil sheet;
-- exposed so Edith edits the same values instead of duplicating them.
function API.GetAttaque()
  local s = Core.state
  if not s then return nil end
  return tonumber(s.attaqueMelee) or 0, tonumber(s.attaqueDistance) or 0
end

function API.SetAttaque(melee, dist)
  Core.SetAttaque(melee, dist)
end

function API.GetDodge()
  local s = Core.state
  if not s then return nil end
  return tonumber(s.dodge) or 0
end

function API.IsPetEnabled()
  local s = Core.state
  local p = s and s.pet
  return (p and p.enabled) and true or false
end

-- Subscribe to state changes. The callback receives no arguments (the
-- private state table is deliberately not handed out); it fires once
-- immediately when state is already initialized. Returns an unsubscribe
-- function.
function API.OnChange(fn)
  if type(fn) ~= "function" then return end
  return Core.OnChange(function() fn() end)
end
