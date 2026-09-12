---@diagnostic disable: undefined-global
local _, ns = ...
local Typing = {}
ns.Typing = Typing

local Shared = ns.Shared
local CHANNELS = { SAY = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }
local ICON = "Interface\\GossipFrame\\GossipGossipIcon"
local INTERVAL, HEARTBEAT, IDLE, EXPIRY = 0.2, 3, 8, 7
-- One expiring record per sender; frames own their reusable icon textures.
local peers, plates = {}, {}
local frame, ticker, summary
local announcedChannel, announcedTarget, lastSent
local lastText, lastEdit, lastActivity
local lastJoin
local dirty = false

function Typing.IsEnabled()
  local settings = ns.GetDB().settings
  return not settings or settings.typingIndicators ~= false
end

local function usable(value)
  return not Shared.IsSecret(value) and type(value) == "string" and value ~= ""
end

local function displayName(sender)
  local popup = ns.TargetPopup
  local name = popup and popup.GetRPDisplayName and popup.GetRPDisplayName(sender)
  if not usable(name) then return sender end
  -- The channel owns the text color, including names with embedded RP colors.
  name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return name ~= "" and name or sender
end

-- Unlike roster display keys, network identities must retain their realm.
local function nameKey(name, realm)
  if not usable(name) then return nil end
  if not name:find("-", 1, true) then
    if not usable(realm) then realm = GetNormalizedRealmName() end
    if not usable(realm) then return nil end
    name = name .. "-" .. realm
  end
  return name:lower():gsub("%s+", "")
end

local function unitKey(unit)
  local name, realm = UnitFullName(unit)
  return nameKey(name, realm)
end

local function groupChannel(channel)
  return channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT"
end

local function groupAvailable(channel)
  if channel == "INSTANCE_CHAT" then return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end
  if channel == "RAID" then return IsInRaid(LE_PARTY_CATEGORY_HOME) end
  return IsInGroup(LE_PARTY_CATEGORY_HOME)
end

local function removePeer(key, channel)
  local peer = peers[key]
  if peer and (not channel or peer.channel == channel) then
    peers[key] = nil
    dirty = true
  end
end

local function inSayRange(position, player)
  if not player or player.map ~= position.map then return false end
  local dx, dy = player.x - position.x, player.y - position.y
  return dx * dx + dy * dy <= 60 * 60
end

function Typing.Receive(sender, channel, payload)
  if not Typing.IsEnabled() or not usable(channel) or not usable(payload) then return end
  local active, position
  if channel == "CHANNEL" then
    channel = "SAY"
    if payload == "1:SAY:0" then active = false
    else
      local map, x, y = payload:match("^1:SAY:1:(%-?%d+):([%d%.%-]+):([%d%.%-]+)$")
      map, x, y = tonumber(map), tonumber(x), tonumber(y)
      if not map or not x or not y or map < 0 or map > 1e6 or math.abs(x) > 1e6 or math.abs(y) > 1e6 then return end
      position = { map = map, x = x, y = y }
      active = inSayRange(position, ns.Distance.GetPlayerPosition())
    end
  elseif channel ~= "SAY" and CHANNELS[channel] then
    if payload ~= "1:1" and payload ~= "1:0" then return end
    active = payload == "1:1"
  else return end
  if groupChannel(channel) and not groupAvailable(channel) then return end
  local key = nameKey(sender)
  if not key or key == unitKey("player") then return end
  if active and channel == "SAY" then
    -- A realm-wide channel also contains other shards/phases. Require a local
    -- nameplate before treating a nearby coordinate as a visible speaker.
    local visible = false
    for unit in pairs(plates) do
      if unitKey(unit) == key then visible = true; break end
    end
    active = visible
  end
  if not active then removePeer(key, channel); return end
  local peer = peers[key]
  if not peer then
    peer = { name = sender }
    peers[key] = peer
    dirty = true
  end
  if peer.channel ~= channel then dirty = true end
  local shownName = displayName(sender)
  if peer.name ~= shownName then peer.name, dirty = shownName, true end
  peer.channel, peer.expires, peer.position = channel, GetTime() + EXPIRY, position
end

local function stopSending()
  if announcedChannel then
    ns.Comm:SendTyping(announcedChannel, announcedTarget, false)
    announcedChannel, announcedTarget = nil, nil
  end
end

local function sampleInput(now)
  local edit = ChatFrameUtil and ChatFrameUtil.GetActiveWindow()
  local text = edit and edit:HasFocus() and edit:GetText() or nil
  if not usable(text) then text = nil end
  if edit ~= lastEdit or text ~= lastText then
    lastActivity = now
    lastEdit, lastText = edit, text
  end
  local channel, target
  if text and not text:match("^%s*$") and text:sub(1, 1) ~= "/"
      and now - lastActivity < IDLE then
    channel = edit:GetAttribute("chatType")
    if not usable(channel) or not CHANNELS[channel] then channel = nil end
    if channel == "WHISPER" then
      target = edit:GetAttribute("tellTarget")
      if not usable(target) then channel, target = nil, nil end
    elseif channel and groupChannel(channel) and not groupAvailable(channel) then
      channel = nil
    end
  end
  if channel ~= announcedChannel or target ~= announcedTarget then stopSending() end
  -- Limit new starts even when channels/recipients change rapidly.
  if channel and (not lastSent or now - lastSent >= (announcedChannel and HEARTBEAT or 1)) then
    local position = channel == "SAY" and ns.Distance.GetPlayerPosition() or nil
    if channel == "SAY" and not position then stopSending(); return end
    if ns.Comm:SendTyping(channel, target, true, position) then
      announcedChannel, announcedTarget, lastSent = channel, target, now
    end
  end
end

local function updatePlate(plate, unit)
  if plate:IsForbidden() then return end
  local player = UnitIsPlayer(unit)
  local key = not Shared.IsSecret(player) and player and unitKey(unit)
  local peer = key and peers[key]
  local icon = plate.grosOrteilTypingIcon
  if peer and not icon then
    icon = plate:CreateTexture(nil, "OVERLAY")
    icon:SetSize(18, 18)
    icon:SetPoint("BOTTOM", plate, "TOP", 0, 0)
    icon:SetTexture(ICON)
    plate.grosOrteilTypingIcon = icon
  end
  if icon then
    if peer then
      local color = ChatTypeInfo[peer.channel]
      icon:SetVertexColor(color.r, color.g, color.b)
      icon:Show()
    else
      icon:Hide()
    end
  end
end

local function refreshSummary()
  if not summary then return end
  local count, only, channel = 0
  for _, peer in pairs(peers) do
    count, only = count + 1, peer
    if count == 1 then channel = peer.channel
    elseif channel ~= peer.channel then channel = nil end
  end
  if count == 0 then summary:Hide(); return end
  summary.text:SetText(count == 1 and (only.name .. " écrit…") or (count .. " personnes écrivent…"))
  local color = channel and ChatTypeInfo[channel]
  summary.text:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
  summary:Show()
end

local function refresh()
  if not dirty then return end
  for unit, plate in pairs(plates) do updatePlate(plate, unit) end
  refreshSummary()
  if summary and summary:IsShown() and GameTooltip:IsOwned(summary) then
    summary:GetScript("OnEnter")(summary)
  end
  dirty = false
end

local function tick()
  local now = GetTime()
  if GetChannelName(ns.Comm.TYPING_CHANNEL) == 0 and (not lastJoin or now - lastJoin >= 10) then
    lastJoin = now
    JoinTemporaryChannel(ns.Comm.TYPING_CHANNEL)
  end
  sampleInput(now)
  local player, measured
  for key, peer in pairs(peers) do
    if peer.position and not measured then
      player, measured = ns.Distance.GetPlayerPosition(), true
    end
    if now >= peer.expires or (peer.position and not inSayRange(peer.position, player)) then removePeer(key) end
  end
  refresh()
end

local function clear()
  stopSending()
  for key in pairs(peers) do peers[key] = nil end
  lastText, lastEdit, lastActivity = nil, nil, nil
  dirty = true
  refresh()
end

local function applyEnabled()
  if ticker then ticker:Cancel(); ticker = nil end
  clear()
  if Typing.IsEnabled() then ticker = C_Timer.NewTicker(INTERVAL, tick) end
end

function Typing.SetEnabled(enabled)
  local db = ns.GetDB()
  db.settings = db.settings or {}
  db.settings.typingIndicators = not not enabled
  if frame then applyEnabled() end
  if not enabled then LeaveChannelByName(ns.Comm.TYPING_CHANNEL) end
end

function Typing.Initialize()
  if frame then return end
  frame = CreateFrame("Frame")
  frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  frame:RegisterEvent("GROUP_ROSTER_UPDATE")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("PLAYER_LEAVING_WORLD")
  frame:RegisterEvent("PLAYER_LOGOUT")
  for channel in pairs(CHANNELS) do frame:RegisterEvent("CHAT_MSG_" .. channel) end
  frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
  frame:RegisterEvent("CHAT_MSG_RAID_LEADER")
  frame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
  frame:SetScript("OnEvent", function(_, event, arg1, sender)
    if event == "NAME_PLATE_UNIT_ADDED" then
      local plate = C_NamePlate.GetNamePlateForUnit(arg1)
      if plate and not plate:IsForbidden() then
        plates[arg1] = plate
        updatePlate(plate, arg1)
      end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
      local plate = plates[arg1]
      if plate and not plate:IsForbidden() and plate.grosOrteilTypingIcon then plate.grosOrteilTypingIcon:Hide() end
      plates[arg1] = nil
    elseif event == "GROUP_ROSTER_UPDATE" then
      -- Unchanged rosters must not blink or restart unrelated say/whisper traffic.
      for key, peer in pairs(peers) do
        if groupChannel(peer.channel) and not groupAvailable(peer.channel) then removePeer(key) end
      end
      if announcedChannel and groupChannel(announcedChannel) and not groupAvailable(announcedChannel) then stopSending() end
    elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
      if ticker then ticker:Cancel(); ticker = nil end
      clear()
    elseif event == "PLAYER_ENTERING_WORLD" then
      applyEnabled()
    else
      local channel = event:match("^CHAT_MSG_(.+)$")
      if channel then
        channel = channel:gsub("_LEADER$", "")
        local key = nameKey(sender)
        if key then removePeer(key, channel) end
      end
    end
    refresh()
  end)

  -- Constant footprint even with a whole raid typing. Details appear only on hover.
  summary = CreateFrame("Frame", "GrosOrteilTypingSummary", UIParent)
  summary:SetSize(280, 20)
  -- Leave room for the chat tabs above the message area.
  summary:SetPoint("BOTTOMLEFT", ChatFrame1 or UIParent, "TOPLEFT", 0, 32)
  summary:EnableMouse(true)
  local icon = summary:CreateTexture(nil, "ARTWORK")
  icon:SetSize(16, 16)
  icon:SetPoint("LEFT")
  icon:SetTexture(ICON)
  summary.text = summary:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  summary.text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  summary.text:SetPoint("RIGHT")
  summary.text:SetJustifyH("LEFT")
  summary.text:SetWordWrap(false)
  summary:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText("En cours de saisie")
    local names = {}
    for key in pairs(peers) do names[#names + 1] = key end
    table.sort(names)
    for i = 1, math.min(#names, 40) do
      local peer = peers[names[i]]
      local color = ChatTypeInfo[peer.channel]
      GameTooltip:AddLine(peer.name .. " — " .. (_G[peer.channel] or peer.channel), color.r, color.g, color.b)
    end
    if #names > 40 then GameTooltip:AddLine("+ " .. (#names - 40) .. " autres") end
    GameTooltip:Show()
  end)
  summary:SetScript("OnLeave", function() GameTooltip:Hide() end)
  summary:SetScript("OnHide", function(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  if C_NamePlate then
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
      if not plate:IsForbidden() and plate.namePlateUnitToken then
        plates[plate.namePlateUnitToken] = plate
      end
    end
  end
  applyEnabled()
end
