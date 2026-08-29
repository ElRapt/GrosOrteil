---@diagnostic disable: undefined-global
-- Offline test runner. Run from the addon root:
--   lua tests/run.lua            (quiet)
--   lua tests/run.lua -v         (verbose)
-- Exits with status 0 if all tests pass, 1 otherwise.

-- Make tests/ resolvable as `require("...")` no matter where lua was invoked from.
local function thisDir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  return src:match("^(.+)[/\\][^/\\]+$") or "."
end
local TESTS_DIR = thisDir()
local sep = package.config:sub(1, 1)
package.path = TESTS_DIR .. sep .. "?.lua;" .. package.path

local mocks = require("mocks")
mocks.install()

local load = require("load")
local ns = load.load()

-- Make ns and mocks available to test files.
_G.NS = ns
_G.MOCKS = mocks
_G.T = require("framework")

-- Register test files. Add new ones to this list.
local TESTS = {
  "test_shared",
  "test_history",
  "test_core",
  "test_grimoire",
  "test_comm",
  "test_popup",
  "test_raid_panel",
  "test_raid_meter",
  "test_meter_sync",
  "test_heal",
  "test_e2e",         -- big cross-feature scenario tests
  "test_invariants",  -- runs last: deliberately abuses Core, leaves messy state
}

for _, name in ipairs(TESTS) do
  require(name)
end

local verbose = false
for _, a in ipairs(arg or {}) do
  if a == "-v" or a == "--verbose" then verbose = true end
end

local ok = _G.T.run({ verbose = verbose })
os.exit(ok and 0 or 1)
