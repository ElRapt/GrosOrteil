---@diagnostic disable: undefined-global, lowercase-global
-- Minimal WoW API stubs so addon files can load and run pure-logic tests.
-- Only stubs what the addon's non-UI code actually touches. Extend as needed.
-- Run from a standalone Lua interpreter, NOT from inside WoW.

local M = {}

-- Reset between test runs to keep state hermetic.
function M.install()
  -- Wipe any saved DBs so each Core_Init() starts clean.
  rawset(_G, "GrosOrteilDB", nil)
  rawset(_G, "GrosOrteilDBPC", nil)

  -- Time helpers.
  -- M.fakeNow lets tests force a deterministic timestamp without re-binding
  -- _G.GetTime (Comm.lua captures it at file load via rawget so a re-bind is
  -- invisible to module code). Set M.fakeNow to a number to override; nil =
  -- normal os.clock-driven timing.
  M.fakeNow = nil
  _G.GetTime = function() return M.fakeNow or os.clock() end
  _G.time = os.time
  _G.date = os.date

  -- WoW string utility used by Comm and LibStub.
  _G.strsplit = function(sep, s, n)
    if type(s) ~= "string" then return s end
    local parts = {}
    local start = 1
    while true do
      if n and #parts == n - 1 then
        parts[#parts + 1] = s:sub(start)
        break
      end
      local i, j = s:find(sep, start, true)
      if not i then parts[#parts + 1] = s:sub(start); break end
      parts[#parts + 1] = s:sub(start, i - 1)
      start = j + 1
    end
    return (table.unpack or unpack)(parts)
  end
  _G.strmatch = string.match
  _G.strfind = string.find
  _G.strsub = string.sub
  _G.strlen = string.len
  _G.format = string.format

  -- Bit lib used by LibDeflate. Lua 5.4 has no built-in bit library; provide bit32-shim.
  if not _G.bit then
    local bit = {}
    function bit.bxor(a, b)
      local r, p = 0, 1
      for _ = 1, 32 do
        local ab, bb = a % 2, b % 2
        if ab ~= bb then r = r + p end
        a = (a - ab) / 2; b = (b - bb) / 2; p = p * 2
      end
      return r
    end
    function bit.band(a, b)
      local r, p = 0, 1
      for _ = 1, 32 do
        local ab, bb = a % 2, b % 2
        if ab == 1 and bb == 1 then r = r + p end
        a = (a - ab) / 2; b = (b - bb) / 2; p = p * 2
      end
      return r
    end
    function bit.bor(a, b)
      local r, p = 0, 1
      for _ = 1, 32 do
        local ab, bb = a % 2, b % 2
        if ab == 1 or bb == 1 then r = r + p end
        a = (a - ab) / 2; b = (b - bb) / 2; p = p * 2
      end
      return r
    end
    function bit.lshift(a, n) return (a * (2 ^ n)) % (2 ^ 32) end
    function bit.rshift(a, n) return math.floor(a / (2 ^ n)) end
    function bit.bnot(a) return bit.bxor(a, 0xFFFFFFFF) end
    _G.bit = bit
  end

  -- Unit info — keep simple and deterministic.
  _G.UnitClass = function(_) return "Mage", "MAGE" end
  _G.UnitName = function(_) return "TestPlayer", "TestRealm" end
  _G.UnitFullName = function(_) return "TestPlayer", "TestRealm" end
  _G.UnitExists = function(_) return true end
  _G.UnitIsPlayer = function(_) return true end
  _G.UnitGUID = function(_) return "Player-1-00000001" end
  _G.IsInRaid = function() return false end
  _G.IsInGroup = function() return false end

  -- Sound stubs — silent.
  _G.PlaySound = function() end
  _G.PlaySoundFile = function() end
  _G.SOUNDKIT = setmetatable({}, { __index = function() return 1 end })

  -- Error handler in WoW *logs* the error but does not re-throw. Mirroring
  -- that here lets us exercise pcall-protected paths (e.g. listener fan-out)
  -- without test framework hijacking the error. Captured errors are exposed
  -- via M.errorHandlerCalls for assertions when needed.
  M.errorHandlerCalls = {}
  _G.geterrorhandler = function()
    return function(e)
      M.errorHandlerCalls[#M.errorHandlerCalls + 1] = tostring(e)
    end
  end

  -- Addon messaging — record outgoing messages for assertions.
  M.sentMessages = {}
  _G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(_) return true end,
    SendAddonMessage = function(prefix, msg, channel, target)
      M.sentMessages[#M.sentMessages + 1] = {
        prefix = prefix, msg = msg, channel = channel, target = target,
      }
      return true
    end,
  }

  -- Timers fire synchronously so tests are deterministic.
  _G.C_Timer = {
    After = function(_, cb) if type(cb) == "function" then cb() end end,
    NewTicker = function() return { Cancel = function() end } end,
  }

  -- UIParent: a minimal frame so layout calls don't blow up.
  _G.UIParent = M.makeFrame()

  -- CreateFrame: returns a table where any method is a chainable no-op.
  _G.CreateFrame = function(_, _, _, _) return M.makeFrame() end

  -- Misc
  _G.GameTooltip = M.makeFrame()
  _G.MAX_PARTY_MEMBERS = 4
  _G.UISpecialFrames = {}
  _G.GetCVar = function() return "" end
  _G.print = print
end

-- A frame mock that responds to any method as a chainable no-op.
function M.makeFrame()
  local f = {}
  local children = {}
  f._isFrame = true

  local meta = {
    __index = function(_, k)
      -- Accessors used widely return sensible defaults.
      if k == "GetWidth" or k == "GetHeight" then return function() return 100 end end
      if k == "GetParent" then return function() return _G.UIParent end end
      if k == "IsShown" or k == "IsVisible" or k == "IsMouseOver" then return function() return false end end
      if k == "GetName" then return function() return nil end end
      if k == "GetObjectType" then return function() return "Frame" end end
      if k == "GetText" then return function() return "" end end
      if k == "GetNumber" then return function() return 0 end end
      if k == "GetCenter" then return function() return 0, 0 end end
      if k == "GetLeft" or k == "GetRight" or k == "GetTop" or k == "GetBottom" then return function() return 0 end end
      if k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine" then
        return function()
          local child = M.makeFrame()
          children[#children + 1] = child
          return child
        end
      end
      -- Default: any other method is a no-op returning the frame for chaining.
      return function(self) return self end
    end,
  }
  return setmetatable(f, meta)
end

return M
