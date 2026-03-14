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

local WARLOCK_CORRUPTION_MAX = 60

local function clampWarlockCorruption(s)
  if not s then return end
  s.maxRes2 = WARLOCK_CORRUPTION_MAX
  if type(s.res2) ~= "number" then s.res2 = 0 end
  if s.res2 < 0 then s.res2 = 0 elseif s.res2 > WARLOCK_CORRUPTION_MAX then s.res2 = WARLOCK_CORRUPTION_MAX end
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
    bonusHp = 0,
    classKey = nil,
    res = 20, maxRes = 20,
    res2 = 0, maxRes2 = 20,
    res3 = 0, maxRes3 = 20,
    res4 = 0, maxRes4 = 20,
    auth = 0, maxAuth = 5,
    armor = 0, trueArmor = 0,
    dodge = 0,
    tempBlock = 0,
    tempMagicBlock = 0,

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
  if db.state.tempMagicBlock == nil then db.state.tempMagicBlock = 0 end
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
  if classKey == "WARLOCK" then
    clampWarlockCorruption(s)
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
  if i == 5 then return "auth", "maxAuth" end
  return nil, nil
end

function Core.SetResIndex(i, res, maxRes)
  local s = Core.state
  if not s then return end
  local resKey, maxKey = resKeysForIndex(i)
  if not resKey then return end
  if not maxKey then return end

  -- Warlock corruption (index 2) has fixed max=60.
  local isWarlockCorruption = (i == 2 and s.classKey == "WARLOCK")
  local isShadowInsanity = (i == 2 and s.classKey == "SHADOWPRIEST")

  if isWarlockCorruption then
    maxRes = WARLOCK_CORRUPTION_MAX
    res = clampNumber(res, 0, WARLOCK_CORRUPTION_MAX)
  else
    res = clampNumber(res, -1e9, 1e9)
    maxRes = clampNumber(maxRes, 1, 1e9)
  end

  if maxRes then s[maxKey] = maxRes end
  if res then s[resKey] = res end
  if not isShadowInsanity then
    clampToMax(s, resKey, maxKey)
  end

  if isWarlockCorruption then
    clampWarlockCorruption(s)
  end
  bump(); notify()
end

function Core.AddResIndex(i, amount)
  local s = Core.state
  if not s then return end
  local resKey, maxKey = resKeysForIndex(i)
  if not resKey then return end

  local isWarlockCorruption = (i == 2 and s.classKey == "WARLOCK")
  local isShadowInsanity = (i == 2 and s.classKey == "SHADOWPRIEST")
  amount = clampNumber(amount, -1e9, 1e9) or 0
  s[resKey] = (s[resKey] or 0) + amount

  if isWarlockCorruption then
    clampWarlockCorruption(s)
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

  local hpBefore = (s.hp or 0)
  local baseMaxBefore = (s.maxHp or 0)
  local bonusBefore = math.max(0, s.bonusHp or 0)
  local armorBefore = (s.armor or 0)
  local trueArmorBefore = (s.trueArmor or 0)
  local dodgeBefore = math.max(0, s.dodge or 0)

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
      hpBefore = hpBefore,
      hpAfter = hpBefore,
      maxHp = baseMaxBefore,
      bonusHp = bonusBefore,
    })
    bump(); notify()
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

  local mit = armorBefore + trueArmorBefore

  local afterAbsorb = amount

  local dmg = effDmg(amount, mit)
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
    dodge = dodgeBefore,
    dodged = false,
    armor = armorBefore,
    trueArmor = trueArmorBefore,
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

  local hpBefore = (s.hp or 0)
  local baseMaxBefore = (s.maxHp or 0)
  local bonusBefore = math.max(0, s.bonusHp or 0)
  local trueArmorBefore = (s.trueArmor or 0)
  local dodgeBefore = math.max(0, s.dodge or 0)

  -- Esquive : s'applique aussi aux dégâts bruts.
  if amount > 0 and dodgeBefore > 0 and amount <= dodgeBefore then
    sfxDodge()
    pushHistory({
      kind = "DAMAGE_TRUE",
      input = amount,
      dodged = true,
      dodge = dodgeBefore,
      trueArmor = trueArmorBefore,
      hpBefore = hpBefore,
      hpAfter = hpBefore,
      maxHp = baseMaxBefore,
      bonusHp = bonusBefore,
    })
    bump(); notify()
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

  local mit = trueArmorBefore

  local afterAbsorb = amount

  local dmg = effDmg(amount, mit)
  if dmg > 0 then
    s.hp = (s.hp or 0) - dmg
  end
  clampHpToEffectiveMax(s)

  pushHistory({
    kind = "DAMAGE_TRUE",
    input = amount + absorbedMagic,
    afterAbsorb = afterAbsorb,
    absorbedMagic = absorbedMagic,
    dodge = dodgeBefore,
    dodged = false,
    trueArmor = trueArmorBefore,
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
  -- IMPORTANT: the cap threshold is based on base max HP only.
  -- Bonus HP must not increase the cap.
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
  bump(); notify()
end

function Core.AddRes(amount)
  Core.AddResIndex(1, amount)
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
