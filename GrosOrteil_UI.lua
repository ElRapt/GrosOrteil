local _, ns = ...
local Core = ns.Core
local History = ns.History
local Shared = ns.Shared

local UI = {}
ns.UI = UI

local getResProfile        = Shared.GetResProfile
local getKeysForIdx        = Shared.GetKeysForIdx
local hideMarkers          = Shared.HideMarkers
local positionMarkers      = Shared.PositionMarkers
local roundPct             = Shared.RoundPct

-- ═══════════════════════════════════════════════════════════════════════════
-- Design System : GrosOrteil Premium Theme
-- Warm amber/gold palette inspired by TRP3's rich WoW-authentic aesthetic.
-- ═══════════════════════════════════════════════════════════════════════════
local C = {
  -- Gold family
  GOLD          = { 1.00, 0.675, 0.125 },
  GOLD_BRIGHT   = { 1.00, 0.82,  0.22  },
  GOLD_LIGHT    = { 1.00, 0.90,  0.55  },
  GOLD_DIM      = { 0.85, 0.70,  0.40  },
  GOLD_MUTED    = { 0.55, 0.42,  0.18  },
  -- Brown family
  BROWN_DEEP    = { 0.08, 0.05,  0.02  },
  BROWN_DARK    = { 0.14, 0.09,  0.04  },
  BROWN_MED     = { 0.24, 0.17,  0.08  },
  BROWN_WARM    = { 0.32, 0.24,  0.12  },
  -- Cream / parchment
  CREAM         = { 0.92, 0.86,  0.74  },
  CREAM_DIM     = { 0.78, 0.72,  0.58  },
  -- Text hierarchy
  TEXT_TITLE    = { 1.00, 0.84,  0.30  },
  TEXT_BRIGHT   = { 1.00, 0.95,  0.80  },
  TEXT_NORMAL   = { 0.90, 0.84,  0.68  },
  TEXT_LABEL    = { 0.82, 0.74,  0.55  },
  TEXT_DIM      = { 0.60, 0.52,  0.36  },
  TEXT_DISABLED = { 0.40, 0.34,  0.22  },
  -- Functional
  RED_HP        = { 0.80, 0.15,  0.15  },
  BG_PANEL      = { 0.06, 0.04,  0.02  },
}

local TEX = {
  FLAT        = "Interface/Buttons/WHITE8x8",
  STATUSBAR   = "Interface/TargetingFrame/UI-StatusBar",
  BG_STONE    = "Interface/DialogFrame/UI-DialogBox-Background",
  BG_DARK     = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
  BORDER_GOLD = "Interface/DialogFrame/UI-DialogBox-Gold-Border",
  TOOLTIP_BG  = "Interface/Tooltips/UI-Tooltip-Background",
  TOOLTIP_BD  = "Interface/Tooltips/UI-Tooltip-Border",
}

-- Reusable backdrop definitions.
local BACKDROP_BUTTON = {
  bgFile   = TEX.TOOLTIP_BG,
  edgeFile = TEX.FLAT,
  edgeSize = 1,
  insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}
local BACKDROP_EDITBOX = {
  bgFile   = TEX.TOOLTIP_BG,
  edgeFile = TEX.FLAT,
  edgeSize = 1,
  insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}
local BACKDROP_SIDEBAR = {
  bgFile   = TEX.BG_DARK,
  edgeFile = TEX.FLAT,
  tile = true, tileSize = 32, edgeSize = 1,
  insets   = { left = 0, right = 0, top = 0, bottom = 0 },
}
local BACKDROP_FRAME = {
  bgFile   = TEX.BG_STONE,
  edgeFile = TEX.BORDER_GOLD,
  tile = true, tileSize = 32, edgeSize = 32,
  insets   = { left = 10, right = 10, top = 10, bottom = 10 },
}
local BACKDROP_CONTENT = {
  bgFile   = TEX.BG_STONE,
  edgeFile = TEX.TOOLTIP_BD,
  tile = true, tileSize = 32, edgeSize = 10,
  insets   = { left = 2, right = 2, top = 2, bottom = 2 },
}
local BACKDROP_TAB = {
  edgeFile = TEX.FLAT,
  edgeSize = 1,
}

local function applyResTextColor(txt)
  if not txt or not txt.SetTextColor then return end
  txt:SetTextColor(C.TEXT_BRIGHT[1], C.TEXT_BRIGHT[2], C.TEXT_BRIGHT[3], 1)
  txt:SetShadowOffset(1, -1)
  txt:SetShadowColor(0, 0, 0, 0.92)
end

local function setEditBoxEnabled(eb, enabled)
  if not eb then return end
  local wrap = eb._wrap
  if enabled then
    if eb.Enable then eb:Enable()
    elseif eb.EnableMouse then eb:EnableMouse(true) end
    if eb.SetAlpha then eb:SetAlpha(1) end
    if wrap and wrap.SetAlpha then wrap:SetAlpha(1) end
  else
    if eb.Disable then eb:Disable()
    elseif eb.EnableMouse then eb:EnableMouse(false) end
    if eb.SetAlpha then eb:SetAlpha(0.55) end
    if wrap and wrap.SetAlpha then wrap:SetAlpha(0.55) end
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
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)
  fs:SetText(text)
  return fs
end

local function mkLabelCenter(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOP", x, y)
  fs:SetJustifyH("CENTER")
  fs:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)
  fs:SetText(text)
  return fs
end

-- Styled edit box with warm dark backdrop and gold focus highlight.
local function mkEdit(parent, w, h, x, y, onEnter)
  local wrap = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  wrap:SetSize(w, h)
  wrap:SetPoint("TOPLEFT", x, y)
  wrap:SetBackdrop(BACKDROP_EDITBOX)
  wrap:SetBackdropColor(C.BROWN_DEEP[1], C.BROWN_DEEP[2], C.BROWN_DEEP[3], 0.92)
  wrap:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.70)

  local eb = CreateFrame("EditBox", nil, wrap)
  eb:SetPoint("TOPLEFT", 5, -2)
  eb:SetPoint("BOTTOMRIGHT", -4, 2)
  eb:SetFontObject("GameFontHighlight")
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetTextColor(C.TEXT_BRIGHT[1], C.TEXT_BRIGHT[2], C.TEXT_BRIGHT[3], 1)

  -- Gold border glow on focus.
  eb:SetScript("OnEditFocusGained", function()
    wrap:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 0.90)
    wrap:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.95)
  end)
  eb:SetScript("OnEditFocusLost", function()
    wrap:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.70)
    wrap:SetBackdropColor(C.BROWN_DEEP[1], C.BROWN_DEEP[2], C.BROWN_DEEP[3], 0.92)
    if onEnter then onEnter() end
  end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onEnter then onEnter() end
  end)

  -- Proxy size/position APIs so callers that adjust the edit box get the wrapper.
  eb._wrap = wrap
  eb.SetSize_orig = eb.SetSize
  return eb
end

-- Custom styled button with dark backdrop, gold border, warm hover.
local function mkButton(parent, text, w, h, x, y, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  b:SetPoint("TOPLEFT", x, y)
  b:SetBackdrop(BACKDROP_BUTTON)
  b:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.90)
  b:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.80)

  -- Highlight overlay (warm glow on hover).
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture(TEX.FLAT)
  hl:SetColorTexture(1.0, 0.80, 0.30, 0.10)

  -- Text label.
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER", 0, 0)
  fs:SetTextColor(C.GOLD_LIGHT[1], C.GOLD_LIGHT[2], C.GOLD_LIGHT[3], 1)
  fs:SetText(text)
  b._fs = fs

  -- Override SetText/GetText to use our custom FontString.
  function b:SetText(t) fs:SetText(t) end
  function b:GetText() return fs:GetText() end

  -- Visual pressed state.
  b:SetScript("OnMouseDown", function()
    if b:IsEnabled() then fs:SetPoint("CENTER", 1, -1) end
  end)
  b:SetScript("OnMouseUp", function()
    fs:SetPoint("CENTER", 0, 0)
  end)

  -- Disabled/enabled state visual overrides.
  local origDisable = b.Disable
  function b:Disable()
    origDisable(self)
    fs:SetTextColor(C.TEXT_DISABLED[1], C.TEXT_DISABLED[2], C.TEXT_DISABLED[3], 1)
    self:SetBackdropColor(C.BROWN_DEEP[1], C.BROWN_DEEP[2], C.BROWN_DEEP[3], 0.65)
    self:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.35)
  end
  local origEnable = b.Enable
  function b:Enable()
    origEnable(self)
    fs:SetTextColor(C.GOLD_LIGHT[1], C.GOLD_LIGHT[2], C.GOLD_LIGHT[3], 1)
    self:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.90)
    self:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.80)
  end

  if onClick then b:SetScript("OnClick", function() onClick() end) end
  return b
end

local function formatHistoryText(history, subjectFilter)
  if History and History.FormatHistoryText then
    local depth = (Core and Core.GetUndoDepth and Core.GetUndoDepth()) or 0
    return History.FormatHistoryText(history, depth, subjectFilter)
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
  bar:SetStatusBarTexture(TEX.STATUSBAR)
  bar:SetStatusBarColor(r, g, b, 1)

  -- Dark background with subtle warm tint.
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints(bar)
  barBg:SetTexture(TEX.FLAT)
  barBg:SetColorTexture(0.04, 0.03, 0.01, 0.92)
  bar._bg = barBg

  -- Top-half sheen for depth / glass effect.
  local sheen = bar:CreateTexture(nil, "OVERLAY")
  sheen:SetTexture(TEX.FLAT)
  sheen:SetVertexColor(1, 1, 1, 0.07)
  sheen:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
  sheen:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, -1)
  sheen:SetHeight(math.max(1, math.floor((bar:GetHeight() or 20) / 2)))

  -- Bottom shadow line for inset effect.
  local shadow = bar:CreateTexture(nil, "OVERLAY")
  shadow:SetTexture(TEX.FLAT)
  shadow:SetColorTexture(0, 0, 0, 0.25)
  shadow:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
  shadow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
  shadow:SetHeight(1)

  -- Spark texture at the fill edge.
  local spark = bar:CreateTexture(nil, "OVERLAY")
  spark:SetTexture("Interface/CastingBar/UI-CastingBar-Spark")
  spark:SetBlendMode("ADD")
  spark:SetSize(12, bar:GetHeight() + 6)
  spark:SetAlpha(0.55)
  spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
  bar._spark = spark

  -- Gold-trimmed border frame.
  local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetBackdrop({ edgeFile = TEX.FLAT, edgeSize = 1 })
  border:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.75)
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

  -- Migration: Paramètres tab merge requires a wider default window.
  if not db.ui._migrated_20260401_paramtab then
    db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0
    db.ui.w, db.ui.h = nil, nil
    db.ui._migrated_20260401_paramtab = true
  end

  local FRAME_W, FRAME_H = 880, 460
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

  frame:SetBackdrop(BACKDROP_FRAME)
  frame:SetBackdropColor(0.95, 0.90, 0.80, 0.98)

  -- Inner shadow frame for depth (inset below the gold border).
  local innerShadow = CreateFrame("Frame", nil, frame)
  innerShadow:SetPoint("TOPLEFT", 8, -8)
  innerShadow:SetPoint("BOTTOMRIGHT", -8, 8)
  innerShadow:SetFrameLevel(frame:GetFrameLevel() + 1)
  local shadowTop = innerShadow:CreateTexture(nil, "OVERLAY")
  shadowTop:SetTexture(TEX.FLAT)
  shadowTop:SetColorTexture(0, 0, 0, 0.18)
  shadowTop:SetPoint("TOPLEFT")
  shadowTop:SetPoint("TOPRIGHT")
  shadowTop:SetHeight(3)
  local shadowLeft = innerShadow:CreateTexture(nil, "OVERLAY")
  shadowLeft:SetTexture(TEX.FLAT)
  shadowLeft:SetColorTexture(0, 0, 0, 0.12)
  shadowLeft:SetPoint("TOPLEFT", 0, -3)
  shadowLeft:SetPoint("BOTTOMLEFT")
  shadowLeft:SetWidth(2)

  -- Header band: warm dark gradient behind the title area.
  local headerBand = frame:CreateTexture(nil, "ARTWORK")
  headerBand:SetPoint("TOPLEFT",  frame, "TOPLEFT",  10, -10)
  headerBand:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
  headerBand:SetHeight(28)
  headerBand:SetTexture(TEX.FLAT)
  headerBand:SetColorTexture(C.BROWN_DEEP[1], C.BROWN_DEEP[2], C.BROWN_DEEP[3], 0.50)

  -- Gold separator below header band.
  local headerLine = frame:CreateTexture(nil, "ARTWORK")
  headerLine:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD_X, -38)
  headerLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD_X, -38)
  headerLine:SetHeight(2)
  headerLine:SetTexture(TEX.FLAT)
  headerLine:SetColorTexture(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.45)
  frame._headerLine = headerLine

  -- Subtle second line for depth effect.
  local headerLine2 = frame:CreateTexture(nil, "ARTWORK")
  headerLine2:SetPoint("TOPLEFT",  headerLine, "BOTTOMLEFT",  0, 0)
  headerLine2:SetPoint("TOPRIGHT", headerLine, "BOTTOMRIGHT", 0, 0)
  headerLine2:SetHeight(1)
  headerLine2:SetTexture(TEX.FLAT)
  headerLine2:SetColorTexture(0, 0, 0, 0.20)

  frame:SetPoint(db.ui.point, UIParent, db.ui.point, db.ui.x, db.ui.y)
  if db.ui.shown then frame:Show() else frame:Hide() end

  -- Title: large gold text with shadow.
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  UI.title = title
  title:SetPoint("TOP", 0, -15)
  title:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
  title:SetShadowOffset(1, -1)
  title:SetShadowColor(0, 0, 0, 0.65)
  updateWindowTitle()

  -- Retry TRP3 hook once after a delay in case TRP3 initializes after us.
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(1.0, function()
      hookTRP3Callbacks()
      updateWindowTitle()
    end)
  end

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetSize(22, 22)

  -- popupToggleBtn is defined after the sidebar sect buttons (needs sidebar reference).

  -- Size label shown in the centre during resize.
  local sizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  sizeLabel:SetPoint("CENTER", frame, "CENTER")
  sizeLabel:SetTextColor(C.GOLD_LIGHT[1], C.GOLD_LIGHT[2], C.GOLD_LIGHT[3], 1)
  sizeLabel:SetShadowOffset(1, -1)
  sizeLabel:SetShadowColor(0, 0, 0, 0.80)
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

  -- ── Keyboard shortcuts ────────────────────────────────────────────
  frame:EnableKeyboard(true)
  frame:SetScript("OnKeyDown", function(self, key)
    if IsControlKeyDown() and (key == "z" or key == "Z") then
      self:SetPropagateKeyboardInput(false)
      if Core and Core.Undo then
        Core.Undo()
        if UI.refreshUndoRedo then UI.refreshUndoRedo() end
      end
    elseif IsControlKeyDown() and (key == "y" or key == "Y") then
      self:SetPropagateKeyboardInput(false)
      if Core and Core.Redo then
        Core.Redo()
        if UI.refreshUndoRedo then UI.refreshUndoRedo() end
      end
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

  -- ── Action icons (bottom-right, all tabs) ───────────────────────
  do
    local ICON_SIZE = 18
    local ICON_GAP  = 3

    local function mkActionIcon(parent, icon, tipTitle, desc, onClick)
      local btn = CreateFrame("Button", nil, parent)
      btn:SetSize(ICON_SIZE, ICON_SIZE)
      btn:SetFrameLevel(parent:GetFrameLevel() + 10)

      -- Background tint
      local bg = btn:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(0, 0, 0, 0.55)

      -- Icon texture
      local tex = btn:CreateTexture(nil, "ARTWORK")
      tex:SetAllPoints()
      tex:SetTexture(icon)
      tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

      -- Thin gold border
      local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
      border:SetAllPoints()
      border:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
      border:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.70)
      border:SetFrameLevel(btn:GetFrameLevel() + 1)

      -- Hover highlight
      local hl = btn:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.20)

      btn:SetScript("OnEnter", function(self)
        border:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(tipTitle, C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
        GameTooltip:AddLine(desc, 1, 1, 1, true)
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function()
        border:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.70)
        GameTooltip:Hide()
      end)
      btn:SetScript("OnClick", function()
        if Core then onClick() end
      end)

      return btn
    end

    local iconRestore = mkActionIcon(frame,
      "Interface/Icons/Spell_Holy_HealingAura",
      "Restaurer PV",
      "Remet tous les PV au maximum (bonus inclus).",
      function() Core.RestoreHP() end)
    iconRestore:SetPoint("BOTTOMRIGHT", grip, "BOTTOMLEFT", -50, 20)

    local iconRegenHP = mkActionIcon(frame,
      "Interface/Icons/Spell_Nature_Rejuvenation",
      "Régénération quotidienne PV",
      "Restaure 10 % du max de PV, ignorant les seuils de blessure.",
      function() Core.DailyRegenHP() end)
    iconRegenHP:SetPoint("RIGHT", iconRestore, "LEFT", -ICON_GAP, 0)

    local iconRegenRes = mkActionIcon(frame,
      "Interface/Icons/spell_arcane_manatap",
      "Régénération quotidienne mystique",
      "Restaure 20 % de la ressource principale (mana, énergie, etc.).",
      function() Core.DailyRegenRes() end)
    iconRegenRes:SetPoint("RIGHT", iconRegenHP, "LEFT", -ICON_GAP, 0)
  end

  -- Main body: sidebar (left) + content (right)
  local body = CreateFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD_X, -40)
  body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD_X, PAD_X)
  UI.body = body

  -- ── Sidebar ───────────────────────────────────────────────────────────
  local sidebar = CreateFrame("Frame", nil, body, "BackdropTemplate")
  sidebar:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  sidebar:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
  sidebar:SetWidth(SIDEBAR_W)
  sidebar:SetBackdrop(BACKDROP_SIDEBAR)
  sidebar:SetBackdropColor(0.12, 0.08, 0.04, 0.98)
  sidebar:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.50)
  UI.sidebar = sidebar

  -- Top gradient overlay on sidebar for depth.
  local sidebarTopGrad = sidebar:CreateTexture(nil, "ARTWORK")
  sidebarTopGrad:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 1, -1)
  sidebarTopGrad:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -1, -1)
  sidebarTopGrad:SetHeight(40)
  sidebarTopGrad:SetTexture(TEX.FLAT)
  sidebarTopGrad:SetColorTexture(0, 0, 0, 0.18)
  sidebarTopGrad:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 1))

  -- Bottom gradient overlay on sidebar.
  local sidebarBotGrad = sidebar:CreateTexture(nil, "ARTWORK")
  sidebarBotGrad:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 1, 1)
  sidebarBotGrad:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, 1)
  sidebarBotGrad:SetHeight(30)
  sidebarBotGrad:SetTexture(TEX.FLAT)
  sidebarBotGrad:SetColorTexture(0, 0, 0, 0.15)
  sidebarBotGrad:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))

  -- Gold vertical divider (double line for depth).
  local sidebarDiv = body:CreateTexture(nil, "ARTWORK")
  sidebarDiv:SetWidth(2)
  sidebarDiv:SetPoint("TOPLEFT",    sidebar, "TOPRIGHT",    0, 0)
  sidebarDiv:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
  sidebarDiv:SetTexture(TEX.FLAT)
  sidebarDiv:SetColorTexture(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.35)

  local sidebarShadow = body:CreateTexture(nil, "ARTWORK")
  sidebarShadow:SetWidth(4)
  sidebarShadow:SetPoint("TOPLEFT",    sidebarDiv, "TOPRIGHT",    0, 0)
  sidebarShadow:SetPoint("BOTTOMLEFT", sidebarDiv, "BOTTOMRIGHT", 0, 0)
  sidebarShadow:SetTexture(TEX.FLAT)
  sidebarShadow:SetColorTexture(0, 0, 0, 0.12)

  -- ── Content area ──────────────────────────────────────────────────────
  local content = CreateFrame("Frame", nil, body, "BackdropTemplate")
  content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", GUTTER, 0)
  content:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  content:SetBackdrop(BACKDROP_CONTENT)
  content:SetBackdropColor(C.CREAM[1], C.CREAM[2], C.CREAM[3], 0.25)
  content:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.30)
  UI.content = content

  -- Inner top shadow for inset depth on content.
  local contentTopShadow = content:CreateTexture(nil, "BORDER")
  contentTopShadow:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -2)
  contentTopShadow:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -2)
  contentTopShadow:SetHeight(3)
  contentTopShadow:SetTexture(TEX.FLAT)
  contentTopShadow:SetColorTexture(0, 0, 0, 0.10)

  -- ── Undo / Redo buttons (bottom-left of content, all tabs) ────────────
  do
    local UBTN_W, UBTN_H = 22, 18
    local UBTN_PAD = 6

    local function mkUndoBtn(parent, label, tipTitle, tipDesc, onClick)
      local btn = CreateFrame("Button", nil, parent)
      btn:SetSize(UBTN_W, UBTN_H)
      btn:SetFrameLevel(parent:GetFrameLevel() + 10)

      local bg = btn:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(0.10, 0.07, 0.03, 0.70)

      local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
      border:SetAllPoints()
      border:SetBackdrop({
        edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1,
      })
      border:SetFrameLevel(btn:GetFrameLevel() + 1)

      local text = btn:CreateFontString(nil, "OVERLAY")
      text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
      text:SetPoint("CENTER", 0, 1)
      text:SetText(label)

      btn.border = border
      btn.text = text
      btn.bg = bg

      local function refreshVisual(enabled)
        if enabled then
          text:SetTextColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 1.0)
          border:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.70)
          bg:SetColorTexture(0.10, 0.07, 0.03, 0.70)
          btn:Enable()
        else
          text:SetTextColor(0.40, 0.35, 0.28, 0.40)
          border:SetBackdropBorderColor(0.30, 0.25, 0.18, 0.30)
          bg:SetColorTexture(0.06, 0.04, 0.02, 0.40)
          btn:Disable()
        end
      end
      btn.refreshVisual = refreshVisual
      refreshVisual(false)

      btn:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        border:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(tipTitle, C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
        GameTooltip:AddLine(tipDesc, 1, 1, 1, true)
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function(self)
        if self:IsEnabled() then
          border:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.70)
        end
        GameTooltip:Hide()
      end)
      btn:SetScript("OnClick", function()
        if Core then
          onClick()
          UI.refreshUndoRedo()
        end
      end)

      return btn
    end

    local undoBtn = mkUndoBtn(content, "<", "Annuler",
      "Annule la dernière action.",
      function() Core.Undo() end)
    undoBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", UBTN_PAD, UBTN_PAD)
    UI.undoBtn = undoBtn

    local redoBtn = mkUndoBtn(content, ">", "Rétablir",
      "Rétablit la dernière action annulée.",
      function() Core.Redo() end)
    redoBtn:SetPoint("LEFT", undoBtn, "RIGHT", 3, 0)
    UI.redoBtn = redoBtn

    function UI.refreshUndoRedo()
      if UI.undoBtn then
        UI.undoBtn.refreshVisual(Core and Core.CanUndo())
      end
      if UI.redoBtn then
        UI.redoBtn.refreshVisual(Core and Core.CanRedo())
      end
    end
  end

  -- ── HP Bar ─────────────────────────────────────────────────────────────
  local hpBar = CreateFrame("StatusBar", nil, content)
  UI.hpBar = hpBar
  hpBar:SetHeight(24)
  hpBar:SetPoint("TOPLEFT", content, "TOPLEFT", 3, -3)
  hpBar:SetPoint("RIGHT", content, "RIGHT", -3, 0)
  hpBar:SetMinMaxValues(0, 1)
  hpBar:SetValue(1)
  skinBar(hpBar, C.RED_HP[1], C.RED_HP[2], C.RED_HP[3])

  local hpText = hpBar:CreateFontString(nil, "OVERLAY")
  hpText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
  UI.hpText = hpText
  hpText:SetPoint("CENTER")
  hpText:SetTextColor(C.TEXT_BRIGHT[1], C.TEXT_BRIGHT[2], C.TEXT_BRIGHT[3], 1)
  hpText:SetShadowOffset(1, -1)
  hpText:SetShadowColor(0, 0, 0, 0.92)

  local blockOverlay = hpBar:CreateTexture(nil, "OVERLAY")
  UI.hpBlockOverlay = blockOverlay
  blockOverlay:SetTexture(TEX.FLAT)
  blockOverlay:SetColorTexture(0.60, 0.60, 0.60, 0.50)
  blockOverlay:SetPoint("TOP", hpBar, "TOP", 0, 0)
  blockOverlay:SetPoint("BOTTOM", hpBar, "BOTTOM", 0, 0)
  blockOverlay:Hide()

  local magicOverlay = hpBar:CreateTexture(nil, "OVERLAY")
  UI.hpMagicBlockOverlay = magicOverlay
  magicOverlay:SetTexture(TEX.FLAT)
  magicOverlay:SetColorTexture(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 0.55)
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
  capText:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 3, -4)
  capText:SetTextColor(C.GOLD_DIM[1], C.GOLD_DIM[2], C.GOLD_DIM[3], 1)
  capText:SetShadowOffset(1, -1)
  capText:SetShadowColor(0, 0, 0, 0.60)
  capText:SetText("")

  -- Ressource bars (up to 4, depending on selected class)
  UI.resBars = {}
  UI.resTexts = {}
  local RES_BAR_H = 17
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
    bar:SetPoint("RIGHT", content, "RIGHT", -3, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    skinBar(bar, 0.2, 0.55, 1.0)
    bar:Hide()

    -- Optional stacked segments (used for Shaman: 4 elements in 1 bar)
    if idx == 1 then
      bar._stackSegs = {}
      for j = 1, 4 do
        local seg = bar:CreateTexture(nil, "OVERLAY")
        seg:SetTexture(TEX.FLAT)
        seg:SetVertexColor(1, 1, 1, 1)
        seg:Hide()
        bar._stackSegs[j] = seg
      end
    end

    local txt = bar:CreateFontString(nil, "OVERLAY")
    txt:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    UI.resTexts[idx] = txt
    txt:SetPoint("CENTER")
    txt:SetTextColor(C.TEXT_BRIGHT[1], C.TEXT_BRIGHT[2], C.TEXT_BRIGHT[3], 1)
    txt:SetShadowOffset(1, -1)
    txt:SetShadowColor(0, 0, 0, 0.92)
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

  -- Mage Arcane Charge thresholds (max always 8): T4 at 4, T5 at 8
  UI.arcaneChargeMarkers = {}
  do
    local bar = UI.resBars[2]
    if bar then
      UI.arcaneChargeMarkers[1] = makeMarker(bar, 4/8, 1.00, 0.82, 0.22, 0.65, 2)
      UI.arcaneChargeMarkers[2] = makeMarker(bar, 8/8, 0.75, 0.30, 1.00, 0.80, 3)
    end
  end

  do
    local bar = UI.resBars[2]
    if bar then
      bar:SetScript("OnSizeChanged", function()
        if UI.corruptionMarkers[1] and UI.corruptionMarkers[1]:IsShown() then
          positionMarkers(UI.corruptionMarkers, bar)
        end
        if UI.insanityMarkers[1] and UI.insanityMarkers[1]:IsShown() then
          positionMarkers(UI.insanityMarkers, bar)
        end
        if UI.arcaneChargeMarkers[1] and UI.arcaneChargeMarkers[1]:IsShown() then
          positionMarkers(UI.arcaneChargeMarkers, bar)
        end
      end)
    end
  end

  do
    local bar = UI.resBars[1]
    if bar then
      bar:SetScript("OnSizeChanged", function()
        if UI.refreshShamanBar then UI.refreshShamanBar() end
      end)
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

  -- 1 = character section, 2 = familiar section.
  local activeSection    = 1
  local lastState        = nil
  local refreshHpDisplay   -- forward declaration; assigned after hpBar is created
  local onChangeCallback   -- forward declaration; allows setSidebarSection to trigger a full re-render

  -- Redraws the shaman stacked-element bar segments from lastState.
  -- Called from onChangeCallback and from bar #1's OnSizeChanged.
  UI.refreshShamanBar = function()
    local s = lastState
    if not s or s.classKey ~= "SHAMAN" then return end
    local bar = UI.resBars and UI.resBars[1]
    local txt = UI.resTexts and UI.resTexts[1]
    if not bar or not bar._stackSegs or not bar:IsShown() then return end

    local profile = getResProfile(s)
    local totalMax, totalCur = 0, 0
    for j = 1, 4 do
      local pj = profile[j]
      if pj then
        local rk, mk = getKeysForIdx(pj.idx)
        local curJ = math.max(0, s[rk] or 0)
        local maxJ = s[mk] or 0
        if maxJ > 0 and curJ > maxJ then curJ = maxJ end
        totalCur = totalCur + curJ
        totalMax = totalMax + maxJ
      end
    end

    local pct = (totalMax > 0) and (totalCur / totalMax) or 0
    bar:SetValue(math.max(0, math.min(1, pct)))
    bar:SetStatusBarColor(0, 0, 0, 0)

    local wBar = bar:GetWidth() or 0
    local x = 0
    for j = 1, 4 do
      local seg = bar._stackSegs[j]
      local pj = profile[j]
      if seg and pj and totalMax > 0 and wBar > 0 then
        local rk, mk = getKeysForIdx(pj.idx)
        local curJ = math.max(0, s[rk] or 0)
        local maxJ = s[mk] or 0
        if maxJ > 0 and curJ > maxJ then curJ = maxJ end
        local segW = wBar * (curJ / totalMax)
        if segW > 0.5 then
          seg:Show()
          seg:SetVertexColor(pj.r, pj.g, pj.b, 0.95)
          seg:ClearAllPoints()
          seg:SetPoint("TOPLEFT",    bar, "TOPLEFT",    x, 0)
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
        totalCur, totalMax, roundPct(pct)
      ))
    end
  end

  local function setTab(active)
    if UI.tabDisabled and UI.tabDisabled[active] then
      return
    end
    -- Don't activate a tab that belongs to the inactive section.
    if active <= 7 and activeSection ~= 1 then return end
    if active >= 8 and activeSection ~= 2 then return end
    if UI.tabHidden and UI.tabHidden[active] then
      setTab(activeSection == 1 and 1 or 8)
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
          -- Active: warm lit background, bright gold text, accent visible.
          b:Disable()
          if b._bg then
            b._bg:SetColorTexture(C.BROWN_MED[1], C.BROWN_MED[2], C.BROWN_MED[3], 0.92)
          end
          if b._accent then b._accent:Show() end
          if b._accentGlow then b._accentGlow:Show() end
          if b._text then
            b._text:SetTextColor(C.GOLD_LIGHT[1], C.GOLD_LIGHT[2], C.GOLD_LIGHT[3], 1)
          end
          if b.SetBackdropBorderColor then
            b:SetBackdropBorderColor(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.50)
          end
        elseif disabled then
          -- Disabled: dim and muted.
          b:Disable()
          if b._bg then
            b._bg:SetColorTexture(C.BROWN_DEEP[1], C.BROWN_DEEP[2], C.BROWN_DEEP[3], 0.40)
          end
          if b._accent then b._accent:Hide() end
          if b._accentGlow then b._accentGlow:Hide() end
          if b._text then
            b._text:SetTextColor(C.TEXT_DISABLED[1], C.TEXT_DISABLED[2], C.TEXT_DISABLED[3], 1)
          end
          if b.SetBackdropBorderColor then
            b:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.15)
          end
        else
          -- Normal: subtle warm background, readable text.
          b:Enable()
          if b._bg then
            b._bg:SetColorTexture(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.55)
          end
          if b._accent then b._accent:Hide() end
          if b._accentGlow then b._accentGlow:Hide() end
          if b._text then
            b._text:SetTextColor(C.TEXT_NORMAL[1], C.TEXT_NORMAL[2], C.TEXT_NORMAL[3], 1)
          end
          if b.SetBackdropBorderColor then
            b:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.25)
          end
        end
      end
    end

    if active == 7 and UI.syncHistoryWidth then
      UI.syncHistoryWidth()
    end
    if active == 9 and UI.syncPetHistoryWidth then
      UI.syncPetHistoryWidth()
    end
  end

  -- Sidebar navigation (vertical tabs)
  local TAB_TEXTS = {
    "Fiche",             -- 1  character section
    "Ressources",       -- 2
    "Armure & blocage", -- 3 (was 4)
    "Actions",          -- 4 (was 5)
    "",                 -- 5  reserved slot (always hidden)
    "Classes",          -- 6 (was 3)
    "Historique",       -- 7
    "Familier",         -- 8  familiar section (merged)
    "Historique",       -- 9  familiar history
    "",                 -- 10 hidden slot
  }

  local NAV_PAD = 5
  local NAV_GAP = 1
  local NAV_BTN_H = 30

  local function mkTab(text, idx)
    local tab = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
    tab:SetSize(SIDEBAR_W - (NAV_PAD * 2), NAV_BTN_H)
    tab:SetBackdrop(BACKDROP_TAB)
    tab:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.25)

    -- Background fill.
    local tabBg = tab:CreateTexture(nil, "BACKGROUND")
    tabBg:SetAllPoints(tab)
    tabBg:SetTexture(TEX.FLAT)
    tabBg:SetColorTexture(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.55)
    tab._bg = tabBg

    -- Hover highlight: warm gold tint.
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetTexture(TEX.FLAT)
    hl:SetColorTexture(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.08)

    -- Left gold accent stripe (shown when active).
    local accent = tab:CreateTexture(nil, "ARTWORK")
    accent:SetTexture(TEX.FLAT)
    accent:SetPoint("TOPLEFT",    tab, "TOPLEFT",    0, 0)
    accent:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    accent:SetColorTexture(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 1.0)
    accent:Hide()
    tab._accent = accent

    -- Accent glow: soft additive glow beside the accent bar.
    local accentGlow = tab:CreateTexture(nil, "ARTWORK")
    accentGlow:SetTexture(TEX.FLAT)
    accentGlow:SetPoint("TOPLEFT",    accent, "TOPRIGHT",    0, 0)
    accentGlow:SetPoint("BOTTOMLEFT", accent, "BOTTOMRIGHT", 0, 0)
    accentGlow:SetWidth(8)
    accentGlow:SetColorTexture(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.08)
    accentGlow:SetBlendMode("ADD")
    accentGlow:Hide()
    tab._accentGlow = accentGlow

    -- Bottom separator line between tabs.
    local sep = tab:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(TEX.FLAT)
    sep:SetPoint("BOTTOMLEFT",  tab, "BOTTOMLEFT",  4, 0)
    sep:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -4, 0)
    sep:SetHeight(1)
    sep:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.12)

    local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT",  tab, "LEFT",  14, 0)
    fs:SetPoint("RIGHT", tab, "RIGHT", -8, 0)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(C.TEXT_NORMAL[1], C.TEXT_NORMAL[2], C.TEXT_NORMAL[3], 1)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.50)
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
      -- Hide tabs that belong to the inactive section or are explicitly hidden.
      local sectionHide = (activeSection == 1 and i >= 8) or (activeSection == 2 and i <= 7)
      if (UI.tabHidden and UI.tabHidden[i]) or sectionHide then
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

  local pageHP      = mkPage()   -- 1  (Paramètres)
  local pageRes     = mkPage()   -- 2
  mkPage()                       -- 3  (hidden — merged into Paramètres)
  mkPage()                       -- 4  (hidden — merged into Paramètres)
  mkPage()                       -- 5 (reserved slot, always hidden)
  local pageClasses = mkPage()   -- 6 (was 3)
  local pageHistory = mkPage()   -- 7
  local pagePetHP     = mkPage() -- 8: familiar – Fiche (merged)
  local pagePetArmor  = mkPage() -- 9: familiar – Historique
  local pagePetCombat = mkPage() -- 10: hidden slot
  UI.pageHistory = pageHistory

  -- Tabs 2-5 are merged into tab 1 (Fiche). Tab 5 is a reserved slot.
  -- Tab 10 is a hidden slot (familiar has only Fiche + Historique).
  UI.tabHidden[2] = true
  UI.tabHidden[3] = true
  UI.tabHidden[4] = true
  UI.tabHidden[5] = true
  UI.tabHidden[10] = true

  -- ── Section switcher buttons (bottom of sidebar) ────────────────────
  local SECT_BTN_H = 24
  local SECT_BTN_W = math.floor((SIDEBAR_W - NAV_PAD * 2 - 4) / 2)

  local sectChar = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
  local sectPet  = CreateFrame("Button", nil, sidebar, "BackdropTemplate")

  local function styleSectBtn(btn, active)
    if active then
      btn:SetBackdropColor(C.BROWN_MED[1], C.BROWN_MED[2], C.BROWN_MED[3], 0.95)
      btn:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 0.85)
      if btn._text then
        btn._text:SetTextColor(C.GOLD_LIGHT[1], C.GOLD_LIGHT[2], C.GOLD_LIGHT[3], 1)
      end
      if btn._topAccent then btn._topAccent:Show() end
    else
      btn:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.60)
      btn:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.40)
      if btn._text then
        btn._text:SetTextColor(C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3], 1)
      end
      if btn._topAccent then btn._topAccent:Hide() end
    end
  end

  local function setSidebarSection(sect)
    activeSection = sect
    repositionSidebarTabs()
    styleSectBtn(sectChar, sect == 1)
    styleSectBtn(sectPet,  sect == 2)
    if sect == 1 then
      if UI.activeTab and UI.activeTab >= 8 then setTab(1) end
    else
      if not UI.activeTab or UI.activeTab < 8 then setTab(8) end
    end
    -- Full re-render for the newly active section.
    if lastState and onChangeCallback then onChangeCallback(lastState) end
  end

  local function makeSectBtn(btn, label, x, onClick)
    btn:SetSize(SECT_BTN_W, SECT_BTN_H)
    btn:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", x, NAV_PAD)
    btn:SetBackdrop(BACKDROP_SIDEBAR)
    -- Warm hover glow.
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetTexture(TEX.FLAT)
    hl:SetColorTexture(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.08)
    -- Top gold accent line (shown when active).
    local topAccent = btn:CreateTexture(nil, "ARTWORK")
    topAccent:SetTexture(TEX.FLAT)
    topAccent:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, 0)
    topAccent:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, 0)
    topAccent:SetHeight(2)
    topAccent:SetColorTexture(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 0.80)
    topAccent:Hide()
    btn._topAccent = topAccent
    -- Label.
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("CENTER", 0, 0)
    lbl:SetShadowOffset(1, -1)
    lbl:SetShadowColor(0, 0, 0, 0.50)
    lbl:SetText(label)
    btn._text = lbl
    btn:SetScript("OnClick", onClick)
  end

  makeSectBtn(sectChar, "Personnage", NAV_PAD,                    function() setSidebarSection(1) end)
  makeSectBtn(sectPet,  "Familier",   NAV_PAD + SECT_BTN_W + 4,  function() setSidebarSection(2) end)

  -- Popup-on-target toggle icon button, centered above the two sect buttons.
  local popupToggleBtn = CreateFrame("Button", nil, sidebar)
  popupToggleBtn:SetSize(26, 26)
  popupToggleBtn:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, SECT_BTN_H + NAV_PAD + 10)
  popupToggleBtn:SetFrameLevel(sidebar:GetFrameLevel() + 5)
  popupToggleBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_Eye_01")
  popupToggleBtn:SetHighlightTexture("Interface\\Icons\\INV_Misc_Eye_01")

  local function refreshPopupToggleBtn()
    local sdb = ns.GetDB and ns.GetDB() or {}
    sdb.settings = sdb.settings or {}
    local enabled = sdb.settings.popupOnTarget ~= false
    local tex = popupToggleBtn:GetNormalTexture()
    if tex then
      if enabled then
        tex:SetVertexColor(1.00, 0.82, 0.22, 1)
        tex:SetDesaturated(false)
      else
        tex:SetVertexColor(0.45, 0.40, 0.35, 1)
        tex:SetDesaturated(true)
      end
    end
  end
  UI.refreshPopupToggleBtn = refreshPopupToggleBtn

  popupToggleBtn:SetScript("OnClick", function()
    local sdb = ns.GetDB and ns.GetDB() or {}
    sdb.settings = sdb.settings or {}
    sdb.settings.popupOnTarget = not (sdb.settings.popupOnTarget ~= false)
    refreshPopupToggleBtn()
  end)

  popupToggleBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    local sdb = ns.GetDB and ns.GetDB() or {}
    sdb.settings = sdb.settings or {}
    local enabled = sdb.settings.popupOnTarget ~= false
    GameTooltip:SetText("Popup au ciblage", 1, 0.82, 0.22, 1, true)
    if enabled then
      GameTooltip:AddLine("Activé — clic pour désactiver", 0.90, 0.84, 0.68)
    else
      GameTooltip:AddLine("Désactivé — clic pour activer", 0.60, 0.52, 0.36)
    end
    GameTooltip:Show()
  end)
  popupToggleBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  refreshPopupToggleBtn()

  -- Decorative separator above section switcher.
  local sectSep = sidebar:CreateTexture(nil, "ARTWORK")
  sectSep:SetTexture(TEX.FLAT)
  sectSep:SetPoint("BOTTOMLEFT",  sidebar, "BOTTOMLEFT",  NAV_PAD + 6, SECT_BTN_H + NAV_PAD + 6)
  sectSep:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -NAV_PAD - 6, SECT_BTN_H + NAV_PAD + 6)
  sectSep:SetHeight(1)
  sectSep:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.25)

  -- Decorative diamond in the center of the separator.
  local sectDiamond = sidebar:CreateTexture(nil, "ARTWORK")
  sectDiamond:SetTexture(TEX.FLAT)
  sectDiamond:SetSize(5, 5)
  sectDiamond:SetPoint("CENTER", sectSep, "CENTER", 0, 0)
  sectDiamond:SetColorTexture(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.35)
  sectDiamond:SetRotation(math.rad(45))

  -- Onglet 1 : Fiche (PV + Armure & Esquive + Actions + Blocage + Ressources)
  -- Déclarations anticipées ; l'UI est construite après les ressources.
  local hpCur, hpMax, bonusHpValEB
  local armorEB, trueArmorEB, tempArmorEB, dodgeEB, blockEB
  local msHpEB, msMaxHpEB, msArmorEB
  local mnsArmorEB, mnsToggleBtn, mnsLabel, mnsArmorLabel
  local actValEB

  local function applyAllHP()
    Core.SetHP(getNumber(hpCur), getNumber(hpMax))
  end

  local function applyAllArmor()
    local armorVal     = getNumber(armorEB)
    local trueArmorVal = getNumber(trueArmorEB)
    local tempArmorVal = getNumber(tempArmorEB)
    local dodgeVal     = getNumber(dodgeEB)
    local blockVal     = getNumber(blockEB)
    Core.SetArmor(armorVal, trueArmorVal)
    Core.SetTempArmor(tempArmorVal)
    Core.SetDodge(dodgeVal)
    Core.SetTempBlock(blockVal)
  end

  local function applyAllMagicShield()
    local hpVal    = getNumber(msHpEB)
    local maxVal   = getNumber(msMaxHpEB)
    local armorVal = getNumber(msArmorEB)
    Core.SetMagicShield(hpVal, maxVal, armorVal)
  end

  local function applyAllManaShield()
    local armorVal = getNumber(mnsArmorEB)
    Core.SetManaShieldArmor(armorVal)
  end

  local function doDmgArmor() Core.DamageWithArmor(getNumber(actValEB) or 0) end
  local function doDmgTrue()  Core.DamageTrue(getNumber(actValEB) or 0) end
  local function doHeal()     Core.Heal(getNumber(actValEB) or 0) end

  -- Build scroll frame early so resource rows can be parented to cA.
  local BLOCK_W = 440
  local paramSF = CreateFrame("ScrollFrame", nil, pageHP, "UIPanelScrollFrameTemplate")
  paramSF:SetPoint("TOPLEFT",     pageHP, "TOPLEFT",     0,   0)
  paramSF:SetPoint("BOTTOMRIGHT", pageHP, "BOTTOMRIGHT", -20, 0)
  local paramChild = CreateFrame("Frame", nil, paramSF)
  paramChild:SetHeight(680)
  paramSF:SetScrollChild(paramChild)
  local cA = CreateFrame("Frame", nil, paramChild)
  cA:SetSize(BLOCK_W, 1)

  -- Onglet 2 (fusionné dans Fiche) : Ressources
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

  -- Row width 354; centered in BLOCK_W=440 → x offset = (440-354)/2 = 43.
  -- Y offsets are relative to cA top; rows start at -514 (below Ressources header).
  local function mkResRow(idx, y)
    local row = CreateFrame("Frame", nil, cA)
    row:SetSize(354, 24)
    row:SetPoint("TOPLEFT", cA, "TOPLEFT", 43, y)
    row.resIdx = idx
    UI.resRow[idx] = row
    row:Hide()

    local label = mkLabel(row, "Ressource", 0, 0)
    UI.resRowLabel[idx] = label

    local curEB, maxEB
    mkLabel(row, "/", 196, 0)

    curEB = mkEdit(row, 70, 20, 120, 2, applyAllRes)
    maxEB = mkEdit(row, 70, 20, 210, 2, applyAllRes)
    UI.resRowCur[idx] = curEB
    UI.resRowMax[idx] = maxEB

    mkButton(row, "+", 28, 20, 294, 2, function()
      if Core and Core.AddResIndex then
        Core.AddResIndex(row.resIdx or idx, 1)
      end
    end)
    mkButton(row, "-", 28, 20, 326, 2, function()
      if Core and Core.AddResIndex then
        Core.AddResIndex(row.resIdx or idx, -1)
      end
    end)

    return row
  end

  -- Rows are shown/hidden based on selected class.
  mkResRow(1, -658)
  mkResRow(2, -686)
  mkResRow(3, -714)
  mkResRow(4, -742)
  mkResRow(5, -770)

  UI.noResHint = mkLabelCenter(cA, "Aucune ressource pour cette classe.", 0, -684)
  UI.noResHint:Hide()

  -- Onglet 1 (suite) : Fiche — construction du scroll
  do
    local INPUT_H = 22
    local BTN_H   = 26
    local LBL_Y   = -2   -- décalage vertical label/input (centre optique)

    local function centerContent()
      local w = paramChild:GetWidth() or 0
      if w <= 0 then return end
      local x = math.max(8, math.floor((w - BLOCK_W) / 2))
      cA:ClearAllPoints()
      cA:SetPoint("TOPLEFT", paramChild, "TOPLEFT", x, 0)
    end
    local function syncParamWidth()
      local w = paramSF:GetWidth() or 0
      if w <= 0 then return end
      paramChild:SetWidth(math.max(200, w - 20))
    end
    paramSF:SetScript("OnSizeChanged", syncParamWidth)
    paramChild:SetScript("OnSizeChanged", centerContent)

    -- En-tête de section : titre centré 14 pt + ligne décorative.
    local function mkSectionHeader(text, y)
      local lbl = cA:CreateFontString(nil, "OVERLAY")
      lbl:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
      lbl:SetPoint("TOP", cA, "TOP", 0, y)
      lbl:SetWidth(BLOCK_W)
      lbl:SetJustifyH("CENTER")
      lbl:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
      lbl:SetShadowOffset(1, -1)
      lbl:SetShadowColor(0, 0, 0, 0.60)
      lbl:SetText(text)
      local ul = cA:CreateTexture(nil, "ARTWORK")
      ul:SetTexture(TEX.FLAT)
      ul:SetPoint("TOPLEFT",  cA, "TOPLEFT",  0, y - 18)
      ul:SetPoint("TOPRIGHT", cA, "TOPRIGHT", 0, y - 18)
      ul:SetHeight(1)
      ul:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.40)
    end

    -- Séparateur discret pleine largeur entre sections.
    local function mkSep(y)
      local sep = paramChild:CreateTexture(nil, "ARTWORK")
      sep:SetTexture(TEX.FLAT)
      sep:SetPoint("TOPLEFT",  paramChild, "TOPLEFT",  16, y)
      sep:SetPoint("TOPRIGHT", paramChild, "TOPRIGHT", -16, y)
      sep:SetHeight(1)
      sep:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.16)
    end

    -- Helpers positionnés dans le bloc centré.
    local function lbl(text, x, y)  mkLabel(cA, text, x, y + LBL_Y)  end
    local function edt(w, x, y, fn) return mkEdit(cA, w, INPUT_H, x, y, fn) end
    local function btn(text, w, x, y, fn) return mkButton(cA, text, w, BTN_H, x, y, fn) end

    -- ── Points de vie ───────────────────────────────────────────────
    mkSectionHeader("Points de vie", -10)

    lbl("PV",  0,   -38)
    lbl("/",   148, -38)
    hpCur = edt(110, 26,  -36, applyAllHP)
    hpMax = edt(110, 166, -36, applyAllHP)

    UI.bonusHpToggleBtn = btn("Activer PV bonus", 172, 0, -70, function()
      if Core and Core.ToggleBonusHP then Core.ToggleBonusHP() end
    end)
    lbl("Valeur", 186, -72)
    bonusHpValEB = edt(110, 234, -70, function()
      if Core and Core.SetBonusHP then Core.SetBonusHP(getNumber(bonusHpValEB) or 0) end
    end)

    mkSep(-106)

    -- ── Armure & Esquive ────────────────────────────────────────────
    mkSectionHeader("Armure & Esquive", -118)

    lbl("Armure",       0,   -144)
    lbl("Armure invul", 190, -144)
    armorEB     = edt(110, 66,  -142, applyAllArmor)
    trueArmorEB = edt(110, 284, -142, applyAllArmor)

    lbl("Esquive",        0,   -178)
    lbl("Armure tempo.",  190, -178)
    dodgeEB     = edt(110, 66,  -176, applyAllArmor)
    tempArmorEB = edt(110, 284, -176, applyAllArmor)

    mkSep(-212)

    -- ── Actions ─────────────────────────────────────────────────────
    mkSectionHeader("Actions", -224)

    lbl("Valeur", 0, -252)
    actValEB = edt(120, 60, -250, nil)

    btn("Dégâts (armure)", 210, 0,   -284, doDmgArmor)
    btn("Dégâts (bruts)",  210, 230, -284, doDmgTrue)

    btn("Soins",              210, 0,   -322, doHeal)
    btn("Soins divins (75%)", 210, 230, -322, function() Core.DivineHeal() end)

    btn("Chirurgie (50%)",    210, 0,   -360, function() Core.Surgery() end)

    mkSep(-402)

    -- ── Blocage ─────────────────────────────────────────────────────
    mkSectionHeader("Blocage", -414)

    lbl("Blocage", 0, -440)
    blockEB = edt(110, 162, -438, applyAllArmor)
    btn("Réinit.", 100, 284, -438, function() Core.ResetTempBlock() end)

    mkSep(-474)

    -- Boucliers magiques
    mkSectionHeader("Boucliers magiques", -486)

    lbl("PV",  0,   -512)
    lbl("/",   148, -512)
    msHpEB    = edt(110, 26,  -510, applyAllMagicShield)
    msMaxHpEB = edt(110, 166, -510, applyAllMagicShield)
    btn("Réinit.", 100, 284, -510, function()
      if Core and Core.ResetMagicShield then Core.ResetMagicShield() end
    end)

    lbl("Armure", 0, -544)
    msArmorEB = edt(110, 162, -542, applyAllMagicShield)

    -- Bouclier de mana (mage uniquement)
    mnsToggleBtn = btn("Activer bouclier de mana", 240, 0, -578, function()
      if Core and Core.ToggleManaShield then Core.ToggleManaShield() end
    end)
    UI.manaShieldToggleBtn = mnsToggleBtn
    mnsArmorLabel = mkLabel(cA, "Armure", 250, -578 + LBL_Y)
    UI.manaShieldArmorLabel = mnsArmorLabel
    mnsArmorEB = edt(80, 304, -578, applyAllManaShield)
    UI.manaShieldArmorEB = mnsArmorEB

    -- Hidden by default; shown only for mages in onChangeCallback.
    mnsToggleBtn:Hide()
    mnsArmorLabel:Hide()
    if mnsArmorEB._wrap then mnsArmorEB._wrap:Hide() else mnsArmorEB:Hide() end

    mkSep(-614)

    -- ── Ressources ──────────────────────────────────────────────────
    -- Rows (mkResRow) and noResHint are pre-built above, parented to cA.
    mkSectionHeader("Ressources", -626)

    -- ── Postures Élémentaires (Shaman uniquement) ────────────────────
    do
      local POSTURE_DEFS = {
        { key = "TERRE", label = "Terre",  r = 0.55, g = 0.35, b = 0.15,
          tip = "Posture de Terre",
          desc = "+5 armure\n+20 PV maximum\n+4 points de terre\n\nRequiert : 3 points de terre" },
        { key = "AIR",   label = "Air",    r = 0.60, g = 0.95, b = 0.95,
          tip = "Posture de l'Air",
          desc = "+15 esquive\n+4 points d'air\n\nRequiert : 3 points d'air" },
        { key = "EAU",   label = "Eau",    r = 0.20, g = 0.55, b = 1.00,
          tip = "Posture de l'Eau",
          desc = "+8 points d'eau\n\nRequiert : 3 points d'eau" },
        { key = "FEU",   label = "Feu",    r = 1.00, g = 0.35, b = 0.10,
          tip = "Posture de Feu",
          desc = "Armure réduite à 0\nDégâts reçus +10\n+4 points de feu\n\nRequiert : 3 points de feu" },
      }

      local postureSection = cA:CreateFontString(nil, "OVERLAY")
      postureSection:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
      postureSection:SetPoint("TOP", cA, "TOP", 0, -808)
      postureSection:SetWidth(BLOCK_W)
      postureSection:SetJustifyH("CENTER")
      postureSection:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
      postureSection:SetShadowOffset(1, -1)
      postureSection:SetShadowColor(0, 0, 0, 0.60)
      postureSection:SetText("Postures Élémentaires")
      UI.postureSectionLabel = postureSection

      local postureSepLine = cA:CreateTexture(nil, "ARTWORK")
      postureSepLine:SetTexture(TEX.FLAT)
      postureSepLine:SetPoint("TOPLEFT",  cA, "TOPLEFT",  0, -826)
      postureSepLine:SetPoint("TOPRIGHT", cA, "TOPRIGHT", 0, -826)
      postureSepLine:SetHeight(1)
      postureSepLine:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.40)
      UI.postureSepLine = postureSepLine

      UI.postureButtons = {}
      local BTN_W = 98
      local BTN_H2 = 26
      local GAP = 6
      local totalW = 4 * BTN_W + 3 * GAP
      local startX = math.floor((BLOCK_W - totalW) / 2)

      for i, def in ipairs(POSTURE_DEFS) do
        local bx = startX + (i - 1) * (BTN_W + GAP)
        local b = mkButton(cA, def.label, BTN_W, BTN_H2, bx, -836)
        b._postureKey = def.key
        b._postureR, b._postureG, b._postureB = def.r, def.g, def.b

        local tipTitle = def.tip
        local tipDesc  = def.desc
        b:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_TOP")
          GameTooltip:ClearLines()
          GameTooltip:AddLine(tipTitle, C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
          GameTooltip:AddLine(tipDesc, 1, 1, 1, true)
          GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function()
          if Core and Core.SetShamanPosture then
            Core.SetShamanPosture(def.key)
          end
        end)

        UI.postureButtons[i] = b
      end
    end
    paramChild:SetHeight(884)
  end

  -- Onglet 7 : Historique
  do
    -- Section header for History page.
    local histHeader = pageHistory:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    histHeader:SetPoint("TOPLEFT", pageHistory, "TOPLEFT", 4, -2)
    histHeader:SetTextColor(C.GOLD_DIM[1], C.GOLD_DIM[2], C.GOLD_DIM[3], 1)
    histHeader:SetText("Historique des évènements")
    local histHeaderLine = pageHistory:CreateTexture(nil, "ARTWORK")
    histHeaderLine:SetTexture(TEX.FLAT)
    histHeaderLine:SetPoint("TOPLEFT", histHeader, "BOTTOMLEFT", 0, -2)
    histHeaderLine:SetPoint("RIGHT", pageHistory, "RIGHT", -4, 0)
    histHeaderLine:SetHeight(1)
    histHeaderLine:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.30)

    local sf = CreateFrame("ScrollFrame", nil, pageHistory, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", histHeaderLine, "BOTTOMLEFT", 0, -4)
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
    txt:SetTextColor(C.TEXT_NORMAL[1], C.TEXT_NORMAL[2], C.TEXT_NORMAL[3], 1)
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

  -- Onglets 8-9 : Familier (section séparée — tout fusionné dans l'onglet 8)
  local petToggleBtn
  local petNameEB
  local petHpCurEB, petHpMaxEB
  local petArmorEB, petTrueArmorEB, petDodgeEB, petMagicBlockEB
  local petActionValEB
  local petDmgArmorBtn, petDmgTrueBtn, petHealBtn, petDivineBtn, petSurgeryBtn

  local function applyAllPet()
    if not Core then return end
    local petNameVal   = petNameEB and petNameEB:GetText() or nil
    local petHpCurVal  = getNumber(petHpCurEB)
    local petHpMaxVal  = getNumber(petHpMaxEB)
    local armorVal     = getNumber(petArmorEB)
    local trueArmorVal = getNumber(petTrueArmorEB)
    local dodgeVal     = getNumber(petDodgeEB)
    local magicVal     = getNumber(petMagicBlockEB)
    if Core.SetPetName and petNameVal then Core.SetPetName(petNameVal) end
    if Core.SetPetHP    then Core.SetPetHP(petHpCurVal, petHpMaxVal) end
    if Core.SetPetArmor then Core.SetPetArmor(armorVal, trueArmorVal) end
    if Core.SetPetDodge then Core.SetPetDodge(dodgeVal) end
    if Core.SetPetTempMagicBlock then Core.SetPetTempMagicBlock(magicVal) end
  end

  -- ── Tab 8 : Familier — Fiche (Identité, Armure, Actions, Blocage fusionnés) ──
  do
    local petSF = CreateFrame("ScrollFrame", nil, pagePetHP, "UIPanelScrollFrameTemplate")
    petSF:SetPoint("TOPLEFT",     pagePetHP, "TOPLEFT",     0,   0)
    petSF:SetPoint("BOTTOMRIGHT", pagePetHP, "BOTTOMRIGHT", -20, 0)
    local petPane = CreateFrame("Frame", nil, petSF)
    petPane:SetHeight(420)
    petSF:SetScrollChild(petPane)

    local function syncPetPaneWidth()
      local w = petSF:GetWidth() or 0
      if w <= 0 then return end
      petPane:SetWidth(math.max(200, w - 20))
    end
    petSF:SetScript("OnSizeChanged", syncPetPaneWidth)
    petPane:SetScript("OnSizeChanged", function()
      for i = 1, #rowAnchors do
        local f = rowAnchors[i]
        if f._reposition then f._reposition() end
      end
    end)

    local function mkPetHeader(text, y)
      local lbl = petPane:CreateFontString(nil, "OVERLAY")
      lbl:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
      lbl:SetPoint("TOPLEFT",  petPane, "TOPLEFT",  0, y)
      lbl:SetPoint("TOPRIGHT", petPane, "TOPRIGHT", 0, y)
      lbl:SetJustifyH("CENTER")
      lbl:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
      lbl:SetShadowOffset(1, -1)
      lbl:SetShadowColor(0, 0, 0, 0.60)
      lbl:SetText(text)
    end

    local function mkPetSep(y)
      local sep = petPane:CreateTexture(nil, "ARTWORK")
      sep:SetTexture(TEX.FLAT)
      sep:SetPoint("LEFT",  petPane, "LEFT",  20, 0)
      sep:SetPoint("RIGHT", petPane, "RIGHT", -20, 0)
      sep:SetPoint("TOP",   petPane, "TOP",   0, y)
      sep:SetHeight(1)
      sep:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.20)
    end

    -- ── Identité ──
    mkPetHeader("Identité", -6)

    local aPetToggle = mkRowAnchor(petPane, 380, -26)
    petToggleBtn = mkButton(aPetToggle, "Activer le familier", 180, 22, 0, 0, function()
      if not Core or not Core.SetPetEnabled then return end
      local p = Core.GetPet and Core.GetPet() or nil
      Core.SetPetEnabled(not (p and p.enabled))
    end)
    UI.petAuthorityToggleBtn = mkButton(aPetToggle, "Autorité", 180, 22, 200, 0, function()
      if not Core or not Core.SetPetAuthorityEnabled then return end
      local p = Core.GetPet and Core.GetPet() or nil
      Core.SetPetAuthorityEnabled(not (p and p.authorityEnabled))
    end)

    local aPetNom = mkRowAnchor(petPane, 230, -54)
    mkLabel(aPetNom, "Nom", 0, -2)
    petNameEB = mkEdit(aPetNom, 180, 20, 46, 0, applyAllPet)
    petNameEB:SetNumeric(false)

    local aPetHP = mkRowAnchor(petPane, 230, -80)
    mkLabel(aPetHP, "PV", 0, -2)
    petHpCurEB = mkEdit(aPetHP, 70, 20, 30,  0, applyAllPet)
    mkLabel(aPetHP, "/", 106, -2)
    petHpMaxEB = mkEdit(aPetHP, 70, 20, 120, 0, applyAllPet)

    -- ── Armure & Esquive ──
    mkPetSep(-106)
    mkPetHeader("Armure & Esquive", -114)

    local aPetDef1 = mkRowAnchor(petPane, 320, -132)
    mkLabel(aPetDef1, "Armure", 0, -2)
    petArmorEB     = mkEdit(aPetDef1, 70, 20, 60,  0, applyAllPet)
    mkLabel(aPetDef1, "Armure invul", 150, -2)
    petTrueArmorEB = mkEdit(aPetDef1, 70, 20, 244, 0, applyAllPet)

    local aPetDef2 = mkRowAnchor(petPane, 160, -160)
    mkLabel(aPetDef2, "Esquive", 0, -2)
    petDodgeEB = mkEdit(aPetDef2, 70, 20, 60, 0, applyAllPet)

    -- ── Actions ──
    mkPetSep(-188)
    mkPetHeader("Actions", -196)

    local aPetVal = mkRowAnchor(petPane, 180, -214)
    mkLabel(aPetVal, "Valeur", 0, -2)
    petActionValEB = mkEdit(aPetVal, 80, 20, 56, 0)

    local aPetBtns1 = mkRowAnchor(petPane, 392, -240)
    petDmgArmorBtn = mkButton(aPetBtns1, "Dégâts (armure)", 190, 22, 0,   0, function()
      if Core and Core.PetDamageWithArmor then Core.PetDamageWithArmor(getNumber(petActionValEB) or 0) end
    end)
    petDmgTrueBtn = mkButton(aPetBtns1, "Dégâts (bruts)", 190, 22, 202, 0, function()
      if Core and Core.PetDamageTrue then Core.PetDamageTrue(getNumber(petActionValEB) or 0) end
    end)

    local aPetBtns2 = mkRowAnchor(petPane, 392, -268)
    petHealBtn = mkButton(aPetBtns2, "Soins", 190, 22, 0, 0, function()
      if Core and Core.PetHeal then Core.PetHeal(getNumber(petActionValEB) or 0) end
    end)
    petDivineBtn = mkButton(aPetBtns2, "Soins divins (75%)", 190, 22, 202, 0, function()
      if Core and Core.PetDivineHeal then Core.PetDivineHeal() end
    end)

    local aPetBtns3 = mkRowAnchor(petPane, 392, -306)
    petSurgeryBtn = mkButton(aPetBtns3, "Chirurgie (50%)", 190, 22, 0, 0, function()
      if Core and Core.PetSurgery then Core.PetSurgery() end
    end)

    -- ── Blocage ──
    mkPetSep(-336)
    mkPetHeader("Blocage", -344)

    local aPetBlock = mkRowAnchor(petPane, 310, -362)
    mkLabel(aPetBlock, "Bouclier magique", 0, -2)
    petMagicBlockEB = mkEdit(aPetBlock, 70, 20, 180, 0, applyAllPet)
    mkButton(aPetBlock, "Réinit.", 70, 20, 260, 0, function()
      if Core and Core.ResetPetTempMagicBlock then
        Core.ResetPetTempMagicBlock()
      elseif Core and Core.SetPetTempMagicBlock then
        Core.SetPetTempMagicBlock(0)
      end
    end)
  end

  -- ── Tab 9 : Familier — Historique ────────────────────────────────────────
  do
    local petHistHeader = pagePetArmor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    petHistHeader:SetPoint("TOPLEFT", pagePetArmor, "TOPLEFT", 4, -2)
    petHistHeader:SetTextColor(C.GOLD_DIM[1], C.GOLD_DIM[2], C.GOLD_DIM[3], 1)
    petHistHeader:SetText("Historique du familier")
    local petHistHeaderLine = pagePetArmor:CreateTexture(nil, "ARTWORK")
    petHistHeaderLine:SetTexture(TEX.FLAT)
    petHistHeaderLine:SetPoint("TOPLEFT", petHistHeader, "BOTTOMLEFT", 0, -2)
    petHistHeaderLine:SetPoint("RIGHT", pagePetArmor, "RIGHT", -4, 0)
    petHistHeaderLine:SetHeight(1)
    petHistHeaderLine:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.30)

    local petSF = CreateFrame("ScrollFrame", nil, pagePetArmor, "UIPanelScrollFrameTemplate")
    petSF:SetPoint("TOPLEFT",     petHistHeaderLine, "BOTTOMLEFT",  0, -4)
    petSF:SetPoint("BOTTOMRIGHT", pagePetArmor,      "BOTTOMRIGHT", -20, 44)
    UI.petHistoryScroll = petSF

    local petChild = CreateFrame("Frame", nil, petSF)
    petChild:SetSize(CONTENT_W - 64, 10)
    petSF:SetScrollChild(petChild)
    UI.petHistoryChild = petChild

    local petTxt = petChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    petTxt:SetPoint("TOPLEFT", 0, 0)
    petTxt:SetJustifyH("LEFT")
    petTxt:SetJustifyV("TOP")
    petTxt:SetWidth(CONTENT_W - 72)
    petTxt:SetTextColor(C.TEXT_NORMAL[1], C.TEXT_NORMAL[2], C.TEXT_NORMAL[3], 1)
    petTxt:SetText("")
    UI.petHistoryText = petTxt

    local function syncPetHistoryWidth()
      if not UI.petHistoryScroll or not UI.petHistoryChild or not UI.petHistoryText then return end
      local w = UI.petHistoryScroll:GetWidth() or 0
      if w <= 0 then return end
      local textW = math.max(80, w - 14)
      UI.petHistoryChild:SetWidth(textW)
      UI.petHistoryText:SetWidth(textW)
    end
    UI.syncPetHistoryWidth = syncPetHistoryWidth
    petSF:SetScript("OnSizeChanged", syncPetHistoryWidth)
    syncPetHistoryWidth()

    local petClearBtn = mkButton(pagePetArmor, "Effacer", 90, 20, 0, 0)
    petClearBtn:ClearAllPoints()
    petClearBtn:SetPoint("BOTTOMLEFT", pagePetArmor, "BOTTOMLEFT", 14, 12)
    petClearBtn:SetScript("OnClick", function()
      if Core and Core.ClearHistory then Core.ClearHistory() end
    end)
  end

  UI.inputs = {
    hpCur = hpCur, hpMax = hpMax, bonusHpMax = bonusHpValEB,
    armor = armorEB, trueArmor = trueArmorEB, tempArmor = tempArmorEB,
    dodge = dodgeEB,
    block = blockEB,
    msHp = msHpEB, msMaxHp = msMaxHpEB, msArmor = msArmorEB,
    mnsArmor = mnsArmorEB,
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
  UI.petButtons = { petDmgArmorBtn, petDmgTrueBtn, petHealBtn, petDivineBtn, petSurgeryBtn }

  setSidebarSection(1)

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

    -- Double border: dark inner + gold outer for selected state.
    b:SetBackdrop({
      edgeFile = TEX.FLAT,
      edgeSize = 2,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    b:SetBackdropBorderColor(0.08, 0.06, 0.02, 0.90)

    local row = (idx <= classBtnPerRow) and 1 or 2
    local idxInRow = (row == 1) and idx or (idx - classBtnPerRow)
    local anchor = (row == 1) and aClassRow1 or aClassRow2
    local x = (idxInRow - 1) * (CLASS_BTN_SIZE + CLASS_BTN_GAP_X)
    b:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, 0)

    -- Dark background behind the icon (visible in corners).
    local iconBg = b:CreateTexture(nil, "BACKGROUND")
    iconBg:SetPoint("TOPLEFT", 2, -2)
    iconBg:SetPoint("BOTTOMRIGHT", -2, 2)
    iconBg:SetTexture(TEX.FLAT)
    iconBg:SetColorTexture(0.04, 0.03, 0.01, 1)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.tex = tex
    setClassIconTexCoords(tex, classKey)

    -- Hover highlight.
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 2)
    hl:SetTexture(TEX.FLAT)
    hl:SetColorTexture(1, 1, 1, 0.15)

    b:SetScript("OnClick", function()
      if Core and Core.SetClassKey then Core.SetClassKey(classKey) end
    end)

    b:SetScript("OnEnter", function(self)
      b:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 1.0)
      local name = (Shared.CLASS_NAMES_FR and Shared.CLASS_NAMES_FR[classKey]) or classKey
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:ClearLines()
      GameTooltip:AddLine(name, C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
      -- Resource list
      local profile = Shared.RES_PROFILES_BY_CLASS and Shared.RES_PROFILES_BY_CLASS[classKey]
      if not profile then
        local style = Shared.CLASS_STYLES and Shared.CLASS_STYLES[classKey]
        if style and style.label then
          profile = {{ label = style.label }}
        end
      end
      if profile and #profile > 0 then
        local parts = {}
        for i = 1, #profile do parts[#parts + 1] = profile[i].label end
        GameTooltip:AddLine(table.concat(parts, ", "), 1, 1, 1, true)
      else
        GameTooltip:AddLine("Aucune ressource", 0.6, 0.6, 0.6, true)
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
      b:SetBackdropBorderColor(0.08, 0.06, 0.02, 0.90)
      GameTooltip:Hide()
    end)

    UI.classButtons[idx] = b
    return b
  end

  for i = 1, #CLASS_KEYS do
    mkClassButton(i, CLASS_KEYS[i])
  end

  refreshHpDisplay = function(s)
    if activeSection == 2 then
      -- Familiar section: show pet HP on the main bar.
      local pet       = type(s.pet) == "table" and s.pet or {}
      local petEnabled = not not pet.enabled
      if petEnabled then
        if UI.title then UI.title:SetText(pet.name or "Familier") end
        local petHp    = tonumber(pet.hp)    or 0
        local petMaxHp = math.max(1, tonumber(pet.maxHp) or 1)
        local petPct   = petHp / petMaxHp
        hpBar:SetValue(math.max(0, math.min(1, petPct)))
        hpText:SetText(string.format("PV familier : %d / %d (%d%%)", petHp, petMaxHp, roundPct(petPct)))
        Shared.UpdateHpShieldOverlays(
          UI.hpBlockOverlay, UI.hpMagicBlockOverlay, hpBar,
          petHp, petMaxHp, 0, tonumber(pet.tempMagicBlock) or 0
        )
        local petCap = 1.0
        if pet.wounds and pet.wounds.hit10 then petCap = 0.25
        elseif pet.wounds and pet.wounds.hit25 then petCap = 0.50 end
        UI.hpMarkerCache.baseMaxHp = petMaxHp
        UI.hpMarkerCache.effMaxHp  = petMaxHp
        UI.hpMarkerCache.cap       = petCap
        UI.repositionHpMarkers()
        if petCap >= 0.999 then
          capText:SetText("")
        else
          capText:SetText(string.format("Plafond de soins : %d%%", roundPct(petCap)))
        end
      else
        if UI.title then UI.title:SetText("Familier") end
        hpBar:SetValue(0)
        hpText:SetText("Aucun familier actif")
        Shared.UpdateHpShieldOverlays(UI.hpBlockOverlay, UI.hpMagicBlockOverlay, hpBar, 0, 1, 0, 0)
        UI.hpMarkerCache.baseMaxHp = 0
        UI.hpMarkerCache.effMaxHp  = 1
        UI.hpMarkerCache.cap       = 1.0
        UI.repositionHpMarkers()
        capText:SetText("")
      end
    else
      -- Character section: show character HP.
      updateWindowTitle()
      local baseMaxHp = (s.maxHp or 0)
      local bonusHp   = math.max(0, s.bonusHp or 0)
      local effMaxHp  = baseMaxHp + bonusHp
      local hpNow     = (s.hp or 0)
      local hpPct     = (effMaxHp > 0) and (hpNow / effMaxHp) or 0
      hpBar:SetValue(math.max(0, math.min(1, hpPct)))
      if bonusHp > 0 then
        hpText:SetText(string.format("PV : %d / %d (+%d bonus, %d%%)", hpNow, effMaxHp, bonusHp, roundPct(hpPct)))
      else
        hpText:SetText(string.format("PV : %d / %d (%d%%)", hpNow, baseMaxHp, roundPct(hpPct)))
      end
      Shared.UpdateHpShieldOverlays(
        UI.hpBlockOverlay, UI.hpMagicBlockOverlay, hpBar,
        hpNow, effMaxHp, s.tempBlock or 0, (s.magicShield and s.magicShield.hp or 0)
      )
      local cap
      local w2 = s.wounds
      if w2 and w2.hit10 then cap = 0.25
      elseif w2 and w2.hit25 then cap = 0.50
      else cap = 1.0 end
      UI.hpMarkerCache.baseMaxHp = baseMaxHp
      UI.hpMarkerCache.effMaxHp  = effMaxHp
      UI.hpMarkerCache.cap       = cap
      UI.repositionHpMarkers()
      if cap >= 0.999 then
        capText:SetText("")
      else
        capText:SetText(string.format("Plafond de soins : %d%%", roundPct(cap)))
      end
    end
  end

  onChangeCallback = function(s)
    lastState = s
    refreshHpDisplay(s)

    -- Resources (character section only)
    if activeSection == 1 then
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

    if UI.noResHint then
      if rowCount == 0 then UI.noResHint:Show() else UI.noResHint:Hide() end
    end
    -- Resources are merged into tab 1 (Fiche); tab 2 is always hidden.
    if UI.tabDisabled then
      UI.tabDisabled[2] = (rowCount == 0)
      setTab(UI.activeTab or 1)
    end

    -- Default: hide resource threshold markers; they'll be re-shown when applicable.
    hideMarkers(UI.corruptionMarkers)
    hideMarkers(UI.insanityMarkers)
    hideMarkers(UI.arcaneChargeMarkers)

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
          UI.refreshShamanBar()
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

          local isWarlockCorruption = (s.classKey == "WARLOCK"      and p.idx == 2)
          local isShadowInsanity    = (s.classKey == "SHADOWPRIEST" and p.idx == 2)
          local isMageArcaneCharge  = (s.classKey == "MAGE"         and p.idx == 2)

          local displayMax = maxv
          if isWarlockCorruption then
            maxv = 60
            if cur < 0 then cur = 0 elseif cur > 60 then cur = 60 end
            displayMax = 60
          elseif isShadowInsanity then
            -- No real maximum, but bar display caps at 25.
            displayMax = 25
            if cur < 0 then cur = 0 end
          elseif isMageArcaneCharge then
            maxv = 8
            if cur < 0 then cur = 0 elseif cur > 8 then cur = 8 end
            displayMax = 8
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
            elseif isMageArcaneCharge then
              local tier
              if cur >= 8 then
                tier = "T5 disponible"
              elseif cur >= 4 then
                tier = "T4 disponible"
              end
              if tier then
                txt:SetText(string.format(
                  "%s : %d / %d — %s",
                  p.label or "Charge arcanique", cur, maxv, tier
                ))
              else
                txt:SetText(string.format(
                  "%s : %d / %d",
                  p.label or "Charge arcanique", cur, maxv
                ))
              end
            else
              txt:SetText(string.format("%s : %d / %d (%d%%)", p.label or "Ressource", cur, maxv, roundPct(pct)))
            end
          end

          -- Threshold markers
          if isWarlockCorruption then
            positionMarkers(UI.corruptionMarkers, bar)
          elseif isShadowInsanity then
            positionMarkers(UI.insanityMarkers, bar)
          elseif isMageArcaneCharge then
            positionMarkers(UI.arcaneChargeMarkers, bar)
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
            elseif isMageArcaneCharge then
              setNumber(maxEB, 8)
            else
              setNumber(maxEB, maxv)
            end
          end

          -- Fixed/scaled max boxes.
          local fixedMax = isWarlockCorruption or isShadowInsanity or isMageArcaneCharge
          setEditBoxEnabled(maxEB, not fixedMax)
        end
      end
    end

    else
      -- Familiar section: collapse all resource bars so the content host sits under the HP bar.
      for i = 1, 5 do
        if UI.resBars  and UI.resBars[i]  then UI.resBars[i]:Hide() end
        if UI.resTexts and UI.resTexts[i] then UI.resTexts[i]:SetText("") end
        if UI.resRow   and UI.resRow[i]   then UI.resRow[i]:Hide() end
      end
      hideMarkers(UI.corruptionMarkers)
      hideMarkers(UI.insanityMarkers)
      UI.resAnchor = hpBar
      applyContentHostLayout(hpBar, 0)
      if UI.syncHistoryWidth then UI.syncHistoryWidth() end
    end  -- activeSection == 1

    if UI.classButtons then
      for i = 1, #UI.classButtons do
        local b = UI.classButtons[i]
        if b and b.classKey then
          if b.classKey == s.classKey then
            b:SetAlpha(1)
            b:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 1.0)
          else
            b:SetAlpha(0.70)
            b:SetBackdropBorderColor(0.08, 0.06, 0.02, 0.90)
          end
        end
      end
    end

    -- Postures Élémentaires (Shaman uniquement)
    do
      local isSham = (s.classKey == "SHAMAN") and (activeSection == 1)
      if UI.postureSectionLabel then
        if isSham then UI.postureSectionLabel:Show() else UI.postureSectionLabel:Hide() end
      end
      if UI.postureSepLine then
        if isSham then UI.postureSepLine:Show() else UI.postureSepLine:Hide() end
      end
      local reqKeys = { TERRE = "res", AIR = "res2", EAU = "res3", FEU = "res4" }
      if UI.postureButtons then
        for _, b in ipairs(UI.postureButtons) do
          if isSham then
            b:Show()
            local pk = b._postureKey
            local rk = reqKeys[pk]
            local pts = rk and (s[rk] or 0) or 0
            local canUse = (pts >= 3)
            local isActive = (s.shamanPosture == pk)
            setButtonEnabled(b, canUse)
            if isActive then
              b:SetBackdropColor(b._postureR * 0.35, b._postureG * 0.35, b._postureB * 0.35, 0.95)
              b:SetBackdropBorderColor(b._postureR, b._postureG, b._postureB, 1.0)
            else
              b:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.90)
              b:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.80)
            end
          else
            b:Hide()
          end
        end
      end
    end

    -- Inputs : on reflète la state (pratique MVP)
    setNumber(UI.inputs.hpCur, s.hp)
    setNumber(UI.inputs.hpMax, s.maxHp)
    setNumber(UI.inputs.bonusHpMax, s.bonusHpMax)
    if UI.bonusHpToggleBtn then
      UI.bonusHpToggleBtn:SetText((s.bonusHp or 0) > 0 and "Désactiver PV bonus" or "Activer PV bonus")
    end
    -- Resource inputs are handled per-row above.
    setNumber(UI.inputs.armor, s.armor)
    setNumber(UI.inputs.trueArmor, s.trueArmor)
    setNumber(UI.inputs.tempArmor, s.tempArmor)
    setNumber(UI.inputs.dodge, s.dodge)
    setNumber(UI.inputs.block, s.tempBlock)
    local ms = s.magicShield or {}
    setNumber(UI.inputs.msHp,    ms.hp)
    setNumber(UI.inputs.msMaxHp, ms.maxHp)
    setNumber(UI.inputs.msArmor, ms.armor)
    local mns = s.manaShield or {}
    setNumber(UI.inputs.mnsArmor, mns.armor)
    if UI.manaShieldToggleBtn then
      local isMage = (s.classKey == "MAGE")
      UI.manaShieldToggleBtn:SetShown(isMage)
      if UI.manaShieldArmorLabel then UI.manaShieldArmorLabel:SetShown(isMage) end
      if UI.manaShieldArmorEB then
        local w = UI.manaShieldArmorEB._wrap
        if w then w:SetShown(isMage) else UI.manaShieldArmorEB:SetShown(isMage) end
      end
      if isMage then
        UI.manaShieldToggleBtn:SetText(mns.active and "Désactiver bouclier de mana" or "Activer bouclier de mana")
      end
    end

    local p = s.pet or {}
    local petEnabled = not not p.enabled
    if UI.petToggleBtn and UI.petToggleBtn.SetText then
      if petEnabled then
        UI.petToggleBtn:SetText("Désactiver le familier")
      else
        UI.petToggleBtn:SetText("Activer le familier")
      end
    end
    if UI.petAuthorityToggleBtn and UI.petAuthorityToggleBtn.SetText then
      if p.authorityEnabled then
        UI.petAuthorityToggleBtn:SetText("Désactiver points d'autorité")
      else
        UI.petAuthorityToggleBtn:SetText("Activer points d'autorité")
      end
    end

    if UI.refreshPopupToggleBtn then UI.refreshPopupToggleBtn() end

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

    -- Historique personnage (tab 7)
    if UI.historyText and UI.historyChild then
      local hist = s.history
      local text = formatHistoryText(hist, "CHAR")
      if not text then
        UI.historyText:SetText("Aucun évènement récent.")
        UI.historyChild:SetHeight(20)
      else
        UI.historyText:SetText(text)
        local h = (UI.historyText.GetStringHeight and UI.historyText:GetStringHeight()) or 0
        UI.historyChild:SetHeight(math.max(20, h + 10))
      end
    end

    -- Historique familier (tab 9)
    if UI.petHistoryText and UI.petHistoryChild then
      local hist = s.history
      local text = formatHistoryText(hist, "PET")
      if not text then
        UI.petHistoryText:SetText("Aucun évènement récent.")
        UI.petHistoryChild:SetHeight(20)
      else
        UI.petHistoryText:SetText(text)
        local h = (UI.petHistoryText.GetStringHeight and UI.petHistoryText:GetStringHeight()) or 0
        UI.petHistoryChild:SetHeight(math.max(20, h + 10))
      end
    end
  end
  Core.OnChange(function(s)
    onChangeCallback(s)
    if UI.refreshUndoRedo then UI.refreshUndoRedo() end
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
