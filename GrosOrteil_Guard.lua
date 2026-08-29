---@diagnostic disable: undefined-global
-- Runtime guards for communication validation and realm-safe remote identity.
-- Loaded after Comm/TargetPopup/Heal/MeterSync/RaidPanel, before PLAYER_LOGIN.
-- It intentionally avoids replacing Blizzard globals or changing secure frames.
local _, ns = ...

local Shared = ns.Shared
local Comm = ns.Comm
local Popup = ns.TargetPopup
local Heal = ns.Heal
local MeterSync = ns.MeterSync

local type, tonumber = type, tonumber
local math, pairs, rawget = math, pairs, rawget

local Guard = {}
ns.Guard = Guard

-- Realm-aware remote identity registry.
-- RaidPanel's protected click path keeps Blizzard unit tokens untouched. Remote
-- addon-message senders normally arrive as Name-Realm. Track those exact
-- identities and refuse ambiguous short-name lookups instead of associating
-- one realm's state/heal response with another realm's character.
local exactByShort = {}

local function identityKey(name)
  if Shared and Shared.IsSecret and Shared.IsSecret(name) then return nil end
  if type(name) ~= "string" or name == "" then return nil end
  local compact = name:lower():gsub("%s+", "")
  if compact == "" then return nil end
  return compact
end

local function shortKey(name)
  local key = identityKey(name)
  if not key then return nil end
  return key:match("^([^%-]+)") or key
end

local function observeIdentity(name)
  local full = identityKey(name)
  local short = shortKey(name)
  if not full or not short or not full:find("-", 1, true) then return end
  local set = exactByShort[short]
  if not set then set = {}; exactByShort[short] = set end
  set[full] = true
end

local function uniqueObservedIdentity(name)
  local full = identityKey(name)
  if not full then return nil end
  if full:find("-", 1, true) then return full end
  local set = exactByShort[full]
  if not set then return full end
  local only, count
  for key in pairs(set) do
    only, count = key, (count or 0) + 1
    if count > 1 then return nil end
  end
  return only or full
end

local function isAmbiguousShort(name)
  local key = identityKey(name)
  if not key or key:find("-", 1, true) then return false end
  local set = exactByShort[key]
  if not set then return false end
  local count = 0
  for _ in pairs(set) do
    count = count + 1
    if count > 1 then return true end
  end
  return false
end

Guard.IdentityKey = identityKey
Guard.ObserveIdentity = observeIdentity
Guard.UniqueObservedIdentity = uniqueObservedIdentity
Guard.IsAmbiguousShort = isAmbiguousShort
Guard._exactByShort = exactByShort

-- MeterSync used Shared.NormalizeNameKey, which deliberately strips realms.
-- Keep an exact side-cache while retaining its existing broadcast/recovery flow.
if MeterSync and MeterSync.Store and MeterSync.Get then
  local exactMeterTotals = {}
  local originalStore = MeterSync.Store
  local originalGet = MeterSync.Get

  MeterSync.Store = function(sender, dmg, heal)
    observeIdentity(sender)
    local key = identityKey(sender)
    if key then
      exactMeterTotals[key] = {
        dmg = math.max(0, math.floor(tonumber(dmg) or 0)),
        heal = math.max(0, math.floor(tonumber(heal) or 0)),
      }
    end
    return originalStore(sender, dmg, heal)
  end

  MeterSync.Get = function(sender)
    local resolved = uniqueObservedIdentity(sender)
    if not resolved then return nil end
    return exactMeterTotals[resolved] or originalGet(sender)
  end

  Guard._exactMeterTotals = exactMeterTotals
end

-- Maintain a realm-safe cache in front of TargetPopup's legacy short-name
-- cache. Exact Name-Realm reads never collide. A short-name read is allowed
-- only when the observed identity is unique; otherwise it fails closed.
if Popup and Popup.OnStateReceived and Popup.GetCachedState and Popup.InjectState then
  local exactStateCache = {}
  local originalOnStateReceived = Popup.OnStateReceived
  local originalGetCachedState = Popup.GetCachedState
  local originalInjectState = Popup.InjectState

  local function withLiveMeter(state, name)
    local live = MeterSync and MeterSync.Get and MeterSync.Get(name) or nil
    if not state or not live then return state end
    local proxy = {}
    for k, v in pairs(state) do proxy[k] = v end
    proxy.meter = { dmg = live.dmg, heal = live.heal }
    return proxy
  end

  Popup.OnStateReceived = function(self, sender, state)
    observeIdentity(sender)
    local key = identityKey(sender)
    if key and type(state) == "table" then exactStateCache[key] = state end
    return originalOnStateReceived(self, sender, state)
  end

  Popup.GetCachedState = function(name)
    local resolved = uniqueObservedIdentity(name)
    if not resolved then return nil end
    local state = exactStateCache[resolved]
    if state then return withLiveMeter(state, resolved) end
    return originalGetCachedState(name)
  end

  Popup.InjectState = function(name, state)
    observeIdentity(name)
    local key = identityKey(name)
    if key and type(state) == "table" then exactStateCache[key] = state end
    return originalInjectState(name, state)
  end

  Guard._exactStateCache = exactStateCache
end

-- Bound multipart work and memory before delegating to the existing assembler.
local MAX_PARTS = 64
local MAX_PART_BYTES = 220
local MAX_TOTAL_BYTES = 14000
local PARTIAL_TTL = 30

local function now()
  local getTime = rawget(_G, "GetTime")
  return (getTime and getTime()) or 0
end

local function prunePartialMessages(comm)
  if not comm or type(comm.partialMessages) ~= "table" then return end
  local t = now()
  for key, entry in pairs(comm.partialMessages) do
    if type(entry) ~= "table" or type(entry.start) ~= "number"
        or (t - entry.start) > PARTIAL_TTL then
      comm.partialMessages[key] = nil
    end
  end
end

local function validMultipartPayload(payload)
  if type(payload) ~= "table" then return false end
  local total = tonumber(payload.total)
  local index = tonumber(payload.index)
  local part = payload.data
  if not total or total ~= math.floor(total) or total < 1 or total > MAX_PARTS then return false end
  if not index or index ~= math.floor(index) or index < 1 or index > total then return false end
  if type(part) ~= "string" or #part > MAX_PART_BYTES then return false end
  return true
end

if Comm and Comm.DeserializeState and Comm.OnChatMsgAddon then
  local originalDeserializeState = Comm.DeserializeState
  local originalOnChatMsgAddon = Comm.OnChatMsgAddon

  Comm.DeserializeState = function(self, cmd, payload, sender)
    prunePartialMessages(self)
    if cmd == "STATE_DATA_PART" or cmd == "STATE_DATA_COMPRESSED_PART" then
      if not validMultipartPayload(payload) then return nil end
      local existing = type(self.partialMessages) == "table" and self.partialMessages[sender or "?"] or nil
      local bytes = #payload.data
      if type(existing) == "table" and type(existing.parts) == "table" then
        bytes = 0
        for i = 1, math.min(tonumber(existing.total) or 0, MAX_PARTS) do
          local p = existing.parts[i]
          if type(p) == "string" then bytes = bytes + #p end
        end
        if not existing.parts[payload.index] then bytes = bytes + #payload.data end
      end
      if bytes > MAX_TOTAL_BYTES then
        if type(self.partialMessages) == "table" then self.partialMessages[sender or "?"] = nil end
        return nil
      end
    end
    return originalDeserializeState(self, cmd, payload, sender)
  end

  Comm.OnChatMsgAddon = function(self, prefixMsg, msg, channel, sender)
    if prefixMsg == self.PREFIX then
      if Shared and Shared.IsSecret and Shared.IsSecret(sender) then return end
      if type(sender) ~= "string" or sender == "" or #sender > 128 then return end
      observeIdentity(sender)
      prunePartialMessages(self)
    end
    return originalOnChatMsgAddon(self, prefixMsg, msg, channel, sender)
  end
end

Guard.ValidMultipartPayload = validMultipartPayload
Guard.PrunePartialMessages = prunePartialMessages
Guard.MAX_PARTS = MAX_PARTS

-- Mirror pending heal requests so unsolicited/duplicate responses are ignored
-- and an accepted response can never credit more healing than was requested.
if Heal and Heal.MarkPending and Heal.ClearPending and Heal.SendRequest and Heal.OnResponse then
  local pendingMirror = {}
  local originalMarkPending = Heal.MarkPending
  local originalClearPending = Heal.ClearPending
  local originalSendRequest = Heal.SendRequest
  local originalOnResponse = Heal.OnResponse

  local function pendingLookup(name)
    local exact = identityKey(name)
    if not exact then return nil, nil end
    local entry = pendingMirror[exact]
    if entry then return exact, entry end
    local short = shortKey(name)
    if not short or isAmbiguousShort(short) then return nil, nil end
    entry = pendingMirror[short]
    return entry and short or nil, entry
  end

  Heal.MarkPending = function(target, amount, t, toPet)
    local key = identityKey(target)
    if key then pendingMirror[key] = { amount = tonumber(amount) or 0, pet = not not toPet } end
    return originalMarkPending(target, amount, t, toPet)
  end

  Heal.ClearPending = function(target)
    local exact = identityKey(target)
    local short = shortKey(target)
    if exact then pendingMirror[exact] = nil end
    if short and not isAmbiguousShort(short) then pendingMirror[short] = nil end
    return originalClearPending(target)
  end

  Heal.SendRequest = function(target, amount, toPet)
    if isAmbiguousShort(target) then return false end
    return originalSendRequest(target, amount, toPet)
  end

  Heal.OnResponse = function(self, target, accepted, amount)
    local key, pending = pendingLookup(target)
    if not pending then return false end
    local reported = tonumber(amount) or 0
    if reported < 0 then reported = 0 end
    local requested = math.max(0, tonumber(pending.amount) or 0)
    if reported > requested then reported = requested end
    if key then pendingMirror[key] = nil end
    originalOnResponse(self, target, accepted, reported)
    return true
  end

  Guard._pendingHeals = pendingMirror
  Guard.FindPendingHeal = pendingLookup
end
