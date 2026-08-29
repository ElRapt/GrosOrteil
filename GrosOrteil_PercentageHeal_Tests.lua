---@diagnostic disable: undefined-global
local _, ns = ...

local Tests = ns.Tests
local Feature = ns.PercentageHeal
local Core = ns.Core
if not Tests or not Feature or not Core then return end

local function runPercentageTests()
  local passed, failed = 0, 0
  local failures = {}

  local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
      passed = passed + 1
    else
      failed = failed + 1
      failures[#failures + 1] = name .. ": " .. tostring(err)
    end
  end

  local function eq(actual, expected)
    if actual ~= expected then
      error("expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
  end

  check("percentage validation accepts boundaries", function()
    eq(Feature.NormalizePercent(1), 1)
    eq(Feature.NormalizePercent(100), 100)
  end)

  check("percentage validation rejects out-of-range values", function()
    eq(Feature.NormalizePercent(0), nil)
    eq(Feature.NormalizePercent(101), nil)
    eq(Feature.NormalizePercent("abc"), nil)
  end)

  local originalState = Core.state
  local originalSetHP = Core.SetHP
  local originalSetPetHP = Core.SetPetHP

  check("character percentage heals from max HP and caps at max", function()
    local setHp, setMax
    Core.state = { hp = 10, maxHp = 200, history = {} }
    Core.SetHP = function(hp, maxHp) setHp, setMax = hp, maxHp end
    eq(Core.PercentageHeal(25), true)
    eq(setHp, 60)
    eq(setMax, 200)

    Core.state.hp = 190
    eq(Core.PercentageHeal(25), true)
    eq(setHp, 200)
  end)

  check("invalid character percentage does not mutate HP", function()
    local called = false
    Core.state = { hp = 10, maxHp = 100, history = {} }
    Core.SetHP = function() called = true end
    eq(Core.PercentageHeal(0), false)
    eq(called, false)
  end)

  check("pet percentage heals from pet max HP", function()
    local setHp, setMax
    Core.state = {
      history = {},
      pet = { enabled = true, hp = 10, maxHp = 100 },
    }
    Core.SetPetHP = function(hp, maxHp) setHp, setMax = hp, maxHp end
    eq(Core.PetPercentageHeal(50), true)
    eq(setHp, 60)
    eq(setMax, 100)
  end)

  Core.state = originalState
  Core.SetHP = originalSetHP
  Core.SetPetHP = originalSetPetHP

  local printer = rawget(_G, "print")
  if printer then
    printer(string.format("|cFF66CC66GrosOrteil/test|r Pourcentage: %d réussis, %d échecs.", passed, failed))
    for i = 1, #failures do
      printer("|cFFFF5555GrosOrteil/test|r " .. failures[i])
    end
  end

  return failed == 0
end

Feature.RunTests = runPercentageTests

if type(Tests.RunAll) == "function" then
  local originalRunAll = Tests.RunAll
  function Tests.RunAll(verbose)
    local result = originalRunAll(verbose)
    runPercentageTests()
    return result
  end
end
