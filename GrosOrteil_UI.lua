local _, ns = ...
local Core = ns.Core
local History = ns.History
local Shared = ns.Shared

local UI = {}
ns.UI = UI

local CLASS_STYLES         = Shared.CLASS_STYLES
local getResProfile        = Shared.GetResProfile
local getKeysForIdx        = Shared.GetKeysForIdx
local hideMarkers          = Shared.HideMarkers
local positionMarkers      = Shared.PositionMarkers
local roundPct             = Shared.RoundPct

local function applyResTextColor(txt)
  if not txt or not txt.SetTextColor then return end
  txt:SetTextColor(1, 1, 1, 1)
end

local function setEditBoxEnabled(eb, enabled)
  if not eb then return end
  if enabled then
    if eb.Enable then eb:Enable()
    elseif eb.EnableMouse then eb:EnableMouse(true) end
    if eb.SetAlpha then eb:SetAlpha(1) end
  else
    if eb.Disable then eb:Disable()
    elseif eb.EnableMouse then eb:EnableMouse(false) end
    if eb.SetAlpha then eb:SetAlpha(0.55) end
  end
end

local function setButtonEnabled(btn, enabled)
  if not btn then return end
  if enabled then
    if btn.Enable then btn:Enable() end
    if btn.SetAlpha then btn:SetAlpha(1) end
  else
    if btn.Disable then btn:Disable() end
    if btn.SetAlpha then btn:SetAlpha(0.55) end
  end
end


local setClassIconTexCoords = Shared.SetClassIconTexCoords


local function getTRP3ProfileName()
  local api = rawget(_G, "TRP3_API")
  if type(api) ~= "table" then return nil end
  local profile = api.profile
  if type(profile) ~= "table" then return nil end
  if type(profile.getPlayerCurrentProfile) ~= "function" then return nil end

  local ok, current = pcall(profile.getPlayerCurrentProfile)
  if not ok or type(current) ~= "table" then return nil end

  -- Prefer the character display name (First + optional Last) when available.
  do
    local player = current.player
    local char = (type(player) == "table") and player.characteristics or nil
    if type(char) == "table" then
      local first = char.FN
      local last = char.LN
      if type(first) == "string" then first = first:gsub("^%s+", ""):gsub("%s+$", "") end
      if type(last) == "string" then last = last:gsub("^%s+", ""):gsub("%s+$", "") end

      if type(first) == "string" and first ~= "" then
        local full
        if type(last) == "string" and last ~= "" then
          full = (first .. " " .. last)
        else
          full = first
        end
        full = full:gsub("%s+", " ")
        if full ~= "" then return full end
      end
    end
  end

  -- Fallback to the TRP3 profile name.
  local name = current.profileName
  if type(name) ~= "string" or name == "" then return nil end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil end
  return name
end

local function updateWindowTitle()
  if not UI or not UI.title or not UI.title.SetText then return end
  local profileName = getTRP3ProfileName()
  if profileName then
    UI.title:SetText(profileName)
  else
    UI.title:SetText("GrosOrteil")
  end
end

local function hookTRP3Callbacks()
  if UI and UI._trp3Hooked then return end
  local api = rawget(_G, "TRP3_API")
  local addon = rawget(_G, "TRP3_Addon")
  if type(api) ~= "table" then return end
  if type(api.RegisterCallback) ~= "function" then return end
  if type(addon) ~= "table" then return end

  UI._trp3Hooked = true
  pcall(api.RegisterCallback, addon, "REGISTER_PROFILES_LOADED", updateWindowTitle)
  pcall(api.RegisterCallback, addon, "REGISTER_DATA_UPDATED", updateWindowTitle)
  updateWindowTitle()
end

local function mkLabel(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function mkLabelCenter(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOP", x, y)
  fs:SetJustifyH("CENTER")
  fs:SetText(text)
  return fs
end

local function mkEdit(parent, w, h, x, y, onEnter)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(w, h)
  eb:SetPoint("TOPLEFT", x, y)
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onEnter then onEnter() end
  end)
  return eb
end

local function mkButton(parent, text, w, h, x, y, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function formatHistoryText(history)
  if History and History.FormatHistoryText then
    return History.FormatHistoryText(history)
  end
  return nil
end

local function getNumber(eb)
  local t = eb:GetText()
  local n = tonumber(t)
  return n
end

local function setNumber(eb, n)
  if not eb or not eb.SetText then return end
  if eb.HasFocus and eb:HasFocus() then return end
  if n == nil then eb:SetText("") else eb:SetText(tostring(math.floor(n))) end
end

local function skinBar(bar, r, g, b)
  bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  bar:SetStatusBarColor(r, g, b, 1)

  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints(bar)
  barBg:SetTexture("Interface/Buttons/WHITE8x8")
  barBg:SetColorTexture(0.05, 0.05, 0.05, 0.90)
  bar._bg = barBg

  local sheen = bar:CreateTexture(nil, "OVERLAY")
  sheen:SetTexture("Interface/Buttons/WHITE8x8")
  sheen:SetVertexColor(1, 1, 1, 0.08)
  sheen:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  sheen:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  sheen:SetHeight(math.max(1, math.floor((bar:GetHeight() or 20) / 2)))

  local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
  border:SetAllPoints(bar)
  border:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
  border:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.85)
  bar._border = border
end

function ns.UI_Init()
  local db = (ns.GetDB and ns.GetDB()) or rawget(_G, "GrosOrteilDBPC") or rawget(_G, "GrosOrteilDB") or {}
  db.ui = db.ui or { point = "CENTER", x = 0, y = 0, shown = true }

  if not db.ui._migrated_20260214_wide then
    db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0
    db.ui._migrated_20260214_wide = true
  end

  -- UI layout migration: new sidebar layout is significantly larger.
  if not db.ui._migrated_20260217_sidebar then
    db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0
    db.ui._migrated_20260217_sidebar = true
  end

  local FRAME_W, FRAME_H = 820, 440
  local MIN_W, MIN_H     = 640, 360
  local MAX_W, MAX_H     = 1500, 1000
  local PAD_X = 14
  local applyContentHostLayout  -- forward declaration; defined below

  -- Left sidebar navigation (vertical tabs) + right content area.
  local SIDEBAR_W = 160
  local GUTTER = 12
  local CONTENT_W = FRAME_W - (PAD_X * 2) - SIDEBAR_W - GUTTER

  local frame = CreateFrame("Frame", "GrosOrteilFrame", UIParent, "BackdropTemplate")
  UI.frame = frame
  frame:SetSize(db.ui.w or FRAME_W, db.ui.h or FRAME_H)

  -- QoL: allow ESC to close the window.
  -- WoW closes frames listed in UISpecialFrames when pressing Escape.
  do
    if type(UISpecialFrames) ~= "table" then
      UISpecialFrames = {}
    end
    local found = false
    for i = 1, #UISpecialFrames do
      if UISpecialFrames[i] == "GrosOrteilFrame" then
        found = true
        break
      end
    end
    if not found then
      UISpecialFrames[#UISpecialFrames + 1] = "GrosOrteilFrame"
    end
  end

  -- Keep SavedVariables in sync even when the frame is closed by ESC.
  frame:SetScript("OnShow", function()
    if db and db.ui then db.ui.shown = true end
    hookTRP3Callbacks()
    updateWindowTitle()
  end)
  frame:SetScript("OnHide", function()
    if db and db.ui then db.ui.shown = false end
  end)

  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    if point then
      db.ui.point, db.ui.x, db.ui.y = point, x or 0, y or 0
    end
  end)

  frame:SetBackdrop({
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Gold-Border",
    tile = true, tileSize = 24, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
  frame:SetBackdropColor(0.04, 0.04, 0.05, 0.95)

  local header = frame:CreateTexture(nil, "ARTWORK")
  header:SetPoint("TOPLEFT", 8, -8)
  header:SetPoint("TOPRIGHT", -8, -8)
  header:SetHeight(26)
  header:SetTexture("Interface/Buttons/WHITE8x8")
  header:SetColorTexture(0.14, 0.10, 0.05, 0.50)
  frame._header = header

  local headerLine = frame:CreateTexture(nil, "ARTWORK")
  headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  headerLine:SetHeight(1)
  headerLine:SetTexture("Interface/Buttons/WHITE8x8")
  headerLine:SetColorTexture(1.0, 0.675, 0.125, 0.30)
  frame._headerLine = headerLine

  frame:SetPoint(db.ui.point, UIParent, db.ui.point, db.ui.x, db.ui.y)
  if db.ui.shown then frame:Show() else frame:Hide() end

  -- Titre
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  UI.title = title
  title:SetPoint("TOP", 0, -12)
  updateWindowTitle()

  -- Retry TRP3 hook once after a delay in case TRP3 initializes after us.
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(1.0, function()
      hookTRP3Callbacks()
      updateWindowTitle()
    end)
  end

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  -- Size label shown in the centre during resize.
  local sizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  sizeLabel:SetPoint("CENTER", frame, "CENTER")
  sizeLabel:Hide()

  -- Manual delta-based resize state (declared before OnSizeChanged so the closure can read it).
  local resizing = false
  local resizeOriginX, resizeOriginY = 0, 0
  local resizeBaseW, resizeBaseH = 0, 0

  frame:SetScript("OnSizeChanged", function(_, w, h)
    w, h = math.floor(w), math.floor(h)
    sizeLabel:SetText(w .. " × " .. h)
    -- Only persist to db on mouseup; avoid thousands of writes during drag.
    if not resizing then
      db.ui.w, db.ui.h = w, h
    end
    if UI.resAnchor then applyContentHostLayout(UI.resAnchor, 0) end
    if UI.syncHistoryWidth then UI.syncHistoryWidth() end
  end)

  -- Grip button (BOTTOMRIGHT corner)
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
  grip:SetFrameLevel(frame:GetFrameLevel() + 10)

  grip:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      -- Re-anchor to TOPLEFT before resizing so the top-left corner stays fixed.
      local left = frame:GetLeft()
      local top  = frame:GetTop()
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
      db.ui.point, db.ui.x, db.ui.y = "TOPLEFT", left, top

      resizing = true
      resizeOriginX, resizeOriginY = GetCursorPosition()
      resizeBaseW = frame:GetWidth()
      resizeBaseH = frame:GetHeight()
      sizeLabel:Show()
    end
  end)

  grip:SetScript("OnUpdate", function()
    if not resizing then return end
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    local w = math.max(MIN_W, math.min(MAX_W, resizeBaseW + (cx - resizeOriginX) / scale))
    local h = math.max(MIN_H, math.min(MAX_H, resizeBaseH - (cy - resizeOriginY) / scale))
    frame:SetSize(w, h)
  end)

  grip:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and resizing then
      resizing = false
      sizeLabel:Hide()
      local w = math.floor(math.max(MIN_W, math.min(MAX_W, frame:GetWidth())))
      local h = math.floor(math.max(MIN_H, math.min(MAX_H, frame:GetHeight())))
      frame:SetSize(w, h)
      db.ui.w, db.ui.h = w, h
      if UI.resAnchor then applyContentHostLayout(UI.resAnchor, 0) end
      if UI.syncHistoryWidth then UI.syncHistoryWidth() end
    elseif button == "RightButton" then
      frame:SetSize(FRAME_W, FRAME_H)
      db.ui.w, db.ui.h = FRAME_W, FRAME_H
      if UI.resAnchor then applyContentHostLayout(UI.resAnchor, 0) end
      if UI.syncHistoryWidth then UI.syncHistoryWidth() end
    end
  end)

  -- Main body: sidebar (left) + content (right)
  local body = CreateFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD_X, -34)
  body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD_X, PAD_X)
  UI.body = body

  local sidebar = CreateFrame("Frame", nil, body, "BackdropTemplate")
  sidebar:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  sidebar:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
  sidebar:SetWidth(SIDEBAR_W)
  sidebar:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8", edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
  sidebar:SetBackdropColor(0.06, 0.05, 0.04, 0.55)
  sidebar:SetBackdropBorderColor(0.3, 0.25, 0.15, 0.45)
  UI.sidebar = sidebar

  local content = CreateFrame("Frame", nil, body)
  content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", GUTTER, 0)
  content:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  UI.content = content

  -- Barres
  local hpBar = CreateFrame("StatusBar", nil, content)
  UI.hpBar = hpBar
  hpBar:SetHeight(20)
  hpBar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  hpBar:SetPoint("RIGHT", content, "RIGHT", 0, 0)
  hpBar:SetMinMaxValues(0, 1)
  hpBar:SetValue(1)
  skinBar(hpBar, 0.85, 0.12, 0.12) -- rouge

  local hpText = hpBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  UI.hpText = hpText
  hpText:SetPoint("CENTER")


  local blockOverlay = hpBar:CreateTexture(nil, "OVERLAY")
  UI.hpBlockOverlay = blockOverlay
  blockOverlay:SetTexture("Interface/Buttons/WHITE8x8")
  blockOverlay:SetColorTexture(0.65, 0.65, 0.65, 0.55)
  blockOverlay:SetPoint("TOP", hpBar, "TOP", 0, 0)
  blockOverlay:SetPoint("BOTTOM", hpBar, "BOTTOM", 0, 0)
  blockOverlay:Hide()

  local magicOverlay = hpBar:CreateTexture(nil, "OVERLAY")
  UI.hpMagicBlockOverlay = magicOverlay
  magicOverlay:SetTexture("Interface/Buttons/WHITE8x8")
  magicOverlay:SetColorTexture(1.0, 0.82, 0.22, 0.60) -- doré
  magicOverlay:SetPoint("TOP", hpBar, "TOP", 0, 0)
  magicOverlay:SetPoint("BOTTOM", hpBar, "BOTTOM", 0, 0)
  magicOverlay:Hide()

  -- Marqueurs 50/25/10%
  local makeMarker = Shared.MakeMarker
  UI.hpMarkers = {}
  UI.hpMarkers[1] = makeMarker(hpBar, 0.50, 1, 1, 1, 0.35, 2)
  UI.hpMarkers[2] = makeMarker(hpBar, 0.25, 1.0, 0.65, 0.1, 0.45, 2)
  UI.hpMarkers[3] = makeMarker(hpBar, 0.10, 1.0, 0.15, 0.15, 0.55, 2)

  local capMarker = makeMarker(hpBar, 1.0, 1.0, 0.9, 0.2, 0.7, 3)
  UI.hpCapMarker = capMarker

  -- HP marker cache and reposition function — defined once here, called from OnChange and OnSizeChanged.
  UI.hpMarkerCache = { baseMaxHp = 0, effMaxHp = 0, cap = 1.0 }

  local function repositionHpMarkers()
    local cache = UI.hpMarkerCache
    local bMaxHp = cache.baseMaxHp
    local eMaxHp = cache.effMaxHp
    local barW   = hpBar:GetWidth() or 0

    for i = 1, #UI.hpMarkers do
      local m = UI.hpMarkers[i]
      local thresholdHp = bMaxHp * (m.pct or 0)
      local x = (eMaxHp > 0) and (barW * (thresholdHp / eMaxHp)) or 0
      if x < 0 then x = 0 elseif x > barW then x = barW end
      m:Show()
      m:ClearAllPoints()
      m:SetPoint("LEFT", hpBar, "LEFT", x, 0)
    end

    if UI.hpCapMarker then
      if cache.cap >= 0.999 then
        UI.hpCapMarker:Hide()
      else
        UI.hpCapMarker:Show()
        local capHp = bMaxHp * cache.cap
        local xCap = (eMaxHp > 0) and (barW * (capHp / eMaxHp)) or 0
        if xCap < 0 then xCap = 0 elseif xCap > barW then xCap = barW end
        UI.hpCapMarker:ClearAllPoints()
        UI.hpCapMarker:SetPoint("LEFT", hpBar, "LEFT", xCap, 0)
      end
    end
  end
  UI.repositionHpMarkers = repositionHpMarkers

  hpBar:SetScript("OnSizeChanged", function()
    repositionHpMarkers()
  end)

  local capText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  UI.capText = capText
  capText:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, -6)
  capText:SetText("")

  -- Ressource bars (up to 4, depending on selected class)
  UI.resBars = {}
  UI.resTexts = {}
  local RES_BAR_H = 14
  local RES_GAP = 4

  local function mkResBar(idx)
    local bar = CreateFrame("StatusBar", nil, content)
    UI.resBars[idx] = bar
    bar:SetHeight(RES_BAR_H)
    if idx == 1 then
      bar:SetPoint("TOPLEFT", capText, "BOTTOMLEFT", 0, -8)
    else
      bar:SetPoint("TOPLEFT", UI.resBars[idx - 1], "BOTTOMLEFT", 0, -RES_GAP)
    end
    bar:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    skinBar(bar, 0.2, 0.55, 1.0)
    bar:Hide()

    -- Optional stacked segments (used for Shaman: 4 elements in 1 bar)
    if idx == 1 then
      bar._stackSegs = {}
      for j = 1, 4 do
        local seg = bar:CreateTexture(nil, "OVERLAY")
        seg:SetTexture("Interface\\Buttons\\WHITE8x8")
        seg:SetVertexColor(1, 1, 1, 1)
        seg:Hide()
        bar._stackSegs[j] = seg
      end
    end

    local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.resTexts[idx] = txt
    txt:SetPoint("CENTER")
    return bar
  end

  for i = 1, 5 do
    mkResBar(i)
  end

  -- Warlock Corruption thresholds (max always 60)
  UI.corruptionMarkers = {}
  do
    local bar = UI.resBars[2]
    if bar then
      UI.corruptionMarkers[1] = makeMarker(bar, 10/60, 0.65, 0.95, 0.65, 0.55, 2)
      UI.corruptionMarkers[2] = makeMarker(bar, 25/60, 1.00, 0.82, 0.22, 0.55, 2)
      UI.corruptionMarkers[3] = makeMarker(bar, 45/60, 1.00, 0.25, 0.25, 0.65, 3)
    end
  end

  -- Shadow Priest Insanity thresholds (no max; bar display caps at 25)
  UI.insanityMarkers = {}
  do
    local bar = UI.resBars[2]
    if bar then
      UI.insanityMarkers[1] = makeMarker(bar, 4/25,  0.65, 0.95, 0.65, 0.45, 2)
      UI.insanityMarkers[2] = makeMarker(bar, 12/25, 1.00, 0.82, 0.22, 0.55, 2)
      UI.insanityMarkers[3] = makeMarker(bar, 20/25, 1.00, 0.55, 0.10, 0.60, 2)
      UI.insanityMarkers[4] = makeMarker(bar, 25/25, 1.00, 0.25, 0.25, 0.70, 3)
    end
  end

  -- Bars are driven by Core.OnChange; keep them hidden until then.

  -- Content host (pages) sits under HP/Resource bars and above class strip.
  local CONTENT_VPAD_BASE = 20

  applyContentHostLayout = function(anchor, extraVertical)
    if not UI.contentHost then return end
    -- Always keep a baseline vertical inset, then split extra height to stay centered.
    local dynamicPad = math.max(0, math.floor((extraVertical or 0) / 2))
    local topPad = CONTENT_VPAD_BASE + dynamicPad
    local bottomPad = CONTENT_VPAD_BASE + dynamicPad

    UI.contentHost:ClearAllPoints()
    UI.contentHost:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -topPad)
    UI.contentHost:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -topPad)
    UI.contentHost:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, bottomPad)
    UI.contentHost:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, bottomPad)
  end

  local contentHost = CreateFrame("Frame", nil, content)
  UI.contentHost = contentHost
  applyContentHostLayout(hpBar, 0)

  -- Row anchor system: invisible frames that auto-center horizontally on resize.
  local rowAnchors = {}

  local function registerRowAnchor(f, parent, w, y)
    local function reposition()
      local cw = parent:GetWidth() or 0
      if cw <= 0 then cw = CONTENT_W end
      local x = math.max(0, math.floor((cw - w) / 2))
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    f._reposition = reposition
    rowAnchors[#rowAnchors + 1] = f
    reposition()
  end

  local function mkRowAnchor(parent, w, y)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, 1)
    registerRowAnchor(f, parent, w, y)
    return f
  end

  contentHost:SetScript("OnSizeChanged", function()
    for i = 1, #rowAnchors do
      local f = rowAnchors[i]
      if f._reposition then f._reposition() end
    end
  end)

  UI.tabs = {}
  UI.pages = {}
  UI.tabDisabled = {}
  UI.tabHidden = {}
  UI.activeTab = 1

  local function setTab(active)
    if UI.tabDisabled and UI.tabDisabled[active] then
      return
    end
    if UI.tabHidden and UI.tabHidden[active] then
      setTab(1)
      return
    end
    UI.activeTab = active

    for i = 1, #UI.pages do
      if i == active then UI.pages[i]:Show() else UI.pages[i]:Hide() end
    end
    for i = 1, #UI.tabs do
      local b = UI.tabs[i]
      if not (UI.tabHidden and UI.tabHidden[i]) then
        local disabled = UI.tabDisabled and UI.tabDisabled[i]
        if i == active then
          b:Disable()
          if b._bg then b._bg:SetColorTexture(0.20, 0.20, 0.24, 0.95) end
          if b._accent then b._accent:Show() end
          if b._text and b._text.SetTextColor then b._text:SetTextColor(1, 1, 1, 1) end
        elseif disabled then
          b:Disable()
          if b._bg then b._bg:SetColorTexture(0.10, 0.10, 0.11, 0.55) end
          if b._accent then b._accent:Hide() end
          if b._text and b._text.SetTextColor then b._text:SetTextColor(0.50, 0.50, 0.50, 1) end
        else
          b:Enable()
          if b._bg then b._bg:SetColorTexture(0.12, 0.12, 0.14, 0.75) end
          if b._accent then b._accent:Hide() end
          if b._text and b._text.SetTextColor then b._text:SetTextColor(0.9, 0.9, 0.9, 1) end
        end
      end
    end

    if active == 7 and UI.syncHistoryWidth then
      UI.syncHistoryWidth()
    end
  end

  -- Sidebar navigation (vertical tabs)
  local TAB_TEXTS = {
    "Points de vie",
    "Ressources",
    "Classes",
    "Armure & blocage",
    "Actions",
    "Familier",
    "Historique",
  }

  local NAV_PAD = 10
  local NAV_GAP = 6
  local NAV_BTN_H = 28

  local function mkTab(text, idx)
    local tab = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
    tab:SetSize(SIDEBAR_W - (NAV_PAD * 2), NAV_BTN_H)
    tab:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
    tab:SetBackdropBorderColor(0, 0, 0, 0.70)

    local tabBg = tab:CreateTexture(nil, "BACKGROUND")
    tabBg:SetAllPoints(tab)
    tabBg:SetTexture("Interface/Buttons/WHITE8x8")
    tabBg:SetColorTexture(0.12, 0.12, 0.14, 0.75)
    tab._bg = tabBg

    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(tab)
    hl:SetTexture("Interface/Buttons/WHITE8x8")
    hl:SetColorTexture(1, 1, 1, 0.06)

    local accent = tab:CreateTexture(nil, "ARTWORK")
    accent:SetTexture("Interface/Buttons/WHITE8x8")
    accent:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    accent:SetColorTexture(1.0, 0.82, 0.22, 0.85)
    accent:Hide()
    tab._accent = accent

    local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", tab, "LEFT", 10, 0)
    fs:SetPoint("RIGHT", tab, "RIGHT", -10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    tab._text = fs

    tab:SetScript("OnClick", function() setTab(idx) end)

    if idx == 1 then
      tab:SetPoint("TOPLEFT", sidebar, "TOPLEFT", NAV_PAD, -NAV_PAD)
    else
      tab:SetPoint("TOPLEFT", UI.tabs[idx - 1], "BOTTOMLEFT", 0, -NAV_GAP)
    end

    UI.tabs[idx] = tab
    return tab
  end

  local function mkPage()
    local p = CreateFrame("Frame", nil, contentHost)
    p:SetAllPoints(contentHost)
    p:Hide()
    table.insert(UI.pages, p)
    return p
  end

  local function repositionSidebarTabs()
    local prev = nil
    for i = 1, #UI.tabs do
      local tab = UI.tabs[i]
      if not tab then break end
      if UI.tabHidden and UI.tabHidden[i] then
        tab:Hide()
      else
        tab:Show()
        tab:ClearAllPoints()
        if not prev then
          tab:SetPoint("TOPLEFT", sidebar, "TOPLEFT", NAV_PAD, -NAV_PAD)
        else
          tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -NAV_GAP)
        end
        prev = tab
      end
    end
  end

  for i = 1, #TAB_TEXTS do
    mkTab(TAB_TEXTS[i], i)
  end

  local pageHP = mkPage()
  local pageRes = mkPage()
  local pageClasses = mkPage()
  local pageArmor = mkPage()
  local pageCombat = mkPage()
  local pagePet = mkPage()
  local pageHistory = mkPage()
  UI.pageHistory = pageHistory
  UI.pagePet = pagePet

  -- Onglet 1 : PV
  local hpCur, hpMax, tempHpEB

  local function applyAllHP()
    local hpCurVal = getNumber(hpCur)
    local hpMaxVal = getNumber(hpMax)
    local tempHpVal = getNumber(tempHpEB)
    Core.SetHP(hpCurVal, hpMaxVal)
    Core.SetBonusHP(tempHpVal)
  end

  local aHP1 = mkRowAnchor(pageHP, 360, -4)
  mkLabel(aHP1, "PV", 0, -2)
  mkLabel(aHP1, "/", 112, -2)
  hpCur = mkEdit(aHP1, 70, 20, 36, 0, applyAllHP)
  hpMax = mkEdit(aHP1, 70, 20, 126, 0, applyAllHP)

  local aHP2 = mkRowAnchor(pageHP, 362, -36)
  mkLabel(aHP2, "PV bonus", 0, -2)
  tempHpEB = mkEdit(aHP2, 70, 20, 120, 0, applyAllHP)
  mkButton(aHP2, "Appliquer", 90, 20, 206, 0, applyAllHP)

  -- Onglet 2 : Ressource
  local aResHeader = mkRowAnchor(pageRes, 420, -6)
  UI.resPageLabel = mkLabel(aResHeader, "Ressource", 0, 0)

  local resDeltaEB
  local aResControls = mkRowAnchor(pageRes, 420, -32)
  UI.resDeltaLabel = mkLabel(aResControls, "Valeur (±)", 0, -2)
  resDeltaEB = mkEdit(aResControls, 70, 20, 96, 0)
  UI.resDeltaEB = resDeltaEB

  UI.resRow = UI.resRow or {}
  UI.resRowLabel = UI.resRowLabel or {}
  UI.resRowCur = UI.resRowCur or {}
  UI.resRowMax = UI.resRowMax or {}

  local function applyAllRes()
    local snapshots = {}
    for i = 1, 5 do
      local row = UI.resRow[i]
      if row and row:IsShown() then
        snapshots[#snapshots + 1] = {
          idx = row.resIdx or i,
          cur = getNumber(UI.resRowCur[i]),
          max = getNumber(UI.resRowMax[i]),
        }
      end
    end
    for _, v in ipairs(snapshots) do
      if Core and Core.SetResIndex then
        Core.SetResIndex(v.idx, v.cur, v.max)
      end
    end
  end

  mkButton(aResControls, "Appliquer", 90, 20, 176, 0, applyAllRes)

  local function mkResRow(idx, y)
    local row = CreateFrame("Frame", nil, pageRes)
    row:SetSize(330, 24)
    registerRowAnchor(row, pageRes, 330, y)
    row.resIdx = idx
    UI.resRow[idx] = row
    row:Hide()

    local label = mkLabel(row, "Ressource", 0, 0)
    UI.resRowLabel[idx] = label

    local curEB, maxEB
    mkLabel(row, "/", 172, 0)

    curEB = mkEdit(row, 70, 20, 96, 2, applyAllRes)
    maxEB = mkEdit(row, 70, 20, 186, 2, applyAllRes)
    UI.resRowCur[idx] = curEB
    UI.resRowMax[idx] = maxEB

    mkButton(row, "+", 28, 20, 270, 2, function()
      if Core and Core.AddResIndex then
        local targetIdx = row.resIdx or idx
        Core.AddResIndex(targetIdx, getNumber(resDeltaEB) or 0)
      end
    end)
    mkButton(row, "-", 28, 20, 302, 2, function()
      if Core and Core.AddResIndex then
        local targetIdx = row.resIdx or idx
        Core.AddResIndex(targetIdx, -(getNumber(resDeltaEB) or 0))
      end
    end)

    return row
  end

  -- Rows are shown/hidden based on selected class.
  mkResRow(1, -60)
  mkResRow(2, -88)
  mkResRow(3, -116)
  mkResRow(4, -144)
  mkResRow(5, -172)

  UI.noResHint = mkLabelCenter(pageRes, "Aucune ressource pour cette classe.", 0, -110)
  UI.noResHint:Hide()

  -- Resources tab can be disabled for classes without resources (eg Warrior).

  -- Onglet 2 : Armure & Blocage
  local armorEB, trueArmorEB, dodgeEB, blockEB, magicBlockEB

  local function applyAllArmor()
    local armorVal = getNumber(armorEB)
    local trueArmorVal = getNumber(trueArmorEB)
    local dodgeVal = getNumber(dodgeEB)
    local blockVal = getNumber(blockEB)
    local magicVal = getNumber(magicBlockEB)
    Core.SetArmor(armorVal, trueArmorVal)
    Core.SetDodge(dodgeVal)
    Core.SetTempBlock(blockVal)
    Core.SetTempMagicBlock(magicVal)
  end

  -- ── Armure & Esquive (2 colonnes, ~320 px) ──────────
  local aArmor1 = mkRowAnchor(pageArmor, 320, -4)
  mkLabel(aArmor1, "Armure", 0, -2)
  armorEB     = mkEdit(aArmor1, 70, 20, 64, 0, applyAllArmor)
  mkLabel(aArmor1, "Armure invul", 154, -2)
  trueArmorEB = mkEdit(aArmor1, 70, 20, 248, 0, applyAllArmor)

  local aArmor2 = mkRowAnchor(pageArmor, 180, -34)
  mkLabel(aArmor2, "Esquive", 0, -2)
  dodgeEB = mkEdit(aArmor2, 70, 20, 64, 0, applyAllArmor)

  local aArmorApply = mkRowAnchor(pageArmor, 90, -64)
  mkButton(aArmorApply, "Appliquer", 90, 20, 0, 0, applyAllArmor)

  -- ── Blocage temporaire ──────────────
  local aBlock1 = mkRowAnchor(pageArmor, 280, -100)
  mkLabel(aBlock1, "Blocage (temp.)", 0, -2)
  blockEB = mkEdit(aBlock1, 70, 20, 130, 0, applyAllArmor)
  mkButton(aBlock1, "Réinit.", 70, 20, 210, 0, function() Core.ResetTempBlock() end)

  local aBlock2 = mkRowAnchor(pageArmor, 340, -130)
  mkLabel(aBlock2, "Blocage magique (temp.)", 0, -2)
  magicBlockEB = mkEdit(aBlock2, 70, 20, 190, 0, applyAllArmor)
  mkButton(aBlock2, "Réinit.", 70, 20, 270, 0, function() Core.ResetTempMagicBlock() end)

  -- Onglet 5 : Actions (Dégâts & Soins)
  local actValEB

  local function doDmgArmor() Core.DamageWithArmor(getNumber(actValEB) or 0) end
  local function doDmgTrue()  Core.DamageTrue(getNumber(actValEB) or 0) end
  local function doHeal()     Core.Heal(getNumber(actValEB) or 0) end

  local aActVal = mkRowAnchor(pageCombat, 180, -4)
  mkLabel(aActVal, "Valeur", 0, -2)
  actValEB = mkEdit(aActVal, 80, 20, 56, 0, doDmgArmor)

  local aActBtns1 = mkRowAnchor(pageCombat, 392, -36)
  mkButton(aActBtns1, "Dégâts (armure)", 190, 22, 0,   0, doDmgArmor)
  mkButton(aActBtns1, "Dégâts (bruts)",  190, 22, 202, 0, doDmgTrue)

  local aActBtns2 = mkRowAnchor(pageCombat, 392, -64)
  mkButton(aActBtns2, "Soins",               190, 22, 0,   0, doHeal)
  mkButton(aActBtns2, "Soins divins (75%)",  190, 22, 202, 0, function() Core.DivineHeal() end)

  -- Onglet 7 : Historique
  do
    local sf = CreateFrame("ScrollFrame", nil, pageHistory, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", pageHistory, "TOPLEFT", 2, -4)
    sf:SetPoint("BOTTOMRIGHT", pageHistory, "BOTTOMRIGHT", -20, 44)
    UI.historyScroll = sf

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(CONTENT_W - 64, 10)
    sf:SetScrollChild(child)
    UI.historyChild = child

    local txt = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txt:SetPoint("TOPLEFT", 0, 0)
    txt:SetJustifyH("LEFT")
    txt:SetJustifyV("TOP")
    txt:SetWidth(CONTENT_W - 72)
    txt:SetText("")
    UI.historyText = txt

    local function syncHistoryWidth()
      if not UI.historyScroll or not UI.historyChild or not UI.historyText then return end
      local w = UI.historyScroll:GetWidth() or 0
      if w <= 0 then return end
      -- Keep a small right gutter so text never overlaps the scrollbar lane.
      local textW = math.max(80, w - 14)
      UI.historyChild:SetWidth(textW)
      UI.historyText:SetWidth(textW)
    end
    UI.syncHistoryWidth = syncHistoryWidth
    sf:SetScript("OnSizeChanged", syncHistoryWidth)
    syncHistoryWidth()

    local clearBtn = mkButton(pageHistory, "Effacer", 90, 20, 0, 0)
    clearBtn:ClearAllPoints()
    clearBtn:SetPoint("BOTTOMLEFT", pageHistory, "BOTTOMLEFT", 14, 12)
    clearBtn:SetScript("OnClick", function()
      if Core and Core.ClearHistory then Core.ClearHistory() end
    end)
    UI.historyClear = clearBtn
  end

  -- Onglet 8 : Familier
  local petToggleBtn
  local petNameEB
  local petHpCurEB, petHpMaxEB
  local petArmorEB, petTrueArmorEB, petDodgeEB, petMagicBlockEB
  local petActionValEB

  local function applyAllPet()
    if not Core then return end
    local petNameVal = petNameEB and petNameEB:GetText() or nil
    local petHpCurVal = getNumber(petHpCurEB)
    local petHpMaxVal = getNumber(petHpMaxEB)
    local armorVal = getNumber(petArmorEB)
    local trueArmorVal = getNumber(petTrueArmorEB)
    local dodgeVal = getNumber(petDodgeEB)
    local magicVal = getNumber(petMagicBlockEB)
    if Core.SetPetName and petNameVal then Core.SetPetName(petNameVal) end
    if Core.SetPetHP then Core.SetPetHP(petHpCurVal, petHpMaxVal) end
    if Core.SetPetArmor then Core.SetPetArmor(armorVal, trueArmorVal) end
    if Core.SetPetDodge then Core.SetPetDodge(dodgeVal) end
    if Core.SetPetTempMagicBlock then Core.SetPetTempMagicBlock(magicVal) end
  end

  -- ── Identité ──────────────────────
  local aPetToggle = mkRowAnchor(pagePet, 170, -6)
  petToggleBtn = mkButton(aPetToggle, "Activer le familier", 170, 22, 0, 0, function()
    if not Core or not Core.SetPetEnabled then return end
    local p = Core.GetPet and Core.GetPet() or nil
    Core.SetPetEnabled(not (p and p.enabled))
  end)

  local aPetNom = mkRowAnchor(pagePet, 230, -38)
  mkLabel(aPetNom, "Nom", 0, -2)
  petNameEB = mkEdit(aPetNom, 180, 20, 46, 0, applyAllPet)
  petNameEB:SetNumeric(false)

  local aPetHP = mkRowAnchor(pagePet, 230, -68)
  mkLabel(aPetHP, "PV", 0, -2)
  petHpCurEB = mkEdit(aPetHP, 70, 20, 30,  0, applyAllPet)
  mkLabel(aPetHP, "/", 106, -2)
  petHpMaxEB = mkEdit(aPetHP, 70, 20, 120, 0, applyAllPet)

  -- ── Défense (2 colonnes, ~320 px) ────────────────────
  -- Col1: x=0..133  Col2: x=150..313
  local aPetDef1 = mkRowAnchor(pagePet, 320, -106)
  mkLabel(aPetDef1, "Armure", 0, -2)
  petArmorEB     = mkEdit(aPetDef1, 70, 20, 60, 0, applyAllPet)
  mkLabel(aPetDef1, "Armure invul", 150, -2)
  petTrueArmorEB = mkEdit(aPetDef1, 70, 20, 244, 0, applyAllPet)

  local aPetDef2 = mkRowAnchor(pagePet, 320, -136)
  mkLabel(aPetDef2, "Esquive", 0, -2)
  petDodgeEB      = mkEdit(aPetDef2, 70, 20, 60, 0, applyAllPet)
  mkLabel(aPetDef2, "Bouclier mag.", 150, -2)
  petMagicBlockEB = mkEdit(aPetDef2, 70, 20, 244, 0, applyAllPet)

  local aPetDefBtns = mkRowAnchor(pagePet, 180, -166)
  mkButton(aPetDefBtns, "Appliquer", 86, 20, 0,  0, applyAllPet)
  mkButton(aPetDefBtns, "Réinit.",   86, 20, 94, 0, function()
    if Core and Core.ResetPetTempMagicBlock then
      Core.ResetPetTempMagicBlock()
    elseif Core and Core.SetPetTempMagicBlock then
      Core.SetPetTempMagicBlock(0)
    end
  end)

  -- ── Actions ───────────────────────
  local aPetVal = mkRowAnchor(pagePet, 180, -202)
  mkLabel(aPetVal, "Valeur", 0, -2)
  petActionValEB = mkEdit(aPetVal, 80, 20, 56, 0)

  local aPetBtns1 = mkRowAnchor(pagePet, 392, -232)
  local petDmgArmorBtn = mkButton(aPetBtns1, "Dégâts (armure)", 190, 22, 0,   0, function()
    if Core and Core.PetDamageWithArmor then Core.PetDamageWithArmor(getNumber(petActionValEB) or 0) end
  end)
  local petDmgTrueBtn = mkButton(aPetBtns1, "Dégâts (bruts)", 190, 22, 202, 0, function()
    if Core and Core.PetDamageTrue then Core.PetDamageTrue(getNumber(petActionValEB) or 0) end
  end)

  local aPetBtns2 = mkRowAnchor(pagePet, 392, -260)
  local petHealBtn = mkButton(aPetBtns2, "Soins", 190, 22, 0, 0, function()
    if Core and Core.PetHeal then Core.PetHeal(getNumber(petActionValEB) or 0) end
  end)
  local petDivineBtn = mkButton(aPetBtns2, "Soins divins (75%)", 190, 22, 202, 0, function()
    if Core and Core.PetDivineHeal then Core.PetDivineHeal() end
  end)

  UI.inputs = {
    hpCur = hpCur, hpMax = hpMax,
    tempHp = tempHpEB,
    armor = armorEB, trueArmor = trueArmorEB,
    dodge = dodgeEB,
    block = blockEB,
    magicBlock = magicBlockEB,
    petName = petNameEB,
    petHpCur = petHpCurEB,
    petHpMax = petHpMaxEB,
    petArmor = petArmorEB,
    petTrueArmor = petTrueArmorEB,
    petDodge = petDodgeEB,
    petMagicBlock = petMagicBlockEB,
    petActionVal = petActionValEB,
  }

  UI.petToggleBtn = petToggleBtn
  UI.petControls = {
    petNameEB, petHpCurEB, petHpMaxEB,
    petArmorEB, petTrueArmorEB, petDodgeEB,
    petMagicBlockEB, petActionValEB,
  }
  UI.petButtons = { petDmgArmorBtn, petDmgTrueBtn, petHealBtn, petDivineBtn }

  setTab(1)

  local CLASS_BTN_SIZE = 60
  local CLASS_BTN_GAP_X = 8
  local CLASS_BTN_GAP_Y = 8

  -- Onglet 3 : Classes (sélection de classe)
  local classStrip = CreateFrame("Frame", nil, pageClasses)
  classStrip:SetPoint("TOPLEFT", pageClasses, "TOPLEFT", 0, -20)
  classStrip:SetPoint("TOPRIGHT", pageClasses, "TOPRIGHT", 0, -20)
  classStrip:SetHeight((CLASS_BTN_SIZE * 2) + CLASS_BTN_GAP_Y)
  UI.classStrip = classStrip

  -- Class icon selector buttons
  UI.classButtons = {}
  local CLASS_KEYS = {
    "WARRIOR",
    "MEDIC",
    "PALADIN",
    "PRIEST",
    "SHADOWPRIEST",
    "MAGE",
    "ROGUE",
    "WARLOCK",
    "DRUID",
    "MONK",
    "SHAMAN",
  }

  -- Pre-compute row anchor widths for class buttons.
  local classBtnPerRow = math.ceil(#CLASS_KEYS / 2)
  local classRow2Count = #CLASS_KEYS - classBtnPerRow
  local classRow1W = (classBtnPerRow  * CLASS_BTN_SIZE) + ((classBtnPerRow  - 1) * CLASS_BTN_GAP_X)
  local classRow2W = (classRow2Count  * CLASS_BTN_SIZE) + ((classRow2Count  - 1) * CLASS_BTN_GAP_X)
  local aClassRow1 = mkRowAnchor(classStrip, classRow1W, 0)
  local aClassRow2 = mkRowAnchor(classStrip, classRow2W, -(CLASS_BTN_SIZE + CLASS_BTN_GAP_Y))

  local function mkClassButton(idx, classKey)
    local b = CreateFrame("Button", nil, classStrip, "BackdropTemplate")
    b:SetSize(CLASS_BTN_SIZE, CLASS_BTN_SIZE)
    b.classKey = classKey
    b:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
    b:SetBackdropBorderColor(0, 0, 0, 0.85)

    local row = (idx <= classBtnPerRow) and 1 or 2
    local idxInRow = (row == 1) and idx or (idx - classBtnPerRow)
    local anchor = (row == 1) and aClassRow1 or aClassRow2
    local x = (idxInRow - 1) * (CLASS_BTN_SIZE + CLASS_BTN_GAP_X)
    b:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, 0)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.tex = tex
    setClassIconTexCoords(tex, classKey)

    b:SetScript("OnClick", function()
      if Core and Core.SetClassKey then Core.SetClassKey(classKey) end
    end)

    UI.classButtons[idx] = b
    return b
  end

  for i = 1, #CLASS_KEYS do
    mkClassButton(i, CLASS_KEYS[i])
  end

  Core.OnChange(function(s)
    local baseMaxHp = (s.maxHp or 0)
    local bonusHp = math.max(0, s.bonusHp or 0)
    local effMaxHp = baseMaxHp + bonusHp
    local hpNow = (s.hp or 0)

    local hpPct = (effMaxHp > 0) and (hpNow / effMaxHp) or 0
    hpBar:SetValue(math.max(0, math.min(1, hpPct)))

    if bonusHp > 0 then
      hpText:SetText(string.format("PV : %d / %d (+%d bonus, %d%%)", hpNow, effMaxHp, bonusHp, roundPct(hpPct)))
    else
      hpText:SetText(string.format("PV : %d / %d (%d%%)", s.hp or 0, baseMaxHp, roundPct(hpPct)))
    end

    -- Overlays Blocage (gris) + Blocage magique (doré)
    Shared.UpdateHpShieldOverlays(
      UI.hpBlockOverlay, UI.hpMagicBlockOverlay, hpBar,
      hpNow, effMaxHp,
      s.tempBlock or 0, s.tempMagicBlock or 0
    )

    local cap
    local w2 = s.wounds
    if w2 and w2.hit10 then cap = 0.25
    elseif w2 and w2.hit25 then cap = 0.50
    else cap = 1.0 end

    -- Update HP marker cache then reposition.
    UI.hpMarkerCache.baseMaxHp = baseMaxHp
    UI.hpMarkerCache.effMaxHp  = effMaxHp
    UI.hpMarkerCache.cap       = cap
    UI.repositionHpMarkers()

    if cap >= 0.999 then
      capText:SetText("")
    else
      capText:SetText(string.format("Plafond de soins : %d%%", roundPct(cap)))
    end

    -- Ressource
    local profile = getResProfile(s)
    local rowCount = #profile
    local barCount
    if s.classKey == "SHAMAN" then
      local hasAuthority = false
      for i = 1, rowCount do
        if profile[i] and profile[i].idx == 5 then
          hasAuthority = true
          break
        end
      end
      barCount = (rowCount > 0) and (hasAuthority and 5 or 1) or 0
    else
      barCount = rowCount
    end

    if UI.resPageLabel and UI.resPageLabel.SetText then
      local headerText
      if rowCount == 0 then
        headerText = "Aucune ressource"
      elseif rowCount == 1 and profile[1] and profile[1].idx == 5 then
        headerText = profile[1].label or "Ressource"
      else
        headerText = (CLASS_STYLES[s.classKey] and CLASS_STYLES[s.classKey].label) or "Ressource"
      end
      UI.resPageLabel:SetText(headerText)
    end

    if UI.noResHint then
      if rowCount == 0 then UI.noResHint:Show() else UI.noResHint:Hide() end
    end
    if UI.resDeltaLabel then
      if rowCount == 0 then UI.resDeltaLabel:Hide() else UI.resDeltaLabel:Show() end
    end
    if UI.resDeltaEB then
      if rowCount == 0 then UI.resDeltaEB:Hide() else UI.resDeltaEB:Show() end
    end

    -- Hide resources tab for Classique (WARRIOR) with no pet; disable for other no-resource classes.
    local hideRes = (s.classKey == "WARRIOR" and rowCount == 0)
    if UI.tabHidden then
      local wasHidden = UI.tabHidden[2]
      UI.tabHidden[2] = hideRes
      if wasHidden ~= hideRes then
        repositionSidebarTabs()
      end
    end
    if UI.tabDisabled then
      UI.tabDisabled[2] = (rowCount == 0)
      if (hideRes or UI.tabDisabled[2]) and UI.activeTab == 2 then
        setTab(1)
      else
        setTab(UI.activeTab or 1)
      end
    end

    -- Default: hide resource threshold markers; they'll be re-shown when applicable.
    hideMarkers(UI.corruptionMarkers)
    hideMarkers(UI.insanityMarkers)

    -- Position content host below the last visible resource bar.
    do
      local n = barCount
      if n < 0 then n = 0 end
      if n > 5 then n = 5 end

      local anchor = hpBar
      if n >= 1 and UI.resBars and UI.resBars[n] then
        anchor = UI.resBars[n]
      end

      UI.resAnchor = anchor
      applyContentHostLayout(anchor, 0)
    end

    if UI.syncHistoryWidth then
      UI.syncHistoryWidth()
    end

    for i = 1, 5 do
      local bar = UI.resBars and UI.resBars[i]
      local txt = UI.resTexts and UI.resTexts[i]
      local row = UI.resRow and UI.resRow[i]
      local rowLabel = UI.resRowLabel and UI.resRowLabel[i]
      local curEB = UI.resRowCur and UI.resRowCur[i]
      local maxEB = UI.resRowMax and UI.resRowMax[i]
      local p = profile[i]

      -- Shaman: display 4 resources in 1 stacked bar, but keep 4 edit rows.
      if s.classKey == "SHAMAN" and (not p or p.idx <= 4) then
        -- Bars: only use bar #1.
        if i ~= 1 then
          if bar then bar:Hide() end
          if txt then txt:SetText("") end
        end

        -- Rows: show/hide and bind each element.
        if not p then
          if row then
            row.resIdx = nil
            row:Hide()
          end
        else
          local resKey, maxKey = getKeysForIdx(p.idx)
          local cur = s[resKey] or 0
          local maxv = s[maxKey] or 0
          if row then
            row.resIdx = p.idx
            row:Show()
          end
          if rowLabel and rowLabel.SetText then rowLabel:SetText(p.label or "Ressource") end
          if curEB then setNumber(curEB, cur) end
          if maxEB then setNumber(maxEB, maxv) end

          -- Ensure max boxes are editable for Shaman (avoid staying disabled after WARLOCK/SHADOWPRIEST).
          setEditBoxEnabled(maxEB, true)
        end

        -- After the loop's first iteration, update the stacked bar visuals.
        if i == 1 and bar and bar._stackSegs then
          bar:Show()

          local totalMax = 0
          local totalCur = 0
          for j = 1, 4 do
            local pj = profile[j]
            if pj then
              local rk, mk = getKeysForIdx(pj.idx)
              local curJ = s[rk] or 0
              local maxJ = s[mk] or 0
              if maxJ > 0 and curJ > maxJ then curJ = maxJ end
              if curJ < 0 then curJ = 0 end
              totalCur = totalCur + curJ
              totalMax = totalMax + maxJ
            end
          end

          local pct = (totalMax > 0) and (totalCur / totalMax) or 0
          bar:SetValue(math.max(0, math.min(1, pct)))
          -- Hide base fill; segments provide the color.
          bar:SetStatusBarColor(0, 0, 0, 0)

          local wBar = bar:GetWidth() or 0
          local x = 0
          for j = 1, 4 do
            local seg = bar._stackSegs[j]
            local pj = profile[j]
            if seg and pj and totalMax > 0 and wBar > 0 then
              local rk, mk = getKeysForIdx(pj.idx)
              local curJ = s[rk] or 0
              local maxJ = s[mk] or 0
              if maxJ > 0 and curJ > maxJ then curJ = maxJ end
              if curJ < 0 then curJ = 0 end
              local segW = wBar * (curJ / totalMax)
              if segW > 0.5 then
                seg:Show()
                seg:SetVertexColor(pj.r, pj.g, pj.b, 0.95)
                seg:ClearAllPoints()
                seg:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
                seg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
                seg:SetWidth(segW)
                x = x + segW
              else
                seg:Hide()
              end
            elseif seg then
              seg:Hide()
            end
          end

          if txt then
            applyResTextColor(txt)
            txt:SetText(string.format(
              "Points élémentaires : %d / %d (%d%%)",
              totalCur,
              totalMax,
              roundPct(pct)
            ))
          end
        end

      else
        -- Default behavior: 1 bar per resource.
        if not p then
          if bar then bar:Hide() end
          if row then
            row.resIdx = nil
            row:Hide()
          end
        else
          -- Hide stacked segments if any
          if bar and bar._stackSegs then
            for j = 1, #bar._stackSegs do
              bar._stackSegs[j]:Hide()
            end
          end

          local resKey, maxKey = getKeysForIdx(p.idx)
          local cur = s[resKey] or 0
          local maxv = s[maxKey] or 0

          local isWarlockCorruption = (s.classKey == "WARLOCK" and p.idx == 2)
          local isShadowInsanity = (s.classKey == "SHADOWPRIEST" and p.idx == 2)

          local displayMax = maxv
          if isWarlockCorruption then
            maxv = 60
            if cur < 0 then cur = 0 elseif cur > 60 then cur = 60 end
            displayMax = 60
          elseif isShadowInsanity then
            -- No real maximum, but bar display caps at 25.
            displayMax = 25
            if cur < 0 then cur = 0 end
          end

          local pct = (displayMax and displayMax > 0) and (math.min(cur, displayMax) / displayMax) or 0

          if bar then
            bar:Show()
            bar:SetStatusBarColor(p.r, p.g, p.b, 1)
            bar:SetValue(math.max(0, math.min(1, pct)))
          end
          if txt then
            applyResTextColor(txt)
            if isWarlockCorruption then
              local tier
              if cur < 10 then
                tier = "Nulle"
              elseif cur < 25 then
                tier = "Passive"
              elseif cur < 45 then
                tier = "Moyenne"
              else
                tier = "Forte"
              end
              txt:SetText(string.format(
                "%s : %d / %d (%d%%) — %s",
                p.label or "Corruption",
                cur,
                maxv,
                roundPct(pct),
                tier
              ))
            elseif isShadowInsanity then
              local tier
              if cur < 4 then
                tier = "Nulle"
              elseif cur < 12 then
                tier = "Légère"
              elseif cur < 20 then
                tier = "Forte"
              elseif cur < 25 then
                tier = "Intense"
              else
                tier = "Folie latente"
              end
              txt:SetText(string.format(
                "%s : %d (%d%%) — %s",
                p.label or "Insanité",
                cur,
                roundPct(pct),
                tier
              ))
            else
              txt:SetText(string.format("%s : %d / %d (%d%%)", p.label or "Ressource", cur, maxv, roundPct(pct)))
            end
          end

          -- Threshold markers
          if isWarlockCorruption then
            positionMarkers(UI.corruptionMarkers, bar)
          elseif isShadowInsanity then
            positionMarkers(UI.insanityMarkers, bar)
          end

          if row then
            row.resIdx = p.idx
            row:Show()
          end
          if rowLabel and rowLabel.SetText then rowLabel:SetText(p.label or "Ressource") end
          if curEB then setNumber(curEB, cur) end
          if maxEB then
            if isShadowInsanity then
              setNumber(maxEB, 25)
            else
              setNumber(maxEB, maxv)
            end
          end

          -- Fixed/scaled max boxes.
          setEditBoxEnabled(maxEB, not (isWarlockCorruption or isShadowInsanity))
        end
      end
    end

    if UI.classButtons then
      for i = 1, #UI.classButtons do
        local b = UI.classButtons[i]
        if b and b.classKey then
          if b.classKey == s.classKey then
            b:SetAlpha(1)
            b:SetBackdropBorderColor(1, 1, 1, 0.9)
          else
            b:SetAlpha(0.75)
            b:SetBackdropBorderColor(0, 0, 0, 0.85)
          end
        end
      end
    end

    -- Inputs : on reflète la state (pratique MVP)
    setNumber(UI.inputs.hpCur, s.hp)
    setNumber(UI.inputs.hpMax, s.maxHp)
    setNumber(UI.inputs.tempHp, s.bonusHp)
    -- Resource inputs are handled per-row above.
    setNumber(UI.inputs.armor, s.armor)
    setNumber(UI.inputs.trueArmor, s.trueArmor)
    setNumber(UI.inputs.dodge, s.dodge)
    setNumber(UI.inputs.block, s.tempBlock)
    setNumber(UI.inputs.magicBlock, s.tempMagicBlock)

    local p = s.pet or {}
    local petEnabled = not not p.enabled
    if UI.petToggleBtn and UI.petToggleBtn.SetText then
      if petEnabled then
        UI.petToggleBtn:SetText("Désactiver le familier")
      else
        UI.petToggleBtn:SetText("Activer le familier")
      end
    end

    if UI.inputs.petName then
      if not (UI.inputs.petName.HasFocus and UI.inputs.petName:HasFocus()) then
        UI.inputs.petName:SetText(p.name or "Familier")
      end
      setEditBoxEnabled(UI.inputs.petName, true)
    end
    setNumber(UI.inputs.petHpCur, p.hp)
    setNumber(UI.inputs.petHpMax, p.maxHp)
    setNumber(UI.inputs.petArmor, p.armor)
    setNumber(UI.inputs.petTrueArmor, p.trueArmor)
    setNumber(UI.inputs.petDodge, p.dodge)
    setNumber(UI.inputs.petMagicBlock, p.tempMagicBlock)

    if UI.petControls then
      for i = 1, #UI.petControls do
        setEditBoxEnabled(UI.petControls[i], true)
      end
    end
    if UI.petButtons then
      for i = 1, #UI.petButtons do
        setButtonEnabled(UI.petButtons[i], petEnabled)
      end
    end

    -- Historique
    if UI.historyText and UI.historyChild then
      local hist = s.history
      local text = formatHistoryText(hist)
      if not text then
        UI.historyText:SetText("Aucun évènement récent.")
        UI.historyChild:SetHeight(20)
      else
        UI.historyText:SetText(text)
        local h = (UI.historyText.GetStringHeight and UI.historyText:GetStringHeight()) or 0
        UI.historyChild:SetHeight(math.max(20, h + 10))
      end
    end
  end)
end

function ns.UI_Show(show)
  local db = (ns.GetDB and ns.GetDB()) or rawget(_G, "GrosOrteilDBPC") or rawget(_G, "GrosOrteilDB") or {}
  db.ui = db.ui or {}
  db.ui.shown = not not show
  if show then UI.frame:Show() else UI.frame:Hide() end
end

function ns.UI_ResetPosition()
  local db = (ns.GetDB and ns.GetDB()) or rawget(_G, "GrosOrteilDBPC") or rawget(_G, "GrosOrteilDB") or {}
  db.ui = db.ui or {}
  db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0
  UI.frame:ClearAllPoints()
  UI.frame:SetPoint("CENTER")
end
