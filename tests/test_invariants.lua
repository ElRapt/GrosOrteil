---@diagnostic disable: undefined-global
-- Invariant fuzz: drive Core through random op sequences and assert
-- structural invariants after every operation. Designed to catch the kind
-- of bugs unit tests miss: unexpected mutation interactions, missed
-- clamps, broken sticky flags, etc.
--
-- Determinism: math.randomseed is fixed so reruns reproduce the same path.
-- Bump the seed locally to explore more space.

local T = _G.T
local ns = _G.NS
local Core = ns.Core

local SEED = 42
local STEPS = 1500
-- Number of seeds to run. Each seed runs STEPS ops, so total = SEED_COUNT * STEPS.
-- Bumping this widens fuzz coverage at modest cost (~2ms per seed locally).
local SEED_COUNT = 16

local CLASSES = {
  "MAGE", "WARLOCK", "PRIEST", "PALADIN", "ROGUE", "SHAMAN",
  "DRUID", "MONK", "MEDIC", "SHADOWPRIEST", "WARRIOR", "HUNTER",
}

-- Each entry is { name, weight, fn(rng) }. Weight controls relative frequency.
local OPS

local function pickInt(rng, lo, hi) return lo + math.floor(rng() * (hi - lo + 1)) end

local function check(state)
  local s = state
  -- HP bounds.
  if s.hp ~= nil then
    assert(s.hp >= 0,                                    "hp < 0: "  .. tostring(s.hp))
    assert(type(s.maxHp) == "number" and s.maxHp >= 1,   "bad maxHp: " .. tostring(s.maxHp))
    assert(s.hp <= s.maxHp,                              "hp > maxHp: " .. tostring(s.hp) .. " > " .. tostring(s.maxHp))
  end
  -- Resource bounds (skip insanity special case).
  local function resCheck(idx, isShadowInsanity)
    local resKey, maxKey = ns.Shared.GetKeysForIdx(idx)
    if not resKey then return end
    local v, m = s[resKey], s[maxKey]
    if type(v) ~= "number" or type(m) ~= "number" then return end
    assert(m >= 0, ("%s < 0"):format(maxKey))
    if not isShadowInsanity then
      assert(v <= m, ("%s > %s (%s > %s)"):format(resKey, maxKey, tostring(v), tostring(m)))
    end
  end
  resCheck(1, false)
  resCheck(2, s.classKey == "SHADOWPRIEST")
  resCheck(3, false)
  resCheck(4, false)
  resCheck(5, false)
  -- Wounds must be booleans, hit10 implies hit25.
  assert(type(s.wounds) == "table", "missing wounds")
  assert(type(s.wounds.hit25) == "boolean")
  assert(type(s.wounds.hit10) == "boolean")
  if s.wounds.hit10 then
    assert(s.wounds.hit25, "hit10 without hit25")
  end
  -- Magic shield: hp ≤ maxHp when maxHp > 0.
  if s.magicShield and (s.magicShield.maxHp or 0) > 0 then
    assert(s.magicShield.hp <= s.magicShield.maxHp, "shield hp > maxHp")
  end
  -- Mana shield only active for MAGE.
  if s.manaShield and s.manaShield.active then
    assert(s.classKey == "MAGE", "mana shield active outside MAGE")
  end
  -- Shaman posture only valid for SHAMAN.
  if s.shamanPosture then
    assert(s.classKey == "SHAMAN", "posture set for non-SHAMAN")
    local valid = { TERRE = true, AIR = true, EAU = true, FEU = true }
    assert(valid[s.shamanPosture], "bad posture: " .. tostring(s.shamanPosture))
  end
  -- Pet structural invariants.
  local p = s.pet or {}
  if p.hp ~= nil then
    assert(p.hp >= 0,             "pet hp < 0")
    assert(p.maxHp >= 1,          "pet maxHp < 1")
    assert(p.hp <= p.maxHp,       "pet hp > maxHp")
  end
  if p.wounds then
    if p.wounds.hit10 then assert(p.wounds.hit25, "pet hit10 w/o hit25") end
  end
  if p.magicShield and (p.magicShield.maxHp or 0) > 0 then
    assert(p.magicShield.hp <= p.magicShield.maxHp, "pet shield hp > maxHp")
  end
end

OPS = {
  { "SetHP",          5, function(rng) Core.SetHP(pickInt(rng, 0, 200), pickInt(rng, 1, 200)) end },
  { "DamageWithArmor", 5, function(rng) Core.DamageWithArmor(pickInt(rng, 0, 50)) end },
  { "DamageTrue",     4, function(rng) Core.DamageTrue(pickInt(rng, 0, 50)) end },
  { "Heal",           4, function(rng) Core.Heal(pickInt(rng, 0, 50)) end },
  { "DivineHeal",     1, function(rng) Core.DivineHeal() end },
  { "Surgery",        1, function(rng) Core.Surgery() end },
  { "RestoreHP",      1, function(rng) Core.RestoreHP() end },
  { "DailyRegenHP",   1, function(rng) Core.DailyRegenHP() end },
  { "DailyRegenRes",  1, function(rng) Core.DailyRegenRes() end },
  { "SetArmor",       2, function(rng) Core.SetArmor(pickInt(rng, 0, 30), pickInt(rng, 0, 10)) end },
  { "SetTempArmor",   2, function(rng) Core.SetTempArmor(pickInt(rng, 0, 30)) end },
  { "ResetTempArmor", 1, function(rng) Core.ResetTempArmor() end },
  { "SetDodge",       2, function(rng) Core.SetDodge(pickInt(rng, 0, 30)) end },
  { "ResetDodge",     1, function(rng) Core.ResetDodge() end },
  { "SetTempBlock",   2, function(rng) Core.SetTempBlock(pickInt(rng, 0, 30)) end },
  { "ResetTempBlock", 1, function(rng) Core.ResetTempBlock() end },
  { "SetMagicShield", 2, function(rng) Core.SetMagicShield(pickInt(rng, 0, 40), pickInt(rng, 0, 40), pickInt(rng, 0, 10)) end },
  { "ResetMagicShield", 1, function(rng) Core.ResetMagicShield() end },
  { "SetManaShieldArmor", 1, function(rng) Core.SetManaShieldArmor(pickInt(rng, 0, 40)) end },
  { "ToggleManaShield", 1, function(rng) Core.ToggleManaShield() end },
  { "SetRes",         2, function(rng) Core.SetRes(pickInt(rng, 0, 30), pickInt(rng, 1, 30)) end },
  { "AddRes",         2, function(rng) Core.AddRes(pickInt(rng, -10, 10)) end },
  { "SetResIndex2",   1, function(rng) Core.SetResIndex(2, pickInt(rng, 0, 30), pickInt(rng, 1, 30)) end },
  { "SetResIndex3",   1, function(rng) Core.SetResIndex(3, pickInt(rng, 0, 30), pickInt(rng, 1, 30)) end },
  { "SetResIndex4",   1, function(rng) Core.SetResIndex(4, pickInt(rng, 0, 30), pickInt(rng, 1, 30)) end },
  { "SetResIndex5",   1, function(rng) Core.SetResIndex(5, pickInt(rng, 0, 5),  pickInt(rng, 1, 5))  end },
  { "AddResIndex",    1, function(rng) Core.AddResIndex(pickInt(rng, 1, 5), pickInt(rng, -5, 5)) end },
  { "SetClassKey",    1, function(rng) Core.SetClassKey(CLASSES[pickInt(rng, 1, #CLASSES)]) end },
  { "SetShamanPosture", 1, function(rng)
      local p = ({ "TERRE", "AIR", "EAU", "FEU" })[pickInt(rng, 1, 4)]
      Core.SetShamanPosture(p)
    end },
  { "SetPetEnabled",  1, function(rng) Core.SetPetEnabled(rng() < 0.5) end },
  { "SetPetHP",       2, function(rng) Core.SetPetHP(pickInt(rng, 0, 50), pickInt(rng, 1, 50)) end },
  { "SetPetArmor",    1, function(rng) Core.SetPetArmor(pickInt(rng, 0, 10), pickInt(rng, 0, 5)) end },
  { "SetPetDodge",    1, function(rng) Core.SetPetDodge(pickInt(rng, 0, 10)) end },
  { "SetPetTempArmor", 1, function(rng) Core.SetPetTempArmor(pickInt(rng, 0, 10)) end },
  { "SetPetMagicShield", 1, function(rng) Core.SetPetMagicShield(pickInt(rng, 0, 10), pickInt(rng, 0, 10), pickInt(rng, 0, 5)) end },
  { "PetDamageWithArmor", 1, function(rng) Core.PetDamageWithArmor(pickInt(rng, 0, 30)) end },
  { "PetDamageTrue",  1, function(rng) Core.PetDamageTrue(pickInt(rng, 0, 30)) end },
  { "PetHeal",        1, function(rng) Core.PetHeal(pickInt(rng, 0, 30)) end },
  { "PetRestoreHP",   1, function(rng) Core.PetRestoreHP() end },
  { "PetDailyRegenHP", 1, function(rng) Core.PetDailyRegenHP() end },
  { "Undo",           1, function(rng) Core.Undo() end },
  { "Redo",           1, function(rng) Core.Redo() end },
  { "ClearHistory",   1, function(rng) Core.ClearHistory() end },
}

local function buildPool()
  local pool = {}
  for _, op in ipairs(OPS) do
    for _ = 1, op[2] do pool[#pool + 1] = op end
  end
  return pool
end

T.describe("Invariant fuzz", function()
  for s = 1, SEED_COUNT do
    local seed = SEED + (s - 1) * 1000
    T.it(("invariants hold across %d random ops (seed %d)"):format(STEPS, seed), function()
      Core.ResetToDefaults()
      math.randomseed(seed)
      local pool = buildPool()
      local rng = math.random

      local lastOp = "<init>"
      local ok, err = pcall(function()
        for _ = 1, STEPS do
          local op = pool[pickInt(rng, 1, #pool)]
          lastOp = op[1]
          op[3](rng)
          check(Core.state)
        end
      end)
      if not ok then
        error(("invariant violated after op '%s' (seed %d): %s"):format(lastOp, seed, tostring(err)))
      end
      T.assertTrue(ok)
    end)
  end
end)

-- Sanity: serialize+deserialize after a fuzzed state must round-trip.
T.describe("Comm round-trip after fuzz", function()
  T.it("serialized payload deserializes back without error", function()
    Core.ResetToDefaults()
    math.randomseed(99)
    local pool = buildPool()
    for _ = 1, 200 do
      local op = pool[pickInt(math.random, 1, #pool)]
      op[3](math.random)
    end
    local s = ns.Comm.SerializeState(Core.state)
    T.assertNotNil(s)
    local out = ns.Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertNotNil(out)
    T.assertEq(out.hp, Core.state.hp)
    T.assertEq(out.maxHp, Core.state.maxHp)
    T.assertEq(out.classKey, Core.state.classKey)
  end)
end)
