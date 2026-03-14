---@diagnostic disable: undefined-global
local _, ns = ...

local Popup = {}
ns.TargetPopup = Popup

local _G = _G
local type = type
local math = math
local string = string
local UnitExists = rawget(_G, "UnitExists")
local UnitIsPlayer = rawget(_G, "UnitIsPlayer")
local UnitName = rawget(_G, "UnitName")
local UnitFullName = rawget(_G, "UnitFullName")
local CreateFrame = rawget(_G, "CreateFrame")
local UIParent = rawget(_G, "UIParent")
local C_Timer = rawget(_G, "C_Timer")
local tostring = tostring

local pendingTarget
local popupFrame

local function dbg(fmt, ...)
  local _ = fmt
  select("#", ...)
  return
end

local function normalizeName(name)
  if type(name) ~= "string" then return nil end
  if name == "" then return nil end
  local out = name:gsub("%s+", ""):lower()
  if out == "" then return nil end
  return out
end

local function splitNameRealm(name)
  local normalized = normalizeName(name)
  if not normalized then return nil, nil end
  local short, realm = normalized:match("^([^%-]+)%-(.+)$")
  if short and short ~= "" then
    return short, realm
  end
  return normalized, nil
end

local function namesMatch(a, b)
  local aShort, aRealm = splitNameRealm(a)
  local bShort, bRealm = splitNameRealm(b)
  if not aShort or not bShort then return false end
  if aShort ~= bShort then return false end

  -- If either side has no realm, treat short-name match as valid.
  if not aRealm or not bRealm then
    return true
  end

  return aRealm == bRealm
end

local function unitTargetName(unit)
  if UnitFullName then
    local name, realm = UnitFullName(unit)
    if name and name ~= "" then
      if realm and realm ~= "" then
        return name .. "-" .. realm
      end
      return name
    end
  end

  local name, realm = UnitName(unit)
  if name and name ~= "" then
    if realm and realm ~= "" then
      return name .. "-" .. realm
    end
    return name
  end

  return nil
end

local function roundNumber(v)
  if type(v) ~= "number" then return 0 end
  if v >= 0 then
    return math.floor(v + 0.5)
  end
  return -math.floor((-v) + 0.5)
end

local function hidePopup()
  if popupFrame then
    popupFrame:Hide()
    dbg("Popup hidden")
  end
end

local function createPopup()
  if popupFrame then return end

  popupFrame = CreateFrame("Frame", "GrosOrteilTargetPopup", UIParent, "BackdropTemplate")
  popupFrame:SetSize(260, 110)
  popupFrame:SetFrameStrata("DIALOG")
  popupFrame:SetMovable(true)
  popupFrame:EnableMouse(true)
  popupFrame:RegisterForDrag("LeftButton")
  popupFrame:SetScript("OnDragStart", popupFrame.StartMoving)
  popupFrame:SetScript("OnDragStop", popupFrame.StopMovingOrSizing)
  popupFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  popupFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
  popupFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 220)

  popupFrame.title = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  popupFrame.title:SetPoint("TOPLEFT", 14, -12)
  popupFrame.title:SetText("GrosOrteil")

  popupFrame.hpText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  popupFrame.hpText:SetPoint("TOPLEFT", popupFrame.title, "BOTTOMLEFT", 0, -12)
  popupFrame.hpText:SetJustifyH("LEFT")
  popupFrame.hpText:SetText("HP: -")

  popupFrame.resText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  popupFrame.resText:SetPoint("TOPLEFT", popupFrame.hpText, "BOTTOMLEFT", 0, -8)
  popupFrame.resText:SetJustifyH("LEFT")
  popupFrame.resText:SetText("Ressource: -")

  popupFrame.closeButton = CreateFrame("Button", nil, popupFrame, "UIPanelCloseButton")
  popupFrame.closeButton:SetPoint("TOPRIGHT", popupFrame, "TOPRIGHT", -4, -4)
  popupFrame.closeButton:SetScript("OnClick", hidePopup)
  dbg("Popup frame created")
end

local function showForState(targetName, state)
  createPopup()

  popupFrame.title:SetText(string.format("Etat de %s", targetName or "?"))
  popupFrame.hpText:SetText(string.format("HP: %d / %d", roundNumber(state.hp), roundNumber(state.maxHp)))
  popupFrame.resText:SetText(string.format("Ressource: %d / %d", roundNumber(state.res), roundNumber(state.maxRes)))
  popupFrame:Show()
  dbg(
    "Popup shown for %s hp=%d/%d res=%d/%d",
    tostring(targetName),
    roundNumber(state.hp),
    roundNumber(state.maxHp),
    roundNumber(state.res),
    roundNumber(state.maxRes)
  )
end

function Popup:OnStateReceived(sender, state)
  local _ = self
  if type(state) ~= "table" then
    dbg("OnStateReceived ignored: invalid state from %s", tostring(sender))
    return
  end

  local senderKey = normalizeName(sender)
  if not senderKey then
    dbg("OnStateReceived ignored: sender normalization failed")
    return
  end

  local targetKey = normalizeName(unitTargetName("target"))
  local pendingKey = normalizeName(pendingTarget)
  dbg("OnStateReceived sender=%s target=%s pending=%s", tostring(senderKey), tostring(targetKey), tostring(pendingKey))

  if targetKey and namesMatch(senderKey, targetKey) then
    showForState(sender, state)
    pendingTarget = nil
    dbg("Matched current target, popup updated")
    return
  end

  if pendingKey and namesMatch(senderKey, pendingKey) then
    showForState(sender, state)
    pendingTarget = nil
    dbg("Matched pending target, popup updated")
  else
    dbg("Sender did not match current/pending target")
  end
end

function Popup:OnTargetChanged()
  local _ = self
  dbg("PLAYER_TARGET_CHANGED fired")
  hidePopup()
  pendingTarget = nil

  if not UnitExists("target") or not UnitIsPlayer("target") then
    dbg("Target invalid or not a player")
    return
  end

  local targetName = unitTargetName("target")
  if not targetName then
    dbg("Target name resolution failed")
    return
  end

  pendingTarget = targetName
  dbg("Target resolved: %s", tostring(targetName))

  if ns.Comm and ns.Comm.RequestState then
    dbg("Requesting state via Comm")
    ns.Comm:RequestState(targetName)
  else
    dbg("Comm module unavailable")
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(5, function()
      if pendingTarget and normalizeName(pendingTarget) == normalizeName(targetName) then
        dbg("Pending target timed out waiting for state: %s", tostring(targetName))
        pendingTarget = nil
      end
    end)
  end
end

function Popup:Initialize()
  if self.eventFrame then
    dbg("Initialize skipped: already initialized")
    return
  end

  self.eventFrame = CreateFrame("Frame")
  self.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
  self.eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
      self:OnTargetChanged()
    end
  end)
  dbg("Initialize complete: PLAYER_TARGET_CHANGED listener active")
end

function ns.TargetPopup_Init()
  Popup:Initialize()
end
