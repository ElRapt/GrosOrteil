---@diagnostic disable: undefined-global
-- Loads the addon's source files into a fake namespace, simulating
-- WoW's `local addonName, ns = ...` calling convention. Returns ns.
-- Run from a standalone Lua interpreter, NOT from inside WoW.

local M = {}

-- Resolve project root (parent of tests/).
local function getProjectRoot()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  -- src is .../tests/load.lua → strip last two components.
  local sep = src:find("[/\\][^/\\]+[/\\][^/\\]+$")
  if not sep then return "." end
  return src:sub(1, sep - 1)
end

M.ROOT = getProjectRoot()

local function pathJoin(...)
  return table.concat({...}, package.config:sub(1, 1))
end

-- Load a Lua file and call it with (addonName, ns) so `local _, ns = ...` works.
local function loadAs(path, addonName, ns)
  local chunk, err = loadfile(path)
  if not chunk then error("loadfile failed for " .. path .. ": " .. tostring(err)) end
  return chunk(addonName, ns)
end

-- Libraries the Comm layer depends on. Loaded into _G so LibStub:GetLibrary works.
local LIBS = {
  "Libs/LibStub/LibStub.lua",
  "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
  "Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua",
  "Libs/AceSerializer-3.0/AceSerializer-3.0.lua",
  "Libs/LibDeflate/LibDeflate.lua",
}

-- Addon source files in dependency order. Skip Main.lua (wires WoW events
-- and slash commands we don't run) and the main UI/tabs files (heavy frame
-- work that needs deeper mocks). TargetPopup loads OK against the frame
-- stub because all its UI work is lazy-deferred to PLAYER_LOGIN events
-- we never fire.
local SOURCES = {
  "GrosOrteil_Shared.lua",
  "GrosOrteil_History.lua",
  "GrosOrteil_Core.lua",
  "GrosOrteil_GMMarkers.lua",
  "GrosOrteil_Comm.lua",
  "GrosOrteil_TargetPopup.lua",
}

function M.load()
  local ns = {}
  -- Stand in for ns.GetDB so Core_Init has a savedvars target.
  rawset(_G, "GrosOrteilDB", {})
  rawset(_G, "GrosOrteilDBPC", {})
  ns.db = _G.GrosOrteilDBPC
  ns.GetDB = function() return ns.db end

  local sep = package.config:sub(1, 1)
  for _, rel in ipairs(LIBS) do
    local relNative = (rel:gsub("/", sep))
    local p = pathJoin(M.ROOT, relNative)
    -- Libraries don't use the (addonName, ns) signature, but passing args is harmless.
    loadAs(p, "GrosOrteil", ns)
  end

  for _, rel in ipairs(SOURCES) do
    local p = pathJoin(M.ROOT, rel)
    loadAs(p, "GrosOrteil", ns)
  end

  if type(ns.Core_Init)       == "function" then ns.Core_Init() end
  if type(ns.GMMarkers_Init)  == "function" then ns.GMMarkers_Init() end
  if type(ns.Comm_Init)       == "function" then ns.Comm_Init() end
  return ns
end

return M
