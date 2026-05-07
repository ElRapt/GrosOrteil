---@diagnostic disable: undefined-global, unused-local
local _, ns = ...

local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "GO_STATE"
Comm.REQUEST_TIMEOUT = 5
-- Per-sender minimum interval between REQUEST_STATE responses. The popup side
-- self-throttles at 5s, so anything below that is a misbehaving/abusive peer.
Comm.RESPONSE_COOLDOWN = 3

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

-- Debug logging (no-op in release; replace body with print() for development)
---@diagnostic disable-next-line: unused-vararg
local function dbg(...) end

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

-- Numeric fields shared in the addon-message payload. Each entry: { key, default }.
-- tempArmor is included so peer popups display the player's effective armor.
local NUMERIC_FIELDS = {
  { "hp", 0 }, { "maxHp", 0 },
  { "armor", 0 }, { "trueArmor", 0 }, { "tempArmor", 0 }, { "dodge", 0 },
  { "tempBlock", 0 },
  { "res", 0 }, { "maxRes", 0 },
  { "res2", 0 }, { "maxRes2", 0 },
  { "res3", 0 }, { "maxRes3", 0 },
  { "res4", 0 }, { "maxRes4", 0 },
  { "auth", 0 }, { "maxAuth", 5 },
  { "attaqueMelee", 0 }, { "attaqueDistance", 0 },
  { "chance", 0 }, { "maxChance", 0 },
  { "perception", 0 },
}
local PET_NUMERIC_FIELDS = {
  { "hp", 0 }, { "maxHp", 0 },
  { "armor", 0 }, { "trueArmor", 0 }, { "dodge", 0 },
  { "attaqueMelee", 0 }, { "attaqueDistance", 0 },
  { "tempArmor", 0 },
}

local function copyNumeric(src, fields)
  local out = {}
  src = src or {}
  for i = 1, #fields do
    local k, def = fields[i][1], fields[i][2]
    out[k] = tonumber(src[k]) or def
  end
  return out
end

local function packWounds(w)
  return {
    hit25 = not not (w and w.hit25),
    hit10 = not not (w and w.hit10),
  }
end

local function buildPayload(src, petSrc, classKey)
  local out = copyNumeric(src, NUMERIC_FIELDS)
  out.wounds   = packWounds(src.wounds)
  out.stabilise = src.stabilise and true or false
  out.classKey = classKey

  -- Player magic shield (mirrors the per-pet block below). Without this peer
  -- popups always show 0 for the player's magic-shield overlay.
  local sms = type(src.magicShield) == "table" and src.magicShield or {}
  out.magicShield = {
    hp    = tonumber(sms.hp)    or 0,
    maxHp = tonumber(sms.maxHp) or 0,
    armor = tonumber(sms.armor) or 0,
  }
  -- Mana shield (Mage only): peers need to know it's active to render the
  -- effective tempArmor contribution.
  local smns = type(src.manaShield) == "table" and src.manaShield or {}
  out.manaShield = {
    active = smns.active and true or false,
    armor  = tonumber(smns.armor) or 0,
  }

  local pet = copyNumeric(petSrc, PET_NUMERIC_FIELDS)
  pet.enabled          = not not petSrc.enabled
  pet.authorityEnabled = not not petSrc.authorityEnabled
  pet.name             = type(petSrc.name) == "string" and petSrc.name or "Familier"
  pet.wounds           = packWounds(petSrc.wounds)
  local pms = type(petSrc.magicShield) == "table" and petSrc.magicShield or {}
  pet.magicShield = {
    hp    = tonumber(pms.hp)    or 0,
    maxHp = tonumber(pms.maxHp) or 0,
    armor = tonumber(pms.armor) or 0,
  }
  out.pet = pet
  return out
end

local function packStatePayload(s)
  s = s or {}
  local p = type(s.pet) == "table" and s.pet or {}
  local classKey = s.classKey
  if (type(classKey) ~= "string" or classKey == "") and UnitClass then
    local _, unitClass = UnitClass("player")
    if type(unitClass) == "string" and unitClass ~= "" then
      classKey = unitClass
    end
  end
  return buildPayload(s, p, classKey)
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

    local decodedPet = type(decoded.pet) == "table" and decoded.pet or {}
    local classKey = type(decoded.classKey) == "string" and decoded.classKey or nil
    return buildPayload(decoded, decodedPet, classKey)
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
  if type(targetPlayer) ~= "string" or targetPlayer == "" then
    dbg("SendStateData aborted: invalid target")
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
    -- Rate-limit per sender so a misbehaving peer can't flood our addon channel
    -- by spamming requests.
    self.lastRequestServed = self.lastRequestServed or {}
    local now = (GetTime and GetTime()) or 0
    local last = self.lastRequestServed[sender or ""] or 0
    if last > 0 and (now - last) < self.RESPONSE_COOLDOWN then
      dbg("Throttled REQUEST_STATE from %s (last %.2fs ago)", tostring(sender), now - last)
      return
    end
    self.lastRequestServed[sender or ""] = now
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
