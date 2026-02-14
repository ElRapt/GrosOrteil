-- GrosOrteil/Core.lua
local ADDON, ns = ...

local Core = {}
ns.Core = Core

local listeners = {}

local function notify()
  for i = 1, #listeners do
    listeners[i](Core.state)
  end
end

function Core.OnChange(fn)
  listeners[#listeners + 1] = fn
end

local function bump()
  Core.state.rev = (Core.state.rev or 0) + 1
end

local function clampNumber(x, minv, maxv)
  if type(x) ~= "number" then return nil end
  if minv and x < minv then x = minv end
  if maxv and x > maxv then x = maxv end
  return x
end

local function updateWoundCap()
  local s = Core.state
  if not s.maxHp or s.maxHp <= 0 then return end
  local p = s.hp / s.maxHp
  if p < 0.10 then
    s.woundCap = math.min(s.woundCap or 1.0, 0.25)
  elseif p < 0.25 then
    s.woundCap = math.min(s.woundCap or 1.0, 0.50)
  end
end

local function applyHealClamp()
  local s = Core.state
  local cap = (s.woundCap or 1.0)
  local maxAllowed = (s.maxHp or 0) * cap
  if s.hp > maxAllowed then
    s.hp = maxAllowed
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
    woundCap = 1.0,
    rev = 0,
  }
  Core.state = db.state
  notify()
end

-- Setters
function Core.SetHP(hp, maxHp)
  local s = Core.state
  hp = clampNumber(hp, -1e9, 1e9)
  maxHp = clampNumber(maxHp, 1, 1e9)
  if maxHp then s.maxHp = maxHp end
  if hp then s.hp = hp end
  updateWoundCap()
  bump(); notify()
end

function Core.SetRes(res, maxRes)
  local s = Core.state
  res = clampNumber(res, -1e9, 1e9)
  maxRes = clampNumber(maxRes, 1, 1e9)
  if maxRes then s.maxRes = maxRes end
  if res then s.res = res end
  bump(); notify()
end

function Core.SetResEnabled(enabled)
  local s = Core.state
  s.resEnabled = not not enabled
  bump(); notify()
end

function Core.SetArmor(armor, trueArmor)
  local s = Core.state
  armor = clampNumber(armor, 0, 1e9)
  trueArmor = clampNumber(trueArmor, 0, 1e9)
  if armor then s.armor = armor end
  if trueArmor then s.trueArmor = trueArmor end
  bump(); notify()
end

function Core.SetTempBlock(v)
  local s = Core.state
  v = clampNumber(v, 0, 1e9)
  if v then s.tempBlock = v end
  bump(); notify()
end

function Core.ResetTempBlock()
  Core.state.tempBlock = 0
  bump(); notify()
end

-- Actions
function Core.DamageWithArmor(amount)
  local s = Core.state
  amount = clampNumber(amount, 0, 1e9) or 0
  local mit = (s.armor or 0) + (s.tempBlock or 0) + (s.trueArmor or 0)
  s.hp = (s.hp or 0) - effDmg(amount, mit)
  updateWoundCap()
  bump(); notify()
end

function Core.DamageTrue(amount)
  local s = Core.state
  amount = clampNumber(amount, 0, 1e9) or 0
  local mit = (s.trueArmor or 0)
  s.hp = (s.hp or 0) - effDmg(amount, mit)
  updateWoundCap()
  bump(); notify()
end

function Core.Heal(amount)
  local s = Core.state
  amount = clampNumber(amount, 0, 1e9) or 0
  s.hp = (s.hp or 0) + amount
  applyHealClamp()
  bump(); notify()
end

function Core.DivineHeal()
  local s = Core.state
  -- Bypass plafond : fixe à 75% du total
  s.hp = (s.maxHp or 0) * 0.75
  bump(); notify()
end

function Core.AddRes(amount)
  local s = Core.state
  amount = clampNumber(amount, -1e9, 1e9) or 0
  s.res = (s.res or 0) + amount
  bump(); notify()
end
