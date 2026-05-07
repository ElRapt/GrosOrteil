---@diagnostic disable: undefined-global, undefined-field, lowercase-global
-- In-game test harness for GrosOrteil.
-- Trigger with /grostest. Snapshots Core.state, runs assertions, then restores.
-- Output goes to the default chat frame as a green/red pass/fail summary.
--
-- IMPORTANT: tests mutate Core.state during execution and rely on the
-- snapshot/restore wrapping to leave the user's data untouched. If you
-- abort mid-run (e.g. /reload) the saved DB will reflect the last test
-- state until next /grostest is run with reset = false.

local _, ns = ...

local Tests = {}
ns.Tests = Tests

local _G = _G
local CreateFrame        = rawget(_G, "CreateFrame")
local DEFAULT_CHAT_FRAME = rawget(_G, "DEFAULT_CHAT_FRAME")

local function colorize(s, hex) return "|cFF" .. hex .. tostring(s) .. "|r" end
local function green(s) return colorize(s, "33CC66") end
local function red(s)   return colorize(s, "E55353") end
local function gold(s)  return colorize(s, "FFCC33") end
local function gray(s)  return colorize(s, "888888") end

local function chat(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00GrosOrteil/test|r " .. tostring(msg))
  else
    print("GrosOrteil/test " .. tostring(msg))
  end
end

-- ─── Tiny test framework (in-game) ───────────────────────────────────

local suites = {}
local current

local function describe(name, fn)
  local s = { name = name, tests = {} }
  suites[#suites + 1] = s
  local prev = current
  current = s
  fn()
  current = prev
end

local function it(name, fn)
  current.tests[#current.tests + 1] = { name = name, fn = fn }
end

local function assertEq(a, b, msg)
  if a ~= b then
    error((msg or "assertEq") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
  end
end
local function assertTrue(v, msg)
  if not v then error(msg or "assertTrue", 2) end
end
local function assertFalse(v, msg)
  if v then error(msg or "assertFalse", 2) end
end
local function assertNil(v, msg)
  if v ~= nil then error((msg or "assertNil") .. ": got " .. tostring(v), 2) end
end
local function assertNotNil(v, msg)
  if v == nil then error(msg or "assertNotNil: got nil", 2) end
end

-- ─── Snapshot / restore Core.state ───────────────────────────────────

local function deepCopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, vv in pairs(v) do out[deepCopy(k, seen)] = deepCopy(vv, seen) end
  return out
end

local function snapshotState()
  if not ns.Core or not ns.Core.state then return nil end
  return deepCopy(ns.Core.state)
end

local function restoreState(snap)
  if not snap then return end
  local db = ns.GetDB and ns.GetDB() or nil
  if db then db.state = deepCopy(snap) end
  if ns.Core_Init then ns.Core_Init() end
end

-- ─── Suites ──────────────────────────────────────────────────────────

describe("smoke", function()
  it("Core, Shared, History, Comm modules exist", function()
    assertNotNil(ns.Core)
    assertNotNil(ns.Shared)
    assertNotNil(ns.History)
    assertNotNil(ns.Comm)
  end)
  it("Core.state is initialized", function()
    assertNotNil(ns.Core.state)
    assertTrue(type(ns.Core.state.maxHp) == "number" and ns.Core.state.maxHp > 0)
  end)
  it("UI frame exists after init", function()
    assertNotNil(ns.UI)
    assertNotNil(ns.UI.frame)
  end)
end)

-- Reset Core to defaults before each test. ResetToDefaults runs Core_Init
-- which clears undoStack/redoStack/prevSnapshot/undoCoalesce — this is critical
-- in-game because the undo-coalesce flag is cleared via C_Timer.After(0, ...)
-- which only fires on the next frame; without explicit reset, all mutations
-- in /grostest coalesce into one undo entry pointing at the user's pre-test
-- state and the undo test fails non-obviously.
local function reset()
  if ns.Core and ns.Core.ResetToDefaults then ns.Core.ResetToDefaults() end
end

describe("Core damage/heal", function()
  it("DamageWithArmor reduces HP by mitigated amount", function()
    reset()
    local Core = ns.Core
    Core.SetHP(100, 100); Core.SetArmor(10, 0)
    Core.DamageWithArmor(30)
    assertEq(Core.state.hp, 80)
  end)
  it("dodge cancels hits at or below dodge", function()
    reset()
    local Core = ns.Core
    Core.SetHP(100, 100); Core.SetDodge(15)
    Core.DamageWithArmor(15)
    assertEq(Core.state.hp, 100)
  end)
  it("Heal clamps to maxHp", function()
    reset()
    local Core = ns.Core
    Core.SetHP(50, 100)
    Core.Heal(9999)
    assertEq(Core.state.hp, 100)
  end)
end)

describe("Core wounds", function()
  it("hit25 sticky after dropping below 25%", function()
    reset()
    local Core = ns.Core
    Core.SetHP(20, 100)
    assertTrue(Core.state.wounds.hit25)
    Core.Heal(40)
    assertTrue(Core.state.wounds.hit25)
  end)
end)

describe("Core undo/redo", function()
  it("undo reverts a damage hit", function()
    reset()
    local Core = ns.Core
    -- After reset, default state is hp=50/50. One mutation = one undo entry.
    Core.DamageTrue(10)
    assertEq(Core.state.hp, 40)
    assertTrue(Core.CanUndo())
    Core.Undo()
    assertEq(Core.state.hp, 50)
  end)
  it("redo reapplies an undone hit", function()
    reset()
    local Core = ns.Core
    Core.DamageTrue(10)
    Core.Undo()
    assertTrue(Core.CanRedo())
    Core.Redo()
    assertEq(Core.state.hp, 40)
  end)
end)

describe("Core regeneration", function()
  it("RestoreHP clears stabilise and refills HP", function()
    reset()
    local Core = ns.Core
    Core.SetHP(0, 50); Core.SetStabilise(true)
    Core.RestoreHP()
    assertEq(Core.state.hp, 50)
    assertNil(Core.state.stabilise)
  end)
  it("DailyRegenHP grants 10% of maxHp", function()
    reset()
    local Core = ns.Core
    Core.SetHP(0, 100)
    Core.DailyRegenHP()
    assertEq(Core.state.hp, 10)
  end)
  it("DailyRegenRes grants 20% of maxRes", function()
    reset()
    local Core = ns.Core
    Core.SetRes(0, 50)
    Core.DailyRegenRes()
    assertEq(Core.state.res, 10)
  end)
end)

describe("Pet flows", function()
  it("toggle on then heal works", function()
    reset()
    local Core = ns.Core
    Core.SetPetEnabled(true)
    Core.SetPetHP(5, 20)
    Core.PetHeal(10)
    -- Hit25 sticky from 25% (5/20). Wound cap = 50% = 10. Heal to 10.
    assertEq(Core.state.pet.hp, 10)
  end)
  it("PetRestoreHP fills to maxHp", function()
    reset()
    local Core = ns.Core
    Core.SetPetEnabled(true); Core.SetPetHP(2, 25)
    Core.PetRestoreHP()
    assertEq(Core.state.pet.hp, 25)
  end)
end)

describe("Class change side-effects", function()
  it("leaving SHAMAN tears down active posture", function()
    reset()
    local Core = ns.Core
    Core.SetClassKey("SHAMAN")
    Core.SetResIndex(1, 5, 20)
    Core.SetShamanPosture("TERRE")
    assertEq(Core.state.shamanPosture, "TERRE")
    Core.SetClassKey("MAGE")
    assertNil(Core.state.shamanPosture)
  end)
  it("leaving MAGE drops mana shield", function()
    reset()
    local Core = ns.Core
    Core.SetClassKey("MAGE")
    Core.SetRes(50, 100)
    Core.SetManaShieldActive(true)
    assertTrue(Core.state.manaShield.active)
    Core.SetClassKey("ROGUE")
    assertFalse(Core.state.manaShield.active)
  end)
end)

describe("Comm round-trip", function()
  it("serialize+deserialize preserves HP and class", function()
    local Core, Comm = ns.Core, ns.Comm
    Core.SetClassKey("WARLOCK"); Core.SetHP(33, 77)
    local s = Comm.SerializeState(Core.state)
    assertNotNil(s)
    local out = Comm:DeserializeState("STATE_DATA", s, "TestPeer")
    assertNotNil(out)
    assertEq(out.hp, 33)
    assertEq(out.maxHp, 77)
    assertEq(out.classKey, "WARLOCK")
  end)
end)

describe("Slash commands", function()
  it("/go show / hide toggles UI", function()
    if not ns.UI or not ns.UI.frame then return end
    ns.UI_Show(false)
    assertFalse(ns.UI.frame:IsShown())
    ns.UI_Show(true)
    assertTrue(ns.UI.frame:IsShown())
  end)
end)

-- ─── Runner ──────────────────────────────────────────────────────────

local function runOne(t)
  local ok, err = pcall(t.fn)
  return ok, err
end

function Tests.RunAll(verbose)
  local snap = snapshotState()
  local pass, fail, failures = 0, 0, {}

  chat(gold("running test suite…"))
  for _, s in ipairs(suites) do
    if verbose then chat(gray("[" .. s.name .. "]")) end
    for _, t in ipairs(s.tests) do
      local ok, err = runOne(t)
      if ok then
        pass = pass + 1
        if verbose then chat("  " .. green("PASS") .. " " .. t.name) end
      else
        fail = fail + 1
        failures[#failures + 1] = { suite = s.name, test = t.name, err = err }
        chat("  " .. red("FAIL") .. " " .. s.name .. " :: " .. t.name)
        chat("        " .. tostring(err))
      end
    end
  end

  -- Always restore, even if a test threw.
  restoreState(snap)

  if fail == 0 then
    chat(green(string.format("✓ all %d tests passed", pass)))
  else
    chat(red(string.format("✗ %d failed, %d passed", fail, pass)))
  end
  return fail == 0, pass, fail, failures
end

-- ─── Slash command ───────────────────────────────────────────────────

local function ensureSlash()
  _G.SLASH_GROSORTEILTEST1 = "/grostest"
  _G.SLASH_GROSORTEILTEST2 = "/got"
  _G.SlashCmdList["GROSORTEILTEST"] = function(msg)
    local arg = ((msg or ""):match("^%s*(%S*)") or ""):lower()
    Tests.RunAll(arg == "v" or arg == "-v" or arg == "verbose")
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() ensureSlash() end)
