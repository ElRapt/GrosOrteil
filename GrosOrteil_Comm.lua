---@diagnostic disable: undefined-global, unused-local
local _, ns = ...

local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "GO_STATE"
Comm.REQUEST_TIMEOUT = 5

local _G = _G
local type = type
local tonumber = tonumber
local strsplit = rawget(_G, "strsplit")
local GetTime = rawget(_G, "GetTime")
local CreateFrame = rawget(_G, "CreateFrame")
local UnitClass = rawget(_G, "UnitClass")
local C_ChatInfo = rawget(_G, "C_ChatInfo")
local ChatThrottleLib = rawget(_G, "ChatThrottleLib")
local LibStub = rawget(_G, "LibStub")
local tostring = tostring
local string = string
local math = math

local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
local LibDeflate = LibStub and LibStub("LibDeflate", true)

local function dbg(fmt, ...)
  local _ = fmt
  select("#", ...)
  return
end

local function sendAddonMessage(prefix, msg, channel, target)
  dbg(
    "SendAddonMessage prefix=%s channel=%s target=%s bytes=%d",
    tostring(prefix),
    tostring(channel),
    tostring(target),
    #(msg or "")
  )
  if ChatThrottleLib and ChatThrottleLib.SendAddonMessage then
    dbg("Using ChatThrottleLib")
    ChatThrottleLib:SendAddonMessage("NORMAL", prefix, msg, channel, target)
    return
  end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    dbg("Using C_ChatInfo.SendAddonMessage")
    C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
    return
  end
  dbg("ERROR: no addon message transport available")
end

local function packStatePayload(s)
  s = s or {}
  local p = s.pet
  if type(p) ~= "table" then p = {} end
  local classKey = s.classKey
  if (type(classKey) ~= "string" or classKey == "") and UnitClass then
    local _, unitClass = UnitClass("player")
    if type(unitClass) == "string" and unitClass ~= "" then
      classKey = unitClass
    end
  end
  return {
    hp = s.hp or 0,
    maxHp = s.maxHp or 0,
    bonusHp = s.bonusHp or 0,
    armor = s.armor or 0,
    trueArmor = s.trueArmor or 0,
    dodge = s.dodge or 0,
    tempBlock = s.tempBlock or 0,
    tempMagicBlock = s.tempMagicBlock or 0,
    res = s.res or 0,
    maxRes = s.maxRes or 0,
    res2 = s.res2 or 0,
    maxRes2 = s.maxRes2 or 0,
    res3 = s.res3 or 0,
    maxRes3 = s.maxRes3 or 0,
    res4 = s.res4 or 0,
    maxRes4 = s.maxRes4 or 0,
    auth = s.auth or 0,
    maxAuth = s.maxAuth or 5,
    wounds = {
      hit25 = s.wounds and not not s.wounds.hit25 or false,
      hit10 = s.wounds and not not s.wounds.hit10 or false,
    },
    classKey = classKey,
    pet = {
      enabled = not not p.enabled,
      name = type(p.name) == "string" and p.name or "Familier",
      hp = tonumber(p.hp) or 0,
      maxHp = tonumber(p.maxHp) or 0,
      armor = tonumber(p.armor) or 0,
      trueArmor = tonumber(p.trueArmor) or 0,
      dodge = tonumber(p.dodge) or 0,
      tempMagicBlock = tonumber(p.tempMagicBlock) or 0,
      wounds = {
        hit25 = p.wounds and not not p.wounds.hit25 or false,
        hit10 = p.wounds and not not p.wounds.hit10 or false,
      },
    },
  }
end

function Comm.SerializeState(state)
  if not AceSerializer then
    dbg("SerializeState failed: AceSerializer unavailable")
    return nil
  end
  return AceSerializer:Serialize(packStatePayload(state))
end

function Comm:DeserializeState(cmd, payload, sender)
  self.partialMessages = self.partialMessages or {}

  if cmd == "STATE_DATA" or cmd == "STATE_DATA_COMPRESSED" then
    if not AceSerializer then
      dbg("DeserializeState failed: AceSerializer unavailable")
      return nil
    end

    local data = payload or ""
    if cmd == "STATE_DATA_COMPRESSED" and LibDeflate then
      dbg("Decoding compressed payload from %s", tostring(sender))
      data = LibDeflate:DecodeForWoWAddonChannel(data)
      data = data and LibDeflate:DecompressDeflate(data)
      if not data then
        dbg("Decompression failed from %s", tostring(sender))
        return nil
      end
    end

    if data == "" then
      dbg("DeserializeState empty payload from %s", tostring(sender))
      return nil
    end

    local success, decoded = AceSerializer:Deserialize(data)
    if not success or type(decoded) ~= "table" then
      dbg("DeserializeState decode failed from %s", tostring(sender))
      return nil
    end

    dbg(
      "DeserializeState success from %s hp=%s/%s res=%s/%s",
      tostring(sender),
      tostring(decoded.hp),
      tostring(decoded.maxHp),
      tostring(decoded.res),
      tostring(decoded.maxRes)
    )

    return {
      hp = tonumber(decoded.hp) or 0,
      maxHp = tonumber(decoded.maxHp) or 0,
      bonusHp = tonumber(decoded.bonusHp) or 0,
      armor = tonumber(decoded.armor) or 0,
      trueArmor = tonumber(decoded.trueArmor) or 0,
      dodge = tonumber(decoded.dodge) or 0,
      tempBlock = tonumber(decoded.tempBlock) or 0,
      tempMagicBlock = tonumber(decoded.tempMagicBlock) or 0,
      res = tonumber(decoded.res) or 0,
      maxRes = tonumber(decoded.maxRes) or 0,
      res2 = tonumber(decoded.res2) or 0,
      maxRes2 = tonumber(decoded.maxRes2) or 0,
      res3 = tonumber(decoded.res3) or 0,
      maxRes3 = tonumber(decoded.maxRes3) or 0,
      res4 = tonumber(decoded.res4) or 0,
      maxRes4 = tonumber(decoded.maxRes4) or 0,
      auth = tonumber(decoded.auth) or 0,
      maxAuth = tonumber(decoded.maxAuth) or 5,
      wounds = {
        hit25 = decoded.wounds and not not decoded.wounds.hit25 or false,
        hit10 = decoded.wounds and not not decoded.wounds.hit10 or false,
      },
      classKey = type(decoded.classKey) == "string" and decoded.classKey or nil,
      pet = {
        enabled = decoded.pet and not not decoded.pet.enabled or false,
        name = decoded.pet and type(decoded.pet.name) == "string" and decoded.pet.name or "Familier",
        hp = decoded.pet and tonumber(decoded.pet.hp) or 0,
        maxHp = decoded.pet and tonumber(decoded.pet.maxHp) or 0,
        armor = decoded.pet and tonumber(decoded.pet.armor) or 0,
        trueArmor = decoded.pet and tonumber(decoded.pet.trueArmor) or 0,
        dodge = decoded.pet and tonumber(decoded.pet.dodge) or 0,
        tempMagicBlock = decoded.pet and tonumber(decoded.pet.tempMagicBlock) or 0,
        wounds = {
          hit25 = decoded.pet and decoded.pet.wounds and not not decoded.pet.wounds.hit25 or false,
          hit10 = decoded.pet and decoded.pet.wounds and not not decoded.pet.wounds.hit10 or false,
        },
      },
    }
  end

  if cmd == "STATE_DATA_PART" or cmd == "STATE_DATA_COMPRESSED_PART" then
    local totalParts = payload and payload.total
    local index = payload and payload.index
    local part = payload and payload.data
    if not (totalParts and index and part) then
      dbg("Invalid multipart payload from %s", tostring(sender))
      return nil
    end

    local key = (sender or "?")
    local entry = self.partialMessages[key]
    if not entry then
      entry = {
        total = totalParts,
        parts = {},
        isCompressed = (cmd == "STATE_DATA_COMPRESSED_PART"),
        start = GetTime(),
      }
      self.partialMessages[key] = entry
      dbg(
        "Start multipart receive from %s total=%d compressed=%s",
        tostring(sender),
        totalParts,
        tostring(entry.isCompressed)
      )
    end

    if totalParts ~= entry.total then
      dbg("Multipart mismatch from %s expected=%d got=%d", tostring(sender), entry.total, totalParts)
      self.partialMessages[key] = nil
      return nil
    end

    entry.parts[index] = part
    dbg("Multipart part from %s index=%d/%d", tostring(sender), index, entry.total)

    if GetTime() - entry.start > 30 then
      dbg("Multipart timeout from %s", tostring(sender))
      self.partialMessages[key] = nil
      return nil
    end

    local received = 0
    for i = 1, entry.total do
      if entry.parts[i] then
        received = received + 1
      end
    end

    if received == entry.total then
      local combined = table.concat(entry.parts)
      self.partialMessages[key] = nil
      local nextCmd = entry.isCompressed and "STATE_DATA_COMPRESSED" or "STATE_DATA"
      dbg("Multipart complete from %s, combinedBytes=%d", tostring(sender), #combined)
      return self:DeserializeState(nextCmd, combined, sender)
    end

    return nil
  end

  return nil
end

function Comm:SendStateData(targetPlayer)
  if not targetPlayer then
    dbg("SendStateData aborted: no target")
    return
  end

  local state = ns.Core and ns.Core.state
  if not state then
    dbg("SendStateData aborted: no core state")
    return
  end

  local serialized = Comm.SerializeState(state)
  if not serialized then
    dbg("SendStateData aborted: serialization failed")
    return
  end

  dbg(
    "Preparing state for %s hp=%d/%d res=%d/%d",
    tostring(targetPlayer),
    state.hp or 0,
    state.maxHp or 0,
    state.res or 0,
    state.maxRes or 0
  )

  local encoded = serialized
  local compressed = false

  if #serialized > 255 and LibDeflate then
    dbg("Compressing payload for %s originalBytes=%d", tostring(targetPlayer), #serialized)
    encoded = LibDeflate:CompressDeflate(serialized)
    encoded = LibDeflate:EncodeForWoWAddonChannel(encoded)
    compressed = true
  end

  local cmd = compressed and "STATE_DATA_COMPRESSED" or "STATE_DATA"
  local message = string.format("%s:%s", cmd, encoded)

  if #message <= 255 then
    dbg("Sending single message cmd=%s to %s", cmd, tostring(targetPlayer))
    sendAddonMessage(self.PREFIX, message, "WHISPER", targetPlayer)
    return
  end

  local partCmd = cmd .. "_PART"
  local chunkSize = 200
  local totalParts = math.ceil(#encoded / chunkSize)
  dbg("Sending multipart cmd=%s to %s totalParts=%d", partCmd, tostring(targetPlayer), totalParts)
  for i = 1, totalParts do
    local chunk = encoded:sub((i - 1) * chunkSize + 1, i * chunkSize)
    local partMsg = string.format("%s:%d:%d:%s", partCmd, totalParts, i, chunk)
    sendAddonMessage(self.PREFIX, partMsg, "WHISPER", targetPlayer)
  end
end

function Comm:RequestState(targetPlayer)
  if not targetPlayer or targetPlayer == "" then
    dbg("RequestState aborted: invalid target")
    return
  end
  dbg("Requesting state from %s", tostring(targetPlayer))
  sendAddonMessage(self.PREFIX, "REQUEST_STATE", "WHISPER", targetPlayer)
end

function Comm:HandleStateData(sender, cmd, rest)
  dbg("HandleStateData cmd=%s sender=%s restBytes=%d", tostring(cmd), tostring(sender), #(rest or ""))
  if cmd == "STATE_DATA" or cmd == "STATE_DATA_COMPRESSED" then
    local state = self:DeserializeState(cmd, rest, sender)
    if state and ns.TargetPopup and ns.TargetPopup.OnStateReceived then
      dbg("Forwarding decoded state to popup for sender=%s", tostring(sender))
      ns.TargetPopup:OnStateReceived(sender, state)
    else
      dbg("No state decoded for sender=%s", tostring(sender))
    end
    return
  end

  if cmd == "STATE_DATA_PART" or cmd == "STATE_DATA_COMPRESSED_PART" then
    local total, index, part = strsplit(":", rest or "", 3)
    local state = self:DeserializeState(cmd, {
      total = tonumber(total),
      index = tonumber(index),
      data = part,
    }, sender)
    if state and ns.TargetPopup and ns.TargetPopup.OnStateReceived then
      dbg("Forwarding multipart decoded state to popup for sender=%s", tostring(sender))
      ns.TargetPopup:OnStateReceived(sender, state)
    else
      dbg("Multipart state not complete yet for sender=%s", tostring(sender))
    end
  end
end

function Comm:OnChatMsgAddon(prefixMsg, msg, channel, sender)
  dbg(
    "CHAT_MSG_ADDON prefix=%s channel=%s sender=%s bytes=%d",
    tostring(prefixMsg),
    tostring(channel),
    tostring(sender),
    #(msg or "")
  )
  if prefixMsg ~= self.PREFIX then
    return
  end

  if msg == "REQUEST_STATE" then
    dbg("Received REQUEST_STATE from %s", tostring(sender))
    self:SendStateData(sender)
    return
  end

  local cmd, rest = strsplit(":", msg or "", 2)
  if not cmd then
    dbg("Message parse failed from %s", tostring(sender))
    return
  end
  self:HandleStateData(sender, cmd, rest)
end

function Comm:Initialize()
  dbg("Initialize start (AceSerializer=%s LibDeflate=%s)", tostring(AceSerializer ~= nil), tostring(LibDeflate ~= nil))
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    dbg("Registered addon prefix %s", self.PREFIX)
  else
    dbg("WARNING: C_ChatInfo.RegisterAddonMessagePrefix unavailable")
  end

  if self.eventFrame then
    return
  end

  self.eventFrame = CreateFrame("Frame")
  self.eventFrame:RegisterEvent("CHAT_MSG_ADDON")
  self.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
      self:OnChatMsgAddon(...)
    end
  end)
  dbg("Initialize complete: CHAT_MSG_ADDON listener active")
end

function ns.Comm_Init()
  Comm:Initialize()
end
