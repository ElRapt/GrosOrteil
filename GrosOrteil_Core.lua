-- GrosOrteil/Core.lua
local _, ns = ...

local Core = {}
ns.Core = Core

local listeners = {}

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

  local p = (s.hp or 0) / s.maxHp
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
  local hit25, hit10 = woundsFromPct(p)
  s.wounds.hit10 = hit10
  s.wounds.hit25 = hit25
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
    resEnabled = true,
    res = 20, maxRes = 20,
    armor = 0, trueArmor = 0,
    tempBlock = 0,

    wounds = { hit25 = false, hit10 = false },

    rev = 0,
  }

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

  Core.state = db.state
  updateWoundsSticky(Core.state)
  notify()
end

-- Setters
function Core.SetHP(hp, maxHp)
  local s = Core.state
  if not s then return end
  hp = clampNumber(hp, -1e9, 1e9)
  maxHp = clampNumber(maxHp, 1, 1e9)
  if maxHp then s.maxHp = maxHp end
  if hp then s.hp = hp end

  clampToMax(s, "hp", "maxHp")
  recomputeWounds(s)
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

function Core.ResetTempBlock()
  if not Core.state then return end
  Core.state.tempBlock = 0
  bump(); notify()
end

-- Actions
function Core.DamageWithArmor(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, 0, 1e9) or 0

  local block = math.max(0, s.tempBlock or 0)
  if block > 0 and amount > 0 then
    local absorbed = math.min(block, amount)
    s.tempBlock = block - absorbed
    amount = amount - absorbed
  end

  local mit = (s.armor or 0) + (s.trueArmor or 0)
  s.hp = (s.hp or 0) - effDmg(amount, mit)
  updateWoundsSticky(s)
  bump(); notify()
end

function Core.DamageTrue(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, 0, 1e9) or 0
  local mit = (s.trueArmor or 0)
  s.hp = (s.hp or 0) - effDmg(amount, mit)
  updateWoundsSticky(s)
  bump(); notify()
end

function Core.Heal(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, 0, 1e9) or 0

  local current = (s.hp or 0)
  local proposed = current + amount

  -- Cap selon l'état courant (seuils dynamiques)
  local capMax = (s.maxHp or 0) * getWoundCap(s)

  -- Soins normaux : ne dépassent pas le cap (s'il existe)
  s.hp = math.min(proposed, capMax)

  -- IMPORTANT: les soins normaux ne lèvent jamais un seuil
  updateWoundsSticky(s)
  bump(); notify()
end

function Core.DivineHeal()
  local s = Core.state
  if not s then return end
  -- Bypass plafond : +75% du total (pas "fixé" à 75%)
  local maxHp = (s.maxHp or 0)
  local current = (s.hp or 0)
  s.hp = math.min(current + (maxHp * 0.75), maxHp)
  -- DivineHeal est un bypass : on recalcule les seuils depuis l'état actuel
  recomputeWounds(s)
  bump(); notify()
end

function Core.AddRes(amount)
  local s = Core.state
  if not s then return end
  amount = clampNumber(amount, -1e9, 1e9) or 0
  s.res = (s.res or 0) + amount

  clampToMax(s, "res", "maxRes")

  bump(); notify()
end
