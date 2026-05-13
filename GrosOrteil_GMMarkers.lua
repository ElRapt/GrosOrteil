---@diagnostic disable: undefined-global
-- GrosOrteil/GMMarkers.lua
-- Stat tracking and actions for the 8 WoW raid target markers (GM-only).
-- Mirrors Core's pattern: state mutators call bump() then notify() so the
-- UI can react. No undo/redo, no class system, no pet, no perception.
local _, ns = ...

local GMMarkers = {}
ns.GMMarkers = GMMarkers

local Shared  = ns.Shared
local History = ns.History

local NUM_MARKERS = 8

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function clamp(x, lo, hi)
  if type(x) ~= "number" then return lo or 0 end
  if lo and x < lo then x = lo end
  if hi and x > hi then x = hi end
  return x
end

local function clampHP(s)
  if s.hp < 0 then s.hp = 0 end
  if s.maxHp > 0 and s.hp > s.maxHp then s.hp = s.maxHp end
end

local function pushHistory(s, entry)
  if History and History.Push then
    History.Push(s, entry)
  else
    if type(s.history) ~= "table" then s.history = {} end
    table.insert(s.history, 1, entry)
    while #s.history > 60 do table.remove(s.history) end
  end
end

---------------------------------------------------------------------------
-- Default state factory
---------------------------------------------------------------------------

local function defaultState(idx)
  local name = (Shared.RAID_MARKERS and Shared.RAID_MARKERS[idx] and Shared.RAID_MARKERS[idx].name) or ("Marqueur " .. idx)
  return {
    label        = name,
    hp           = 50,
    maxHp        = 50,
    wounds       = { hit25 = false, hit10 = false },
    stabilise    = nil,
    armor        = 0,
    trueArmor    = 0,
    tempArmor    = 0,
    dodge        = 0,
    tempBlock    = 0,
    magicShield  = { hp = 0, maxHp = 0, armor = 0 },
    res          = 20,
    maxRes       = 20,
    attaqueMelee    = 0,
    attaqueDistance = 0,
    chance       = 1,
    maxChance    = 1,
    history      = {},
    rev          = 0,
  }
end

-- Apply missing fields from defaults onto an existing table (migration).
local function applyDefaults(t, idx)
  local def = defaultState(idx)
  for k, v in pairs(def) do
    if t[k] == nil then
      if type(v) == "table" then
        t[k] = {}
        for kk, vv in pairs(v) do t[k][kk] = vv end
      else
        t[k] = v
      end
    end
  end
  -- Ensure wounds sub-table has both fields
  if type(t.wounds) ~= "table" then t.wounds = { hit25 = false, hit10 = false } end
  if t.wounds.hit25 == nil then t.wounds.hit25 = false end
  if t.wounds.hit10 == nil then t.wounds.hit10 = false end
  -- Ensure magicShield sub-table
  if type(t.magicShield) ~= "table" then t.magicShield = { hp = 0, maxHp = 0, armor = 0 } end
end

---------------------------------------------------------------------------
-- Observer (per-marker listeners)
---------------------------------------------------------------------------

-- listeners[idx] = list of { id, fn }
local listenerMap = {}
local nextId = 0

local function bump(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  s.rev = s.rev + 1
  local ls = listenerMap[idx]
  if not ls then return end
  for i = 1, #ls do
    pcall(ls[i].fn, idx)
  end
end

-- Register a listener for state changes on marker idx.
-- fn(idx) is called on every change. Returns an unregister function.
function GMMarkers.OnChange(idx, fn)
  if type(fn) ~= "function" then return function() end end
  nextId = nextId + 1
  local id = nextId
  if not listenerMap[idx] then listenerMap[idx] = {} end
  listenerMap[idx][#listenerMap[idx] + 1] = { id = id, fn = fn }
  return function()
    local ls = listenerMap[idx]
    if not ls then return end
    for i = 1, #ls do
      if ls[i].id == id then table.remove(ls, i); return end
    end
  end
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

GMMarkers.states = {}

function ns.GMMarkers_Init()
  -- GrosOrteilDB is account-wide (accessible directly as global in WoW,
  -- or as rawget(_G,"GrosOrteilDB") for test safety).
  local db = rawget(_G, "GrosOrteilDB")
  if type(db) ~= "table" then
    rawset(_G, "GrosOrteilDB", {})
    db = rawget(_G, "GrosOrteilDB")
  end
  if type(db.gmMarkers) ~= "table" then db.gmMarkers = {} end

  for i = 1, NUM_MARKERS do
    if type(db.gmMarkers[i]) ~= "table" then
      db.gmMarkers[i] = defaultState(i)
    else
      applyDefaults(db.gmMarkers[i], i)
    end
    GMMarkers.states[i] = db.gmMarkers[i]
    listenerMap[i] = listenerMap[i] or {}
  end
end

---------------------------------------------------------------------------
-- Stat setters
---------------------------------------------------------------------------

function GMMarkers.SetHP(idx, hp, maxHp)
  local s = GMMarkers.states[idx]
  if not s then return end
  maxHp = clamp(maxHp, 1, 1e9)
  hp    = clamp(hp,    0, maxHp)
  s.hp    = hp
  s.maxHp = maxHp
  Shared.RecomputeWounds(s)
  if s.hp > 0 then s.stabilise = nil end
  bump(idx)
end

function GMMarkers.SetArmor(idx, armor, trueArmor)
  local s = GMMarkers.states[idx]
  if not s then return end
  s.armor     = clamp(armor,     0, 1e9)
  s.trueArmor = clamp(trueArmor, 0, 1e9)
  bump(idx)
end

function GMMarkers.SetTempArmor(idx, v)
  local s = GMMarkers.states[idx]
  if not s then return end
  s.tempArmor = clamp(v, 0, 1e9)
  bump(idx)
end

function GMMarkers.ResetTempArmor(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  s.tempArmor = 0
  bump(idx)
end

function GMMarkers.SetDodge(idx, v)
  local s = GMMarkers.states[idx]
  if not s then return end
  s.dodge = clamp(v, 0, 1e9)
  bump(idx)
end

function GMMarkers.SetTempBlock(idx, v)
  local s = GMMarkers.states[idx]
  if not s then return end
  s.tempBlock = clamp(v, 0, 1e9)
  bump(idx)
end

function GMMarkers.ResetTempBlock(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  s.tempBlock = 0
  bump(idx)
end

function GMMarkers.SetMagicShield(idx, hp, maxHp, armor)
  local s = GMMarkers.states[idx]
  if not s then return end
  maxHp = clamp(maxHp, 0, 1e9)
  hp    = clamp(hp,    0, maxHp)
  armor = clamp(armor, 0, 1e9)
  s.magicShield = { hp = hp, maxHp = maxHp, armor = armor }
  bump(idx)
end

function GMMarkers.ResetMagicShield(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  s.magicShield = { hp = 0, maxHp = 0, armor = 0 }
  bump(idx)
end

function GMMarkers.SetRes(idx, res, maxRes)
  local s = GMMarkers.states[idx]
  if not s then return end
  maxRes = clamp(maxRes, 0, 1e9)
  res    = clamp(res,    0, maxRes)
  s.res    = res
  s.maxRes = maxRes
  bump(idx)
end

function GMMarkers.AddRes(idx, amount)
  local s = GMMarkers.states[idx]
  if not s then return end
  amount = clamp(amount, -1e9, 1e9)
  s.res = clamp((s.res or 0) + amount, 0, s.maxRes or 0)
  bump(idx)
end

function GMMarkers.SetAttaque(idx, melee, dist)
  local s = GMMarkers.states[idx]
  if not s then return end
  s.attaqueMelee    = clamp(melee, 0, 1e9)
  s.attaqueDistance = clamp(dist,  0, 1e9)
  bump(idx)
end

function GMMarkers.SetChance(idx, cur, maxv)
  local s = GMMarkers.states[idx]
  if not s then return end
  maxv = clamp(maxv, 0, 1e9)
  cur  = clamp(cur,  0, maxv)
  s.chance    = cur
  s.maxChance = maxv
  bump(idx)
end

function GMMarkers.SetLabel(idx, text)
  local s = GMMarkers.states[idx]
  if not s then return end
  if type(text) ~= "string" then text = "" end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  s.label = text ~= "" and text or (Shared.RAID_MARKERS and Shared.RAID_MARKERS[idx] and Shared.RAID_MARKERS[idx].name or "")
  bump(idx)
end

function GMMarkers.SetStabilise(idx, v)
  local s = GMMarkers.states[idx]
  if not s then return end
  s.stabilise = v and true or nil
  bump(idx)
end

function GMMarkers.ResetMarker(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  local fresh = defaultState(idx)
  for k, v in pairs(fresh) do
    if type(v) == "table" then
      s[k] = {}
      for kk, vv in pairs(v) do s[k][kk] = vv end
    else
      s[k] = v
    end
  end
  -- Preserve rev continuity so listeners can detect a reset as a change.
  s.rev = (s.rev or 0) + 1
  bump(idx)
end

function GMMarkers.ClearHistory(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  if History and History.Clear then
    History.Clear(s)
  else
    s.history = {}
  end
  bump(idx)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

-- Damage pipeline: dodge → tempBlock → magicShield → armor mitigation.
function GMMarkers.DamageWithArmor(idx, amount)
  local s = GMMarkers.states[idx]
  if not s then return end
  amount = clamp(amount, 0, 1e9)

  local hpBefore  = s.hp or 0
  local maxBefore = s.maxHp or 0
  local dodgeVal  = math.max(0, s.dodge or 0)

  -- Dodge
  if amount > 0 and dodgeVal > 0 and amount <= dodgeVal then
    pushHistory(s, {
      kind = "DAMAGE_ARMOR", input = amount,
      dodged = true, dodge = dodgeVal,
      hpBefore = hpBefore, hpAfter = hpBefore, maxHp = maxBefore,
    })
    bump(idx)
    return
  end

  local absorbedBlock = 0
  local absorbedMagic = 0

  -- TempBlock
  local block = math.max(0, s.tempBlock or 0)
  if block > 0 and amount > 0 then
    absorbedBlock = math.min(block, amount)
    s.tempBlock   = block - absorbedBlock
    amount        = amount - absorbedBlock
  end

  -- Magic shield
  local overflow
  overflow, absorbedMagic = Shared.ConsumeMagicShield(s.magicShield, amount)
  amount = overflow

  -- Armor mitigation
  local mit = Shared.ComputeMitigation(s, true)
  local dmg = math.max(0, amount - mit)

  if dmg > 0 then
    s.hp = math.max(0, (s.hp or 0) - dmg)
  end

  pushHistory(s, {
    kind          = "DAMAGE_ARMOR",
    input         = clamp(amount + absorbedBlock + absorbedMagic, 0, 1e9),
    absorbedBlock = absorbedBlock,
    absorbedMagic = absorbedMagic,
    dodge         = dodgeVal,
    dodged        = false,
    armor         = s.armor or 0,
    trueArmor     = s.trueArmor or 0,
    tempArmor     = math.max(0, s.tempArmor or 0),
    mitigation    = mit,
    damage        = dmg,
    hpBefore      = hpBefore,
    hpAfter       = s.hp or 0,
    maxHp         = maxBefore,
  })

  Shared.UpdateWoundsSticky(s)
  if (s.hp or 0) <= 0 then s.stabilise = true end
  bump(idx)
end

-- True damage: ignores armor, applies only trueArmor + tempArmor.
function GMMarkers.DamageTrue(idx, amount)
  local s = GMMarkers.states[idx]
  if not s then return end
  amount = clamp(amount, 0, 1e9)

  local hpBefore  = s.hp or 0
  local maxBefore = s.maxHp or 0
  local dodgeVal  = math.max(0, s.dodge or 0)

  -- Dodge
  if amount > 0 and dodgeVal > 0 and amount <= dodgeVal then
    pushHistory(s, {
      kind = "DAMAGE_TRUE", input = amount,
      dodged = true, dodge = dodgeVal,
      hpBefore = hpBefore, hpAfter = hpBefore, maxHp = maxBefore,
    })
    bump(idx)
    return
  end

  local absorbedMagic = 0
  local overflow
  overflow, absorbedMagic = Shared.ConsumeMagicShield(s.magicShield, amount)
  amount = overflow

  local mit = Shared.ComputeMitigation(s, false) -- trueArmor + tempArmor only
  local dmg = math.max(0, amount - mit)

  if dmg > 0 then
    s.hp = math.max(0, (s.hp or 0) - dmg)
  end

  pushHistory(s, {
    kind          = "DAMAGE_TRUE",
    input         = clamp(amount + absorbedMagic, 0, 1e9),
    absorbedMagic = absorbedMagic,
    dodge         = dodgeVal,
    dodged        = false,
    trueArmor     = s.trueArmor or 0,
    tempArmor     = math.max(0, s.tempArmor or 0),
    mitigation    = mit,
    damage        = dmg,
    hpBefore      = hpBefore,
    hpAfter       = s.hp or 0,
    maxHp         = maxBefore,
  })

  Shared.UpdateWoundsSticky(s)
  if (s.hp or 0) <= 0 then s.stabilise = true end
  bump(idx)
end

-- Normal heal: capped by wound threshold.
function GMMarkers.Heal(idx, amount)
  local s = GMMarkers.states[idx]
  if not s then return end
  amount = clamp(amount, 0, 1e9)

  local hpBefore  = s.hp or 0
  local maxBefore = s.maxHp or 0
  local capMult   = Shared.GetWoundCap(s.wounds)
  local capMax    = maxBefore * capMult
  local proposed  = hpBefore + amount
  local healed    = math.min(proposed, capMax, maxBefore)
  s.hp = math.max(hpBefore, healed)
  clampHP(s)

  pushHistory(s, {
    kind     = "HEAL",
    input    = amount,
    current  = hpBefore,
    proposed = proposed,
    capMax   = capMax,
    effMax   = maxBefore,
    applied  = (s.hp or 0) - hpBefore,
    hpBefore = hpBefore,
    hpAfter  = s.hp or 0,
    maxHp    = maxBefore,
    woundCap = capMult,
  })

  Shared.UpdateWoundsSticky(s)
  if (s.hp or 0) > 0 then s.stabilise = nil end
  bump(idx)
end

-- Divine heal: +75 % of maxHp, ignores wound cap.
function GMMarkers.DivineHeal(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  local hpBefore  = s.hp or 0
  local maxBefore = s.maxHp or 0
  local gain      = maxBefore * 0.75
  s.hp = math.min((s.hp or 0) + gain, maxBefore)
  clampHP(s)
  Shared.RecomputeWounds(s)
  if (s.hp or 0) > 0 then s.stabilise = nil end
  pushHistory(s, { kind = "DIVINE_HEAL", gain = gain, hpBefore = hpBefore, hpAfter = s.hp or 0, maxHp = maxBefore })
  bump(idx)
end

-- Surgery: +50 % of maxHp, ignores wound cap.
function GMMarkers.Surgery(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  local hpBefore  = s.hp or 0
  local maxBefore = s.maxHp or 0
  local gain      = maxBefore * 0.50
  s.hp = math.min((s.hp or 0) + gain, maxBefore)
  clampHP(s)
  Shared.RecomputeWounds(s)
  if (s.hp or 0) > 0 then s.stabilise = nil end
  pushHistory(s, { kind = "SURGERY", gain = gain, hpBefore = hpBefore, hpAfter = s.hp or 0, maxHp = maxBefore })
  bump(idx)
end

-- Restore HP to maxHp and clear wounds.
function GMMarkers.RestoreHP(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  local hpBefore  = s.hp or 0
  local maxBefore = s.maxHp or 0
  s.hp = maxBefore
  s.wounds.hit25 = false
  s.wounds.hit10 = false
  s.stabilise = nil
  pushHistory(s, { kind = "RESTORE_HP", hpBefore = hpBefore, hpAfter = s.hp, maxHp = maxBefore })
  bump(idx)
end

-- Daily HP regen: +10 % of maxHp.
function GMMarkers.DailyRegenHP(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  local hpBefore  = s.hp or 0
  local maxBefore = s.maxHp or 0
  local gain      = Shared.Round and Shared.Round(maxBefore * 0.10) or math.floor(maxBefore * 0.10 + 0.5)
  s.hp = math.min((s.hp or 0) + gain, maxBefore)
  clampHP(s)
  Shared.UpdateWoundsSticky(s)
  if (s.hp or 0) > 0 then s.stabilise = nil end
  pushHistory(s, { kind = "REGEN_HP", gain = gain, hpBefore = hpBefore, hpAfter = s.hp or 0, maxHp = maxBefore })
  bump(idx)
end

-- Daily resource regen: +20 % of maxRes.
function GMMarkers.DailyRegenRes(idx)
  local s = GMMarkers.states[idx]
  if not s then return end
  local before  = s.res or 0
  local maxRes  = s.maxRes or 0
  local gain    = Shared.Round and Shared.Round(maxRes * 0.20) or math.floor(maxRes * 0.20 + 0.5)
  s.res = math.min(before + gain, maxRes)
  pushHistory(s, { kind = "REGEN_RES", gain = gain, resBefore = before, resAfter = s.res, maxRes = maxRes })
  bump(idx)
end

---------------------------------------------------------------------------
-- GM eligibility check (UI-facing helper)
---------------------------------------------------------------------------

function GMMarkers.IsGMEligible()
  local inGroup = (type(IsInRaid)   == "function" and IsInRaid())
               or (type(IsInGroup)  == "function" and IsInGroup())
  if not inGroup then return false end
  if type(UnitIsGroupLeader)    == "function" and UnitIsGroupLeader("player")    then return true end
  if type(UnitIsGroupAssistant) == "function" and UnitIsGroupAssistant("player") then return true end
  return false
end
