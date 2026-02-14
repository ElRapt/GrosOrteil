-- GrosOrteil/Core.lua
local _, ns = ...

local Core = {}
ns.Core = Core

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

local function bump()
  if not Core.state then return end
  Core.state.rev = (Core.state.rev or 0) + 1
end

local function clampNumber(x, minv, maxv)
  if type(x) ~= "number" then return nil end
  if minv and x < minv then x = minv end
  if maxv and x > maxv then x = maxv end
  return x
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

local function effDmg(dmg, mitigation)
  dmg = math.max(0, dmg or 0)
  mitigation = math.max(0, mitigation or 0)
  local eff = dmg - mitigation
  if eff < 0 then eff = 0 end
  return eff
end

function ns.Core_Init()
  local db = GrosOrteilDB

  db.state = db.state or {
    hp = 50, maxHp = 50,
    bonusHp = 0,
    classKey = nil,
    resEnabled = true,
    res = 20, maxRes = 20,
    res2 = 0, maxRes2 = 20,
    res3 = 0, maxRes3 = 20,
    res4 = 0, maxRes4 = 20,
    armor = 0, trueArmor = 0,
    dodge = 0,
    tempBlock = 0,
    tempMagicBlock = 0,

    wounds = { hit25 = false, hit10 = false },

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
  if db.state.tempMagicBlock == nil then db.state.tempMagicBlock = 0 end
  if db.state.resEnabled == nil then db.state.resEnabled = true end

  -- Ensure multi-resource fields exist (Warlock/Shadow Priest/Shaman).
  if db.state.res2 == nil then db.state.res2 = 0 end
  if db.state.maxRes2 == nil then db.state.maxRes2 = db.state.maxRes or 20 end
  if db.state.res3 == nil then db.state.res3 = 0 end
  if db.state.maxRes3 == nil then db.state.maxRes3 = db.state.maxRes or 20 end
  if db.state.res4 == nil then db.state.res4 = 0 end
  if db.state.maxRes4 == nil then db.state.maxRes4 = db.state.maxRes or 20 end
  -- Migration: tempHp -> bonusHp
  if db.state.bonusHp == nil then
    db.state.bonusHp = db.state.tempHp or 0
  end
  db.state.tempHp = nil
  clampHpToEffectiveMax(db.state)

  Core.state = db.state
  updateWoundsSticky(Core.state)
  notify()
end

function Core.SetClassKey(classKey)
  local s = Core.state
  if not s then return end
  if type(classKey) ~= "string" or classKey == "" then return end
  if s.classKey == classKey then return end
  s.classKey = classKey
  bump(); notify()
end

-- Setters
function Core.SetHP(hp, maxHp)
  local s = Core.state
  if not s then return end
  hp = clampNumber(hp, -1e9, 1e9)
  maxHp = clampNumber(maxHp, 1, 1e9)
  if maxHp then s.maxHp = maxHp end
  if hp then s.hp = hp end

  clampHpToEffectiveMax(s)
  recomputeWounds(s)
  bump(); notify()
end

function Core.SetBonusHP(v)
  local s = Core.state
  if not s then return end
  v = clampNumber(v, 0, 1e9)
  if v then s.bonusHp = v end
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
  return nil, nil
end

function Core.SetResIndex(i, res, maxRes)
  local s = Core.state
  if not s then return end
  local resKey, maxKey = resKeysForIndex(i)
  if not resKey then return end
  if not maxKey then return end

  res = clampNumber(res, -1e9, 1e9)
  maxRes = clampNumber(maxRes, 1, 1e9)
  if maxRes then s[maxKey] = maxRes end
  if res then s[resKey] = res end
  clampToMax(s, resKey, maxKey)
  bump(); notify()
end

function Core.AddResIndex(i, amount)
  local s = Core.state
  if not s then return end
  local resKey, maxKey = resKeysForIndex(i)
  if not resKey then return end
  amount = clampNumber(amount, -1e9, 1e9) or 0
  s[resKey] = (s[resKey] or 0) + amount
  clampToMax(s, resKey, maxKey)
  bump(); notify()
end

function Core.SetResEnabled(enabled)
  local s = Core.state
  if not s then return end
  s.resEnabled = not not enabled
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

function Core.SetTempBlock(v)
  local s = Core.state
  if not s then return end
  v = clampNumber(v, 0, 1e9)
  if v then s.tempBlock = v end
  bump(); notify()
end

function Core.SetTempMagicBlock(v)
  local s = Core.state
  if not s then return end
  v = clampNumber(v, 0, 1e9)
  if v then s.tempMagicBlock = v end
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

function Core.ResetTempBlock()
  if not Core.state then return end
  Core.state.tempBlock = 0
  bump(); notify()
end

function Core.ResetTempMagicBlock()
  if not Core.state then return end
  Core.state.tempMagicBlock = 0
  bump(); notify()
end

-- Actions
function Core.DamageWithArmor(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, 0, 1e9) or 0

  -- Esquive : si les dégâts sont <= au seuil, ils sont entièrement ignorés.
  local dodge = math.max(0, s.dodge or 0)
  if amount > 0 and dodge > 0 and amount <= dodge then
    return
  end

  local absorbedBlock = 0
  local absorbedMagic = 0

  local block = math.max(0, s.tempBlock or 0)
  if block > 0 and amount > 0 then
    absorbedBlock = math.min(block, amount)
    s.tempBlock = block - absorbedBlock
    amount = amount - absorbedBlock
  end

  -- Blocage magique : comme le blocage, mais fonctionne aussi sur dégâts bruts.
  local mblock = math.max(0, s.tempMagicBlock or 0)
  if mblock > 0 and amount > 0 then
    absorbedMagic = math.min(mblock, amount)
    s.tempMagicBlock = mblock - absorbedMagic
    amount = amount - absorbedMagic
  end

  -- SFX (une seule par "coup") : magic > block > damage
  if absorbedMagic > 0 then
    sfxMagicShield()
  elseif absorbedBlock > 0 then
    sfxBlock()
  elseif amount > 0 then
    sfxDamage()
  end

  local mit = (s.armor or 0) + (s.trueArmor or 0)

  local dmg = effDmg(amount, mit)
  if dmg > 0 then
    s.hp = (s.hp or 0) - dmg
  end
  updateWoundsSticky(s)
  bump(); notify()
end

function Core.DamageTrue(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, 0, 1e9) or 0

  -- Esquive : s'applique aussi aux dégâts bruts.
  local dodge = math.max(0, s.dodge or 0)
  if amount > 0 and dodge > 0 and amount <= dodge then
    return
  end

  local absorbedMagic = 0

  -- Blocage magique : s'applique aux dégâts bruts (contrairement au blocage normal).
  local mblock = math.max(0, s.tempMagicBlock or 0)
  if mblock > 0 and amount > 0 then
    absorbedMagic = math.min(mblock, amount)
    s.tempMagicBlock = mblock - absorbedMagic
    amount = amount - absorbedMagic
  end

  if absorbedMagic > 0 then
    sfxMagicShield()
  elseif amount > 0 then
    sfxDamage()
  end

  local mit = (s.trueArmor or 0)

  local dmg = effDmg(amount, mit)
  if dmg > 0 then
    s.hp = (s.hp or 0) - dmg
  end
  updateWoundsSticky(s)
  bump(); notify()
end

function Core.Heal(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, 0, 1e9) or 0

  if amount > 0 then sfxHealLight() end

  local current = (s.hp or 0)
  local proposed = current + amount

  -- Cap selon l'état courant (seuils dynamiques)
  local baseMax = (s.maxHp or 0)
  local bonus = math.max(0, s.bonusHp or 0)
  -- IMPORTANT: the cap threshold is based on base max HP only.
  -- Bonus HP must not increase the cap.
  local capMax = (baseMax * getWoundCap(s))
  local effMax = baseMax + bonus

  -- Soins normaux : ne dépassent pas le cap (s'il existe)
  -- Never reduce HP if current HP is already above the cap.
  local healed = math.min(proposed, capMax, effMax)
  s.hp = math.max(current, healed)

  -- IMPORTANT: les soins normaux ne lèvent jamais un seuil
  updateWoundsSticky(s)
  bump(); notify()
end

function Core.DivineHeal()
  local s = Core.state
  if not s then return end

  sfxLayOnHands()
  -- Bypass plafond : +75% du total (pas "fixé" à 75%)
  local baseMax = (s.maxHp or 0)
  local bonus = math.max(0, s.bonusHp or 0)
  local maxHp = baseMax + bonus
  local current = (s.hp or 0)
  s.hp = math.min(current + (baseMax * 0.75), maxHp)
  -- DivineHeal est un bypass : on recalcule les seuils depuis l'état actuel
  recomputeWounds(s)
  bump(); notify()
end

function Core.AddRes(amount)
  Core.AddResIndex(1, amount)
end
