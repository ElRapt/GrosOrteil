---@diagnostic disable: undefined-global
local _, ns = ...

-- Live synchronization for the raid-panel damage/heal meter.
--
-- The regular STATE_DATA protocol is request/response and backed by the target
-- popup's 60-second cache. That is appropriate for character-sheet inspection,
-- but it left the meter displaying whatever snapshot each viewer happened to
-- have requested last. Two players could therefore keep different meter values
-- indefinitely, and a local reset could permanently preserve that difference in
-- their baselines.
--
-- MeterSync keeps only the two running counters live. Counters are authoritative
-- on their owner's client and are broadcast when they change. Opening/refreshing
-- the raid panel also requests the current counters alongside STATE_DATA, so a
-- missed broadcast heals itself without sending full state continuously.
--
-- No Blizzard unit state is written or hooked. The module only sends addon
-- messages and overlays the two meter numbers on states returned from our own
-- cache accessor.

local MeterSync = {}
ns.MeterSync = MeterSync

local Comm   = ns.Comm
local Core   = ns.Core
local Popup  = ns.TargetPopup
local Shared = ns.Shared

local _G = _G
local type     = type
local tonumber = tonumber
local tostring = tostring
local math     = math
local rawget   = rawget

MeterSync.STATE_CMD   = "METER_STATE"
MeterSync.REQUEST_CMD = "METER_REQUEST"

local totalsByKey = {}
local lastDmg, lastHeal

local function normalize(name)
  return Shared and Shared.NormalizeNameKey and Shared.NormalizeNameKey(name) or nil
end

local function sanitize(v)
  v = tonumber(v) or 0
  if v < 0 then return 0 end
  return math.floor(v + 0.5)
end

local function readLocalTotals()
  local state = Core and Core.state
  local meter = type(state) == "table" and type(state.meter) == "table" and state.meter or nil
  return sanitize(meter and meter.dmg), sanitize(meter and meter.heal)
end

local function send(msg, channel, target)
  local ctl = rawget(_G, "ChatThrottleLib")
  local chat = rawget(_G, "C_ChatInfo")
  if ctl and ctl.SendAddonMessage then
    ctl:SendAddonMessage("NORMAL", Comm.PREFIX, msg, channel, target)
  elseif chat and chat.SendAddonMessage then
    chat.SendAddonMessage(Comm.PREFIX, msg, channel, target)
  end
end

local function groupChannel()
  local isInRaid  = rawget(_G, "IsInRaid")
  local isInGroup = rawget(_G, "IsInGroup")
  if isInRaid and isInRaid() then return "RAID" end
  if isInGroup and isInGroup() then return "PARTY" end
  return nil
end

function MeterSync.Store(sender, dmg, heal)
  local key = normalize(sender)
  if not key then return false end
  totalsByKey[key] = { dmg = sanitize(dmg), heal = sanitize(heal) }
  return true
end

function MeterSync.Get(sender)
  local key = normalize(sender)
  return key and totalsByKey[key] or nil
end

function MeterSync.SendState(target)
  local dmg, heal = readLocalTotals()
  local msg = string.format("%s:%d:%d", MeterSync.STATE_CMD, dmg, heal)
  if type(target) == "string" and target ~= "" then
    send(msg, "WHISPER", target)
    return true
  end
  local channel = groupChannel()
  if not channel then return false end
  send(msg, channel)
  return true
end

function MeterSync.Request(target)
  if type(target) ~= "string" or target == "" then return false end
  send(MeterSync.REQUEST_CMD, "WHISPER", target)
  return true
end

function MeterSync.BroadcastIfChanged(force)
  local dmg, heal = readLocalTotals()
  if not force and dmg == lastDmg and heal == lastHeal then return false end
  lastDmg, lastHeal = dmg, heal
  return MeterSync.SendState()
end

function MeterSync.OnAddonMessage(msg, sender)
  if msg == MeterSync.REQUEST_CMD then
    MeterSync.SendState(sender)
    return true
  end

  local dmg, heal = type(msg) == "string"
    and msg:match("^" .. MeterSync.STATE_CMD .. ":(%d+):(%d+)$")
  if dmg and heal then
    MeterSync.Store(sender, dmg, heal)
    -- State-arrival callbacks drive RaidPanel relayouts. Reuse that path when
    -- possible so a live counter update redraws the meter immediately.
    if Popup and Popup.OnStateReceived and Popup.GetCachedState then
      local cached = Popup.GetCachedState(sender)
      if cached then Popup:OnStateReceived(sender, cached) end
    end
    return true
  end
  return false
end

-- Merge authoritative live meter totals into state reads without mutating the
-- cached STATE_DATA table. This keeps the target-popup cache semantics intact.
if Popup and Popup.GetCachedState then
  local originalGetCachedState = Popup.GetCachedState
  Popup.GetCachedState = function(name)
    local state = originalGetCachedState(name)
    local live = MeterSync.Get(name)
    if not state or not live then return state end
    local proxy = {}
    for k, v in pairs(state) do proxy[k] = v end
    proxy.meter = { dmg = live.dmg, heal = live.heal }
    return proxy
  end
end

-- Extend the existing comm dispatcher before Comm:Initialize installs its event
-- callback. Unknown meter messages are consumed here; every existing command is
-- delegated unchanged.
if Comm and Comm.OnChatMsgAddon then
  local originalOnChatMsgAddon = Comm.OnChatMsgAddon
  Comm.OnChatMsgAddon = function(self, prefixMsg, msg, channel, sender)
    if prefixMsg == self.PREFIX and MeterSync.OnAddonMessage(msg, sender) then return end
    return originalOnChatMsgAddon(self, prefixMsg, msg, channel, sender)
  end
end

-- A normal panel refresh already requests STATE_DATA from every member. Pair it
-- with a tiny meter request so opening the panel repairs any missed broadcasts.
if Comm and Comm.RequestState then
  local originalRequestState = Comm.RequestState
  Comm.RequestState = function(self, targetPlayer)
    originalRequestState(self, targetPlayer)
    MeterSync.Request(targetPlayer)
  end
end

-- Local meter counters only change through Core mutations. Broadcast after the
-- mutation has completed; unrelated sheet changes are ignored by value check.
if Core and Core.OnChange then
  Core.OnChange(function()
    MeterSync.BroadcastIfChanged(false)
  end)
end

-- Announce on world/group transitions as a recovery path for clients that join
-- after the latest counter mutation. This is read-only with respect to Blizzard
-- state and uses the existing addon prefix.
local CreateFrame = rawget(_G, "CreateFrame")
if CreateFrame then
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("GROUP_ROSTER_UPDATE")
  frame:SetScript("OnEvent", function()
    MeterSync.BroadcastIfChanged(true)
  end)
  MeterSync.eventFrame = frame
end

MeterSync._totalsByKey = totalsByKey
