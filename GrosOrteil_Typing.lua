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
local debugUntil = 0
local diagnostics = { input = "no focused chat", sent = 0, failed = 0, received = 0 }
local pendingProbe

local function diagnostic(message)
  print("|cFF00FF00GrosOrteil saisie|r " .. message)
end

local function trace(message)
  if GetTime() < debugUntil then print("|cFF00FF00GrosOrteil saisie|r " .. message) end
end

local function inputStatus(status)
  if diagnostics.input ~= status then
    diagnostics.input = status
    trace("Input: " .. status)
  end
end

local function sendResult(sent, result)
  local label = tostring(result)
  for name, value in pairs(Enum and Enum.SendAddonMessageResult or {}) do
    if value == result then label = name; break end
  end
  local key = sent and "sent" or "failed"
  diagnostics[key] = diagnostics[key] + 1
  diagnostics.result = (sent and "accepted" or "FAILED") .. " (" .. label .. ")"
  trace("Transport: " .. diagnostics.result)
end

function Typing.Debug(command)
  local mode, target = (command or ""):match("^(%S*)%s*(.-)$")
  mode = mode:lower()
  if mode == "test" then Typing.TestDisplay(); return end
  if mode == "probe" then Typing.ProbePeer(target); return end
  debugUntil = mode == "off" and 0 or GetTime() + 60
  if mode == "off" then pendingProbe = nil end
  print("|cFF00FF00GrosOrteil saisie|r enabled=" .. tostring(Typing.IsEnabled())
    .. ", polling=" .. tostring(ticker ~= nil) .. ", input=" .. diagnostics.input
    .. ", accepted=" .. diagnostics.sent .. ", failed=" .. diagnostics.failed
    .. ", received=" .. diagnostics.received .. ", last=" .. (diagnostics.result or "none"))
  print("|cFF00FF00GrosOrteil saisie|r " .. (mode == "off" and "Diagnostic off."
    or "Diagnostic on for 60s. Type normally; draft text is never logged. Accepted means sent to WoW, not confirmed by a recipient."))
end

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
  diagnostics.received = diagnostics.received + 1
  trace("Receive: " .. (usable(sender) and sender or "?") .. " / " .. (usable(channel) and channel or "?"))
  if not Typing.IsEnabled() or not usable(channel) or not usable(payload) then trace("Ignored: disabled/invalid packet"); return end
  local active, position
  if channel == "CHANNEL" then
    channel = "SAY"
    if payload == "1:SAY:0" then active = false
    else
      local map, x, y = payload:match("^1:SAY:1:(%-?%d+):([%d%.%-]+):([%d%.%-]+)$")
      map, x, y = tonumber(map), tonumber(x), tonumber(y)
      if not map or not x or not y or map < 0 or map > 1e6 or math.abs(x) > 1e6 or math.abs(y) > 1e6 then trace("Ignored: invalid SAY position"); return end
      position = { map = map, x = x, y = y }
      active = inSayRange(position, ns.Distance.GetPlayerPosition())
    end
  elseif channel ~= "SAY" and CHANNELS[channel] then
    if payload ~= "1:1" and payload ~= "1:0" then trace("Ignored: unsupported payload"); return end
    active = payload == "1:1"
  else trace("Ignored: unsupported channel"); return end
  if groupChannel(channel) and not groupAvailable(channel) then trace("Ignored: no matching group"); return end
  local key = nameKey(sender)
  if not key or key == unitKey("player") then trace("Ignored: self/invalid sender"); return end
  -- Nameplates only control overhead icons. Their absence (including friendly
  -- plates being disabled) must not discard a nearby SAY status for the summary.
  -- World coordinates cannot distinguish overlapping shards/phases.
  if not active then trace("Hidden: stopped/out of range/position unavailable"); removePeer(key, channel); return end
  trace("Display: " .. channel)
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
    trace("Stop: " .. announcedChannel)
    ns.Comm:SendTyping(announcedChannel, announcedTarget, false, nil, sendResult)
    announcedChannel, announcedTarget = nil, nil
  end
end

-- Reuse the existing state request/reply, understood by unpatched peers. A
-- reply proves addon traffic can make the round trip, not their typing UI.
function Typing.ProbePeer(target)
  if not usable(target) or target:find("%s") then
    diagnostic("Usage: /go typingdebug probe Character-Realm")
    return
  end
  local key = nameKey(target)
  if not key or key == unitKey("player") then
    diagnostic("Choose another player for the network check.")
    return
  end
  if pendingProbe then diagnostic("A network check is already pending."); return end
  local probe = { key = key, target = target }
  pendingProbe = probe
  diagnostic("Network check: requesting addon state from " .. target .. " (no update needed on their side).")
  C_Timer.After(8, function()
    if pendingProbe ~= probe then return end
    pendingProbe = nil
    diagnostic("No state reply from " .. target .. " within 8s. This does not identify the cause; check character/realm and that their addon is active.")
  end)
  ns.Comm:ProbeState(target, function(sent, result)
    if pendingProbe ~= probe or sent then return end
    pendingProbe = nil
    diagnostic("Network check send failed: " .. tostring(result))
  end)
end

function Typing.OnDiagnosticMessage(sender, channel, command)
  local probe = pendingProbe
  if not probe or channel ~= "WHISPER" or nameKey(sender) ~= probe.key then return end
  if command ~= "STATE_DATA" and command ~= "STATE_DATA_COMPRESSED"
      and command ~= "STATE_DATA_PART" and command ~= "STATE_DATA_COMPRESSED_PART" then return end
  pendingProbe = nil
  diagnostic("State reply received from " .. sender .. ": addon traffic works in both directions. Their typing setting/display is still unverified.")
end

local function focusedChat()
  local getActive = ChatFrameUtil and ChatFrameUtil.GetActiveWindow or ChatEdit_GetActiveWindow
  local edit = getActive and getActive()
  if edit and edit:HasFocus() then return edit end
  -- The active-window pointer can be absent/stale. Only inspect known chat
  -- boxes, so typing in addon forms never broadcasts a typing status.
  for _, name in ipairs(CHAT_FRAMES or {}) do
    local chat = _G[name]
    edit = chat and chat.editBox
    if edit and edit:HasFocus() then return edit end
  end
  edit = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
  if edit and edit:HasFocus() then return edit end
end

local function sampleInput(now)
  local edit = focusedChat()
  local text = edit and edit:GetText() or nil
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
    if channel == "SAY" and not position then inputStatus("SAY position unavailable"); stopSending(); return end
    -- Bound failed attempts as well as successful starts.
    lastSent = now
    trace("Send: " .. channel .. (target and (" / " .. target) or ""))
    if ns.Comm:SendTyping(channel, target, true, position, sendResult) then
      announcedChannel, announcedTarget = channel, target
    end
  end
  inputStatus(channel and ("typing " .. channel) or (not edit and "no focused chat" or "draft inactive/unsupported"))
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

function Typing.TestDisplay()
  if not frame or not ticker or not Typing.IsEnabled() then
    diagnostic("Enable Saisie before running the local display test.")
    return
  end
  local realm = GetNormalizedRealmName()
  if not usable(realm) then diagnostic("Local realm unavailable."); return end
  local sender = "GrosOrteilTypingTest-" .. realm
  -- Inject locally through the normal message parser; nothing goes on the wire.
  ns.Comm:OnChatMsgAddon(ns.Comm.PREFIX, "TYPING:1:1", "WHISPER", sender)
  local peer = peers[nameKey(sender)]
  if not peer then diagnostic("Local test failed: the receiver rejected the test signal."); return end
  peer.name = "Test de saisie (local)"
  dirty = true
  refresh()
  diagnostic("Local test: a pink typing summary should appear above chat for 7s. No message was sent to another player.")
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
