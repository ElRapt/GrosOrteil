-- GrosOrteil/Core.lua
local _, ns = ...

local Core = {}
ns.Core = Core

local History = ns.History

local listeners = {}

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

local function reportError(err)
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

local function notify()
  local s = Core.state
  if not s then return end

  for i = 1, #listeners do
    local fn = listeners[i]
    local ok, err = pcall(fn, s)
    if not ok then
      reportError(err)
    end
  end
end

function Core.OnChange(fn)
  if type(fn) ~= "function" then return end
  listeners[#listeners + 1] = fn

  -- Important: Core_Init() may have already fired notify() before UI registers.
  -- Push the current cached state immediately so the UI is correct on /reload.
  if Core.state then
    local ok, err = pcall(fn, Core.state)
    if not ok then reportError(err) end
  end
end

-- ── Undo / Redo ─────────────────────────────────────────────────────────
local undoStack = {}
local redoStack = {}
local MAX_UNDO = 50
local undoCoalesce = false
local prevSnapshot = nil

local function deepCopyState(s)
  local c = {}
  c.hp = s.hp; c.maxHp = s.maxHp
  c.bonusHp = s.bonusHp; c.bonusHpMax = s.bonusHpMax
  c.stabilise = s.stabilise
  c.classKey = s.classKey
  c.res = s.res; c.maxRes = s.maxRes
  c.res2 = s.res2; c.maxRes2 = s.maxRes2
  c.res3 = s.res3; c.maxRes3 = s.maxRes3
  c.res4 = s.res4; c.maxRes4 = s.maxRes4
  c.auth = s.auth; c.maxAuth = s.maxAuth
  c.armor = s.armor; c.trueArmor = s.trueArmor
  c.tempArmor = s.tempArmor
  c.dodge = s.dodge
  c.tempBlock = s.tempBlock
  local ms = s.magicShield
  c.magicShield = ms and {
    hp = ms.hp, maxHp = ms.maxHp, armor = ms.armor,
  } or nil
  local mns = s.manaShield
  c.manaShield = mns and {
    active = mns.active, armor = mns.armor,
  } or nil
  c.rev = s.rev
  c.shamanPosture = s.shamanPosture
  c.shamanPostureDmgBonus = s.shamanPostureDmgBonus
  local spb = s.shamanPostureBase
  c.shamanPostureBase = spb and {
    armor = spb.armor, dodge = spb.dodge, maxHp = spb.maxHp,
    maxRes = spb.maxRes, maxRes2 = spb.maxRes2, maxRes3 = spb.maxRes3, maxRes4 = spb.maxRes4,
  } or nil
  c.wounds = { hit25 = s.wounds.hit25, hit10 = s.wounds.hit10 }
  local p = s.pet or {}
  local pw = p.wounds or {}
  c.pet = {
    enabled = p.enabled, name = p.name,
    hp = p.hp, maxHp = p.maxHp,
    armor = p.armor, trueArmor = p.trueArmor,
    dodge = p.dodge, tempMagicBlock = p.tempMagicBlock,
    wounds = { hit25 = pw.hit25, hit10 = pw.hit10 },
  }
  return c
end

local function restoreSnapshot(snap)
  local s = Core.state
  s.hp = snap.hp; s.maxHp = snap.maxHp
  s.bonusHp = snap.bonusHp; s.bonusHpMax = snap.bonusHpMax
  s.stabilise = snap.stabilise
  s.classKey = snap.classKey
  s.res = snap.res; s.maxRes = snap.maxRes
  s.res2 = snap.res2; s.maxRes2 = snap.maxRes2
  s.res3 = snap.res3; s.maxRes3 = snap.maxRes3
  s.res4 = snap.res4; s.maxRes4 = snap.maxRes4
  s.auth = snap.auth; s.maxAuth = snap.maxAuth
  s.armor = snap.armor; s.trueArmor = snap.trueArmor
  s.tempArmor = snap.tempArmor or 0
  s.dodge = snap.dodge
  s.tempBlock = snap.tempBlock
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
  s.shamanPosture = snap.shamanPosture
  s.shamanPostureDmgBonus = snap.shamanPostureDmgBonus or 0
  local spb = snap.shamanPostureBase
  s.shamanPostureBase = spb and {
    armor = spb.armor, dodge = spb.dodge, maxHp = spb.maxHp,
    maxRes = spb.maxRes, maxRes2 = spb.maxRes2, maxRes3 = spb.maxRes3, maxRes4 = spb.maxRes4,
  } or nil
  s.wounds.hit25 = snap.wounds.hit25
  s.wounds.hit10 = snap.wounds.hit10
  local p = s.pet; local sp = snap.pet
  p.enabled = sp.enabled; p.name = sp.name
  p.hp = sp.hp; p.maxHp = sp.maxHp
  p.armor = sp.armor; p.trueArmor = sp.trueArmor
  p.dodge = sp.dodge; p.tempMagicBlock = sp.tempMagicBlock
  p.wounds.hit25 = sp.wounds.hit25; p.wounds.hit10 = sp.wounds.hit10
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

local function ensureWounds(s)
  if not s.wounds then
    s.wounds = { hit25 = false, hit10 = false }
  end
end

local function getWoundCap(s)
  local w = s and s.wounds
  if w and w.hit10 then return 0.25 end
  if w and w.hit25 then return 0.50 end
  return 1.0
end

local function woundsFromPct(p)
  if p < 0.10 then return true, true end
  if p < 0.25 then return true, false end
  return false, false
end

local function updateWoundsSticky(s)
  ensureWounds(s)

  if not s.maxHp or s.maxHp <= 0 then
    s.wounds.hit25 = false
    s.wounds.hit10 = false
    return
  end

  -- IMPORTANT: wounds thresholds are based on base max HP only.
  -- Bonus HP must not change the threshold values.
  local p = (s.hp or 0) / s.maxHp
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  local hit25, hit10 = woundsFromPct(p)
  if hit10 then
    s.wounds.hit10 = true
    s.wounds.hit25 = true
  elseif hit25 then
    s.wounds.hit25 = true
  end
end

local function recomputeWounds(s)
  ensureWounds(s)
  s.wounds.hit25 = false
  s.wounds.hit10 = false

  if not s.maxHp or s.maxHp <= 0 then
    return
  end

  local p = (s.hp or 0) / s.maxHp
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  local hit25, hit10 = woundsFromPct(p)
  s.wounds.hit10 = hit10
  s.wounds.hit25 = hit25
end

local function clampHpToEffectiveMax(s)
  if not s then return end
  if type(s.hp) == "number" and s.hp < 0 then
    s.hp = 0
  end
  local baseMax = s.maxHp
  if type(baseMax) ~= "number" or baseMax <= 0 then return end
  local bonus = math.max(0, s.bonusHp or 0)
  local effMax = baseMax + bonus
  if type(s.hp) == "number" and s.hp > effMax then
    s.hp = effMax
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
  if type(pet.tempMagicBlock) ~= "number" or pet.tempMagicBlock < 0 then pet.tempMagicBlock = 0 end
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
  local w = p and p.wounds
  if w and w.hit10 then return 0.25 end
  if w and w.hit25 then return 0.50 end
  return 1.0
end

local function updatePetWoundsSticky(p)
  if not p then return end
  if type(p.wounds) ~= "table" then
    p.wounds = { hit25 = false, hit10 = false }
  end

  if not p.maxHp or p.maxHp <= 0 then
    p.wounds.hit25 = false
    p.wounds.hit10 = false
    return
  end

  local pct = (p.hp or 0) / p.maxHp
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
  local hit25, hit10 = woundsFromPct(pct)
  if hit10 then
    p.wounds.hit10 = true
    p.wounds.hit25 = true
  elseif hit25 then
    p.wounds.hit25 = true
  end
end

local function recomputePetWounds(p)
  if not p then return end
  if type(p.wounds) ~= "table" then
    p.wounds = { hit25 = false, hit10 = false }
  else
    p.wounds.hit25 = false
    p.wounds.hit10 = false
  end

  if not p.maxHp or p.maxHp <= 0 then
    return
  end

  local pct = (p.hp or 0) / p.maxHp
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
  local hit25, hit10 = woundsFromPct(pct)
  p.wounds.hit10 = hit10
  p.wounds.hit25 = hit25
end

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

local function effDmg(dmg, mitigation)
  dmg = math.max(0, dmg or 0)
  mitigation = math.max(0, mitigation or 0)
  local eff = dmg - mitigation
  if eff < 0 then eff = 0 end
  return eff
end

function ns.Core_Init()
  local db = (ns.GetDB and ns.GetDB()) or rawget(_G, "GrosOrteilDBPC") or rawget(_G, "GrosOrteilDB") or {}

  db.state = db.state or {
    hp = 50, maxHp = 50,
    bonusHp = 0, bonusHpMax = 0,
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
      tempMagicBlock = 0,
      wounds = { hit25 = false, hit10 = false },
    },

    attaqueMelee = 0, attaqueDistance = 0,
    chance = 1, maxChance = 1,
    perception = 0,

    history = {},

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
  ensureHistory(db.state)
  ensurePet(db.state)

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
  -- Migration: tempHp -> bonusHp
  if db.state.bonusHp == nil then
    db.state.bonusHp = db.state.tempHp or 0
  end
  db.state.tempHp = nil
  -- Migration: bonusHpMax (new field; seed from current bonusHp if missing)
  if db.state.bonusHpMax == nil then
    db.state.bonusHpMax = db.state.bonusHp or 0
  end
  if db.state.attaqueMelee    == nil then db.state.attaqueMelee    = 0 end
  if db.state.attaqueDistance == nil then db.state.attaqueDistance = 0 end
  if db.state.chance          == nil then db.state.chance          = 1 end
  if db.state.maxChance       == nil then db.state.maxChance       = 1 end
  if db.state.perception      == nil then db.state.perception      = 0 end
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
  s.classKey = classKey

  -- Warlock: Corruption has a fixed max of 60.
  -- Mage: Arcane Charge has a fixed max of 8.
  if classKey == "WARLOCK" then
    clampWarlockCorruption(s)
  elseif classKey == "MAGE" then
    clampMageArcaneCharge(s)
  end
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

function Core.SetPetTempMagicBlock(v)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  v = clampNumber(v, 0, 1e9)
  if v then p.tempMagicBlock = v end
  bump(); notify()
end

function Core.ResetPetTempMagicBlock()
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  p.tempMagicBlock = 0
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
  s.stabilise = v and true or false
  bump(); notify()
end

-- Sets the configured bonus HP maximum. If bonus HP is currently active,
-- also updates the live pool to match.
function Core.SetBonusHP(v)
  local s = Core.state
  if not s then return end
  v = clampNumber(v, 0, 1e9) or 0
  s.bonusHpMax = v
  if (s.bonusHp or 0) > 0 then
    s.bonusHp = v
  end
  clampHpToEffectiveMax(s)
  recomputeWounds(s)
  bump(); notify()
end

-- Toggles bonus HP on (adds the pool and fills HP by that amount) or off (removes the pool).
function Core.ToggleBonusHP()
  local s = Core.state
  if not s then return end
  if (s.bonusHp or 0) > 0 then
    s.bonusHp = 0
  else
    local amount = (s.bonusHpMax or 0)
    s.bonusHp = amount
    s.hp = (s.hp or 0) + amount
  end
  clampHpToEffectiveMax(s)
  recomputeWounds(s)
  bump(); notify()
end

function Core.ResetBonusHP()
  if not Core.state then return end
  Core.state.bonusHp = 0
  clampHpToEffectiveMax(Core.state)
  recomputeWounds(Core.state)
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

local function resKeysForIndex(i)
  if i == 1 then return "res", "maxRes" end
  if i == 2 then return "res2", "maxRes2" end
  if i == 3 then return "res3", "maxRes3" end
  if i == 4 then return "res4", "maxRes4" end
  if i == 5 then return "auth", "maxAuth" end
  return nil, nil
end

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
local function applyManaShieldActive(s, newActive)
  local mns = s.manaShield
  if not mns then return end
  local wasActive = mns.active
  mns.active = newActive
  if newActive ~= wasActive then
    local a = mns.armor or 0
    if newActive then
      s.tempArmor = math.max(0, (s.tempArmor or 0) + a)
    else
      s.tempArmor = math.max(0, (s.tempArmor or 0) - a)
    end
  end
end

function Core.SetManaShieldArmor(v)
  local s = Core.state
  if not s then return end
  s.manaShield = s.manaShield or { active = false, armor = 25 }
  v = clampNumber(v, 0, 1e9)
  if v then
    if s.manaShield.active then
      local oldArmor = s.manaShield.armor or 0
      s.manaShield.armor = v
      s.tempArmor = math.max(0, (s.tempArmor or 0) - oldArmor + v)
    else
      s.manaShield.armor = v
    end
  end
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

-- Actions
function Core.DamageWithArmor(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, 0, 1e9) or 0

  if s.shamanPosture == "FEU" then
    amount = amount + (s.shamanPostureDmgBonus or 10)
  end

  local hpBefore        = (s.hp or 0)
  local baseMaxBefore   = (s.maxHp or 0)
  local bonusBefore     = math.max(0, s.bonusHp or 0)
  local armorBefore     = (s.armor or 0)
  local trueArmorBefore = (s.trueArmor or 0)
  local tempArmorBefore = math.max(0, s.tempArmor or 0)
  local dodgeBefore     = math.max(0, s.dodge or 0)
  local manaBefore      = (s.res or 0)

  -- Esquive : si les dégâts sont <= au seuil, ils sont entièrement ignorés.
  if amount > 0 and dodgeBefore > 0 and amount <= dodgeBefore then
    sfxDodge()
    pushHistory({
      kind = "DAMAGE_ARMOR",
      input = amount,
      dodged = true,
      dodge = dodgeBefore,
      armor = armorBefore,
      trueArmor = trueArmorBefore,
      tempArmor = tempArmorBefore,
      hpBefore = hpBefore,
      hpAfter = hpBefore,
      maxHp = baseMaxBefore,
      bonusHp = bonusBefore,
    })
    bump(); notify()
    return
  end

  local absorbedBlock = 0

  local block = math.max(0, s.tempBlock or 0)
  if block > 0 and amount > 0 then
    absorbedBlock = math.min(block, amount)
    s.tempBlock = block - absorbedBlock
    amount = amount - absorbedBlock
  end

  -- Bouclier magique (PV) : absorbe avant l'application de la mitigation.
  local absorbedMagic
  amount, absorbedMagic = consumeMagicShield(s, amount)

  -- SFX (une seule par "coup") : magic > block > damage
  if absorbedMagic > 0 then
    sfxMagicShield()
  elseif absorbedBlock > 0 then
    sfxBlock()
  elseif amount > 0 then
    sfxDamage()
  end

  local mit = armorBefore + trueArmorBefore + tempArmorBefore

  local afterAbsorb = amount
  local dmg = effDmg(amount, mit)

  local manaAbsorbed, manaBroke = 0, false
  if dmg > 0 then
    dmg, manaAbsorbed, manaBroke = applyManaShield(s, dmg)
  end
  if dmg > 0 then
    s.hp = (s.hp or 0) - dmg
  end
  clampHpToEffectiveMax(s)

  pushHistory({
    kind = "DAMAGE_ARMOR",
    input = amount + absorbedBlock + absorbedMagic,
    afterAbsorb = afterAbsorb,
    absorbedBlock = absorbedBlock,
    absorbedMagic = absorbedMagic,
    manaAbsorbed = manaAbsorbed,
    manaBroke = manaBroke,
    manaBefore = manaBefore,
    manaAfter = (s.res or 0),
    dodge = dodgeBefore,
    dodged = false,
    armor = armorBefore,
    trueArmor = trueArmorBefore,
    tempArmor = tempArmorBefore,
    mitigation = mit,
    damage = dmg,
    hpBefore = hpBefore,
    hpAfter = (s.hp or 0),
    maxHp = baseMaxBefore,
    bonusHp = bonusBefore,
  })

  updateWoundsSticky(s)
  bump(); notify()
end

function Core.DamageTrue(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, 0, 1e9) or 0

  if s.shamanPosture == "FEU" then
    amount = amount + (s.shamanPostureDmgBonus or 10)
  end

  local hpBefore        = (s.hp or 0)
  local baseMaxBefore   = (s.maxHp or 0)
  local bonusBefore     = math.max(0, s.bonusHp or 0)
  local trueArmorBefore = (s.trueArmor or 0)
  local tempArmorBefore = math.max(0, s.tempArmor or 0)
  local dodgeBefore     = math.max(0, s.dodge or 0)
  local manaBefore      = (s.res or 0)

  -- Esquive : s'applique aussi aux dégâts bruts.
  if amount > 0 and dodgeBefore > 0 and amount <= dodgeBefore then
    sfxDodge()
    pushHistory({
      kind = "DAMAGE_TRUE",
      input = amount,
      dodged = true,
      dodge = dodgeBefore,
      trueArmor = trueArmorBefore,
      tempArmor = tempArmorBefore,
      hpBefore = hpBefore,
      hpAfter = hpBefore,
      maxHp = baseMaxBefore,
      bonusHp = bonusBefore,
    })
    bump(); notify()
    return
  end

  -- Bouclier magique (PV) : s'applique aussi aux dégâts bruts.
  local absorbedMagic
  amount, absorbedMagic = consumeMagicShield(s, amount)

  if absorbedMagic > 0 then
    sfxMagicShield()
  elseif amount > 0 then
    sfxDamage()
  end

  local mit = trueArmorBefore + tempArmorBefore

  local afterAbsorb = amount
  local dmg = effDmg(amount, mit)

  local manaAbsorbed, manaBroke = 0, false
  if dmg > 0 then
    dmg, manaAbsorbed, manaBroke = applyManaShield(s, dmg)
  end
  if dmg > 0 then
    s.hp = (s.hp or 0) - dmg
  end
  clampHpToEffectiveMax(s)

  pushHistory({
    kind = "DAMAGE_TRUE",
    input = amount + absorbedMagic,
    afterAbsorb = afterAbsorb,
    absorbedMagic = absorbedMagic,
    manaAbsorbed = manaAbsorbed,
    manaBroke = manaBroke,
    manaBefore = manaBefore,
    manaAfter = (s.res or 0),
    dodge = dodgeBefore,
    dodged = false,
    trueArmor = trueArmorBefore,
    tempArmor = tempArmorBefore,
    mitigation = mit,
    damage = dmg,
    hpBefore = hpBefore,
    hpAfter = (s.hp or 0),
    maxHp = baseMaxBefore,
    bonusHp = bonusBefore,
  })

  updateWoundsSticky(s)
  bump(); notify()
end

function Core.Heal(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, 0, 1e9) or 0

  local hpBefore = (s.hp or 0)
  local baseMaxBefore = (s.maxHp or 0)
  local bonusBefore = math.max(0, s.bonusHp or 0)

  if amount > 0 then sfxHealLight() end

  local current = (s.hp or 0)
  local proposed = current + amount

  -- Cap selon l'état courant (seuils dynamiques)
  local baseMax = (s.maxHp or 0)
  local bonus = math.max(0, s.bonusHp or 0)
  -- Wound cap is based on base max HP only; bonus HP does not extend the threshold.
  local capMax = (baseMax * getWoundCap(s))
  local effMax = baseMax + bonus

  -- Soins normaux : ne dépassent pas le cap (s'il existe)
  -- Never reduce HP if current HP is already above the cap.
  local healed = math.min(proposed, capMax, effMax)
  s.hp = math.max(current, healed)

  clampHpToEffectiveMax(s)

  pushHistory({
    kind = "HEAL",
    input = amount,
    current = current,
    proposed = proposed,
    capMax = capMax,
    effMax = effMax,
    applied = (s.hp or 0) - hpBefore,
    hpBefore = hpBefore,
    hpAfter = (s.hp or 0),
    maxHp = baseMaxBefore,
    bonusHp = bonusBefore,
    woundCap = getWoundCap(s),
  })

  -- IMPORTANT: les soins normaux ne lèvent jamais un seuil
  updateWoundsSticky(s)
  if (s.hp or 0) > 0 then s.stabilise = nil end
  bump(); notify()
end

function Core.DivineHeal()
  local s = Core.state
  if not s then return end

  local hpBefore = (s.hp or 0)
  local baseMaxBefore = (s.maxHp or 0)
  local bonusBefore = math.max(0, s.bonusHp or 0)

  sfxLayOnHands()
  -- Bypass plafond : +75% du total (pas "fixé" à 75%)
  local baseMax = (s.maxHp or 0)
  local bonus = math.max(0, s.bonusHp or 0)
  local maxHp = baseMax + bonus
  local current = (s.hp or 0)
  local gain = (baseMax * 0.75)
  s.hp = math.min(current + gain, maxHp)
  clampHpToEffectiveMax(s)

  pushHistory({
    kind = "DIVINE_HEAL",
    gain = gain,
    hpBefore = hpBefore,
    hpAfter = (s.hp or 0),
    maxHp = baseMaxBefore,
    bonusHp = bonusBefore,
  })

  -- DivineHeal est un bypass : on recalcule les seuils depuis l'état actuel
  recomputeWounds(s)
  if (s.hp or 0) > 0 then s.stabilise = nil end
  bump(); notify()
end

function Core.Surgery()
  local s = Core.state
  if not s then return end

  local hpBefore = (s.hp or 0)
  local baseMaxBefore = (s.maxHp or 0)
  local bonusBefore = math.max(0, s.bonusHp or 0)

  sfxLayOnHands()
  -- Bypass plafond : +50% du total
  local baseMax = (s.maxHp or 0)
  local bonus = math.max(0, s.bonusHp or 0)
  local maxHp = baseMax + bonus
  local current = (s.hp or 0)
  local gain = (baseMax * 0.50)
  s.hp = math.min(current + gain, maxHp)
  clampHpToEffectiveMax(s)

  pushHistory({
    kind = "SURGERY",
    gain = gain,
    hpBefore = hpBefore,
    hpAfter = (s.hp or 0),
    maxHp = baseMaxBefore,
    bonusHp = bonusBefore,
  })

  recomputeWounds(s)
  if (s.hp or 0) > 0 then s.stabilise = nil end
  bump(); notify()
end

function Core.AddRes(amount)
  Core.AddResIndex(1, amount)
end

function Core.SetShamanPosture(posture)
  local s = Core.state
  if not s or s.classKey ~= "SHAMAN" then return end
  -- Toggle off if same posture clicked again
  if s.shamanPosture == posture then posture = nil end

  -- Deactivate current posture first (restore base stats)
  if s.shamanPosture then
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

  if not posture then bump(); notify(); return end

  -- Check requirement: ≥ 3 points in the matching element
  local reqKeys = { TERRE = "res", AIR = "res2", EAU = "res3", FEU = "res4" }
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

-- Restaure les PV au maximum (PV de base + bonus actif).
function Core.RestoreHP()
  local s = Core.state
  if not s then return end
  local bonus  = math.max(0, s.bonusHp or 0)
  local baseMax = math.max(1, s.maxHp or 1)
  s.hp = baseMax + bonus
  clampHpToEffectiveMax(s)
  recomputeWounds(s)
  s.stabilise = nil
  bump(); notify()
end

-- Régénération quotidienne PV : +10 % du max de base, ignore les seuils de blessure.
function Core.DailyRegenHP()
  local s = Core.state
  if not s then return end
  local bonus   = math.max(0, s.bonusHp or 0)
  local baseMax = math.max(1, s.maxHp or 1)
  local effMax  = baseMax + bonus
  local gain    = math.floor(baseMax * 0.10 + 0.5)
  s.hp = math.min((s.hp or 0) + gain, effMax)
  clampHpToEffectiveMax(s)
  recomputeWounds(s)
  if (s.hp or 0) > 0 then s.stabilise = nil end
  bump(); notify()
end

-- Régénération quotidienne mystique : +20 % de la ressource principale (idx 1).
function Core.DailyRegenRes()
  local s = Core.state
  if not s then return end
  local maxRes = math.max(1, s.maxRes or 1)
  local gain   = math.floor(maxRes * 0.20 + 0.5)
  s.res = math.min((s.res or 0) + gain, maxRes)
  bump(); notify()
end

function Core.PetDamageWithArmor(amount)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end

  amount = clampNumber(amount, 0, 1e9) or 0
  local hpBefore = p.hp or 0
  local maxBefore = p.maxHp or 0
  local dodgeBefore = math.max(0, p.dodge or 0)

  if amount > 0 and dodgeBefore > 0 and amount <= dodgeBefore then
    sfxDodge()
    pushHistory({
      kind = "DAMAGE_ARMOR",
      subject = "PET",
      input = amount,
      dodged = true,
      dodge = dodgeBefore,
      armor = p.armor or 0,
      trueArmor = p.trueArmor or 0,
      hpBefore = hpBefore,
      hpAfter = hpBefore,
      maxHp = maxBefore,
      bonusHp = 0,
    })
    bump(); notify()
    return
  end

  local absorbedMagic = 0
  local mblock = math.max(0, p.tempMagicBlock or 0)
  if mblock > 0 and amount > 0 then
    absorbedMagic = math.min(mblock, amount)
    p.tempMagicBlock = mblock - absorbedMagic
    amount = amount - absorbedMagic
  end

  local mit = math.max(0, (p.armor or 0) + (p.trueArmor or 0))
  local afterAbsorb = amount
  local dmg = effDmg(amount, mit)
  if dmg > 0 then
    p.hp = math.max(0, (p.hp or 0) - dmg)
  end

  if absorbedMagic > 0 then
    sfxMagicShield()
  elseif amount > 0 then
    sfxDamage()
  end

  pushHistory({
    kind = "DAMAGE_ARMOR",
    subject = "PET",
    input = amount + absorbedMagic,
    afterAbsorb = afterAbsorb,
    absorbedBlock = 0,
    absorbedMagic = absorbedMagic,
    dodge = dodgeBefore,
    dodged = false,
    armor = p.armor or 0,
    trueArmor = p.trueArmor or 0,
    mitigation = mit,
    damage = dmg,
    hpBefore = hpBefore,
    hpAfter = (p.hp or 0),
    maxHp = maxBefore,
    bonusHp = 0,
  })

  updatePetWoundsSticky(p)

  bump(); notify()
end

function Core.PetDamageTrue(amount)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end

  amount = clampNumber(amount, 0, 1e9) or 0
  local hpBefore = p.hp or 0
  local maxBefore = p.maxHp or 0
  local dodgeBefore = math.max(0, p.dodge or 0)

  if amount > 0 and dodgeBefore > 0 and amount <= dodgeBefore then
    sfxDodge()
    pushHistory({
      kind = "DAMAGE_TRUE",
      subject = "PET",
      input = amount,
      dodged = true,
      dodge = dodgeBefore,
      trueArmor = p.trueArmor or 0,
      hpBefore = hpBefore,
      hpAfter = hpBefore,
      maxHp = maxBefore,
      bonusHp = 0,
    })
    bump(); notify()
    return
  end

  local absorbedMagic = 0
  local mblock = math.max(0, p.tempMagicBlock or 0)
  if mblock > 0 and amount > 0 then
    absorbedMagic = math.min(mblock, amount)
    p.tempMagicBlock = mblock - absorbedMagic
    amount = amount - absorbedMagic
  end

  local mit = math.max(0, p.trueArmor or 0)
  local afterAbsorb = amount
  local dmg = effDmg(amount, mit)
  if dmg > 0 then
    p.hp = math.max(0, (p.hp or 0) - dmg)
  end

  if absorbedMagic > 0 then
    sfxMagicShield()
  elseif amount > 0 then
    sfxDamage()
  end

  pushHistory({
    kind = "DAMAGE_TRUE",
    subject = "PET",
    input = amount + absorbedMagic,
    afterAbsorb = afterAbsorb,
    absorbedMagic = absorbedMagic,
    dodge = dodgeBefore,
    dodged = false,
    trueArmor = p.trueArmor or 0,
    mitigation = mit,
    damage = dmg,
    hpBefore = hpBefore,
    hpAfter = (p.hp or 0),
    maxHp = maxBefore,
    bonusHp = 0,
  })

  updatePetWoundsSticky(p)

  bump(); notify()
end

function Core.PetHeal(amount)
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end

  amount = clampNumber(amount, 0, 1e9) or 0
  local hpBefore = p.hp or 0
  local maxBefore = p.maxHp or 0
  if amount > 0 then sfxHealLight() end

  local proposed = hpBefore + amount
  local capMax = (maxBefore * getPetWoundCap(p))
  local healed = math.min(proposed, capMax, maxBefore)
  p.hp = math.max(hpBefore, healed)

  pushHistory({
    kind = "HEAL",
    subject = "PET",
    input = amount,
    current = hpBefore,
    proposed = proposed,
    capMax = capMax,
    effMax = maxBefore,
    applied = (p.hp or 0) - hpBefore,
    hpBefore = hpBefore,
    hpAfter = (p.hp or 0),
    maxHp = maxBefore,
    bonusHp = 0,
    woundCap = getPetWoundCap(p),
  })

  updatePetWoundsSticky(p)

  bump(); notify()
end

function Core.PetDivineHeal()
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end

  local hpBefore = p.hp or 0
  local maxBefore = p.maxHp or 0
  local gain = (maxBefore * 0.75)
  sfxLayOnHands()
  p.hp = math.min(maxBefore, hpBefore + gain)

  pushHistory({
    kind = "DIVINE_HEAL",
    subject = "PET",
    gain = gain,
    hpBefore = hpBefore,
    hpAfter = (p.hp or 0),
    maxHp = maxBefore,
    bonusHp = 0,
  })

  recomputePetWounds(p)

  bump(); notify()
end

function Core.PetSurgery()
  local s = Core.state
  if not s then return end
  local p = ensurePet(s)
  if not p.enabled then return end

  local hpBefore = p.hp or 0
  local maxBefore = p.maxHp or 0
  local gain = (maxBefore * 0.50)
  sfxLayOnHands()
  p.hp = math.min(maxBefore, hpBefore + gain)

  pushHistory({
    kind = "SURGERY",
    subject = "PET",
    gain = gain,
    hpBefore = hpBefore,
    hpAfter = (p.hp or 0),
    maxHp = maxBefore,
    bonusHp = 0,
  })

  recomputePetWounds(p)

  bump(); notify()
end
