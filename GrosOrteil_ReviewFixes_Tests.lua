---@diagnostic disable: undefined-global
local _, ns = ...

local Tests = ns.Tests
local Fixes = ns.ReviewFixes
local Comm = ns.Comm
local Heal = ns.Heal
local Core = ns.Core
local MeterSync = ns.MeterSync
if not Tests or not Fixes then return end

local function runReviewFixTests()
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
    eq(Fixes.ValidMultipartPayload({ total = Fixes.MAX_PARTS + 1, index = 1, data = "x" }), false)
    eq(Fixes.ValidMultipartPayload({ total = 2, index = 3, data = "x" }), false)
    eq(Fixes.ValidMultipartPayload({ total = 2, index = 1, data = string.rep("x", 221) }), false)
    eq(Fixes.ValidMultipartPayload({ total = 2, index = 1, data = "x" }), true)
  end)

  check("hostile multipart never reaches the legacy large scan", function()
    if not Comm then return end
    local out = Comm:DeserializeState("STATE_DATA_PART", {
      total = 1000000000,
      index = 1,
      data = "x",
    }, "ReviewPeer-Realm")
    eq(out, nil)
  end)

  check("realm identities fail closed when short name is ambiguous", function()
    Fixes.ObserveIdentity("Reviewalice-RealmOne")
    eq(Fixes.UniqueObservedIdentity("Reviewalice"), "reviewalice-realmone")
    Fixes.ObserveIdentity("Reviewalice-RealmTwo")
    eq(Fixes.UniqueObservedIdentity("Reviewalice"), nil)
    eq(Fixes.IsAmbiguousShort("Reviewalice"), true)
    eq(Fixes.UniqueObservedIdentity("Reviewalice-RealmOne"), "reviewalice-realmone")
  end)

  check("meter totals stay separate for same short name on different realms", function()
    if not MeterSync then return end
    MeterSync.Store("Reviewmeter-RealmOne", 10, 20)
    MeterSync.Store("Reviewmeter-RealmTwo", 30, 40)
    eq(MeterSync.Get("Reviewmeter-RealmOne").dmg, 10)
    eq(MeterSync.Get("Reviewmeter-RealmTwo").dmg, 30)
    eq(MeterSync.Get("Reviewmeter"), nil)
  end)

  check("unsolicited heal response is ignored", function()
    if not Heal or not Core then return end
    local originalCredit = Core.CreditHealGiven
    local credited = 0
    Core.CreditHealGiven = function(amount) credited = credited + (tonumber(amount) or 0) end
    local ok, err = pcall(function()
      eq(Heal:OnResponse("Reviewforged-Realm", true, 999999), false)
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
      Heal.MarkPending("Reviewheal-Realm", 25, 0, false)
      eq(Heal:OnResponse("Reviewheal-Realm", true, 999999), true)
      eq(credited, 25)
      eq(Heal:OnResponse("Reviewheal-Realm", true, 25), false)
      eq(credited, 25)
    end)
    Heal.ClearPending("Reviewheal-Realm")
    Core.CreditHealGiven = originalCredit
    if not ok then error(err, 0) end
  end)

  local printer = rawget(_G, "print")
  if printer then
    printer(string.format("|cFF66CC66GrosOrteil/test|r Review fixes: %d réussis, %d échecs.", passed, failed))
    for i = 1, #failures do
      printer("|cFFFF5555GrosOrteil/test|r " .. failures[i])
    end
  end
  return failed == 0
end

Fixes.RunTests = runReviewFixTests

if type(Tests.RunAll) == "function" then
  local originalRunAll = Tests.RunAll
  function Tests.RunAll(verbose)
    local result, passed, failed, failures = originalRunAll(verbose)
    local reviewResult = runReviewFixTests()
    return result and reviewResult, passed, failed, failures
  end
end
