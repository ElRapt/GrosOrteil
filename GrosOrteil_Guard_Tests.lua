---@diagnostic disable: undefined-global
local _, ns = ...

local Tests = ns.Tests
local Guard = ns.Guard
local Comm = ns.Comm
local Heal = ns.Heal
local Core = ns.Core
local MeterSync = ns.MeterSync
if not Tests or not Guard then return end

local function runGuardTests()
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

  check("multipart bounds reject hostile totals and indexes", function()
    eq(Guard.ValidMultipartPayload({ total = Guard.MAX_PARTS + 1, index = 1, data = "x" }), false)
    eq(Guard.ValidMultipartPayload({ total = 2, index = 3, data = "x" }), false)
    eq(Guard.ValidMultipartPayload({ total = 2, index = 1, data = string.rep("x", 221) }), false)
    eq(Guard.ValidMultipartPayload({ total = 2, index = 1, data = "x" }), true)
  end)

  check("hostile multipart never reaches the legacy large scan", function()
    if not Comm then return end
    local out = Comm:DeserializeState("STATE_DATA_PART", {
      total = 1000000000,
      index = 1,
      data = "x",
    }, "GuardPeer-Realm")
    eq(out, nil)
  end)

  check("realm identities fail closed when short name is ambiguous", function()
    Guard.ObserveIdentity("Guardalice-RealmOne")
    eq(Guard.UniqueObservedIdentity("Guardalice"), "guardalice-realmone")
    Guard.ObserveIdentity("Guardalice-RealmTwo")
    eq(Guard.UniqueObservedIdentity("Guardalice"), nil)
    eq(Guard.IsAmbiguousShort("Guardalice"), true)
    eq(Guard.UniqueObservedIdentity("Guardalice-RealmOne"), "guardalice-realmone")
  end)

  check("meter totals stay separate for same short name on different realms", function()
    if not MeterSync then return end
    MeterSync.Store("Guardmeter-RealmOne", 10, 20)
    MeterSync.Store("Guardmeter-RealmTwo", 30, 40)
    eq(MeterSync.Get("Guardmeter-RealmOne").dmg, 10)
    eq(MeterSync.Get("Guardmeter-RealmTwo").dmg, 30)
    eq(MeterSync.Get("Guardmeter"), nil)
  end)

  check("unsolicited heal response is ignored", function()
    if not Heal or not Core then return end
    local originalCredit = Core.CreditHealGiven
    local credited = 0
    Core.CreditHealGiven = function(amount) credited = credited + (tonumber(amount) or 0) end
    local ok, err = pcall(function()
      eq(Heal:OnResponse("Guardforged-Realm", true, 999999), false)
      eq(credited, 0)
    end)
    Core.CreditHealGiven = originalCredit
    if not ok then error(err, 0) end
  end)

  check("heal response credit is capped to requested amount", function()
    if not Heal or not Core then return end
    local originalCredit = Core.CreditHealGiven
    local credited = 0
    Core.CreditHealGiven = function(amount) credited = credited + (tonumber(amount) or 0) end
    local ok, err = pcall(function()
      Heal.MarkPending("Guardheal-Realm", 25, 0, false)
      eq(Heal:OnResponse("Guardheal-Realm", true, 999999), true)
      eq(credited, 25)
      eq(Heal:OnResponse("Guardheal-Realm", true, 25), false)
      eq(credited, 25)
    end)
    Heal.ClearPending("Guardheal-Realm")
    Core.CreditHealGiven = originalCredit
    if not ok then error(err, 0) end
  end)

  local printer = rawget(_G, "print")
  if printer then
    printer(string.format("|cFF66CC66GrosOrteil/test|r Guards: %d réussis, %d échecs.", passed, failed))
    for i = 1, #failures do
      printer("|cFFFF5555GrosOrteil/test|r " .. failures[i])
    end
  end
  return failed == 0, passed, failed, failures
end

Guard.RunTests = runGuardTests

if type(Tests.RunAll) == "function" then
  local originalRunAll = Tests.RunAll
  function Tests.RunAll(verbose)
    local result, passed, failed, failures = originalRunAll(verbose)
    local guardResult, guardPassed, guardFailed, guardFailures = runGuardTests()
    failures = failures or {}
    for i = 1, #(guardFailures or {}) do
      failures[#failures + 1] = { suite = "Guard", test = "hardening", err = guardFailures[i] }
    end
    return result and guardResult,
      (passed or 0) + (guardPassed or 0),
      (failed or 0) + (guardFailed or 0),
      failures
  end
end
