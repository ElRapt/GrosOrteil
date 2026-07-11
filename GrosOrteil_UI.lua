---@diagnostic disable: undefined-global, unused-local
local _, ns = ...
local Core = ns.Core
local History = ns.History
local Shared = ns.Shared
local ipairs = ipairs

local UI = {}
ns.UI = UI

-- Confirmation popup for the reset-to-defaults button.
_G.StaticPopupDialogs["GROSORTEIL_RESET_DEFAULTS"] = {
  text = "Réinitialiser tous les paramètres aux valeurs par défaut ?\nCette action est irréversible.",
  button1 = "Réinitialiser",
  button2 = "Annuler",
  OnAccept = function()
    if Core and Core.ResetToDefaults then Core.ResetToDefaults() end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

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
  edgeSize = 2,
  insets   = { left = 2, right = 2, top = 2, bottom = 2 },
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
-- Uses edgeSize=2 so borders never vanish due to subpixel rounding on resize.
local function mkEdit(parent, w, h, x, y, onEnter)
  local wrap = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  wrap:SetSize(w, h)
  wrap:SetPoint("TOPLEFT", x, y)
  wrap:SetBackdrop({
    bgFile   = TEX.FLAT,
    edgeFile = TEX.FLAT,
    edgeSize = 2,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  wrap:SetBackdropColor(C.BROWN_DEEP[1], C.BROWN_DEEP[2], C.BROWN_DEEP[3], 0.92)
  wrap:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.70)

  local eb = CreateFrame("EditBox", nil, wrap)
  eb:SetPoint("TOPLEFT", 5, -2)
  eb:SetPoint("BOTTOMRIGHT", -4, 2)
  eb:SetFontObject("GameFontHighlight")
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetTextColor(C.TEXT_BRIGHT[1], C.TEXT_BRIGHT[2], C.TEXT_BRIGHT[3], 1)

  eb:SetScript("OnEditFocusGained", function(self)
    wrap:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 0.90)
    wrap:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.95)
    -- Select the current value so typing replaces it (no manual erase needed).
    if self.HighlightText then self:HighlightText() end
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

  -- Migration registry: add new entries here; each runs exactly once per character.
  db.ui.migrations = db.ui.migrations or {}
  -- Seed legacy boolean flags into the registry so they don't re-run.
  if db.ui._migrated_20260214_wide    then db.ui.migrations["wide"]     = true end
  if db.ui._migrated_20260217_sidebar then db.ui.migrations["sidebar"]  = true end
  if db.ui._migrated_20260401_paramtab then db.ui.migrations["paramtab"] = true end
  local MIGRATIONS = {
    { key = "wide",     run = function() db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0 end },
    { key = "sidebar",  run = function() db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0 end },
    { key = "paramtab", run = function()
        db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0
        db.ui.w, db.ui.h = nil, nil
      end },
  }
  for _, m in ipairs(MIGRATIONS) do
    if not db.ui.migrations[m.key] then
      m.run()
      db.ui.migrations[m.key] = true
    end
  end

  local FRAME_W, FRAME_H = 880, 460
  local MIN_W, MIN_H     = 680, 380
  local MAX_W, MAX_H     = 1500, 1000
  -- Board geometry: content sits inside the wooden rails, below the plaque.
  local BODY_X      = 32   -- EDGE(4) + WOOD(20) + 8
  local BODY_TOP    = 48   -- EDGE(4) + 6 + plaque(30) + 8
  local BODY_BOTTOM = 30   -- EDGE(4) + WOOD(20) + 6
  local applyContentHostLayout  -- forward declaration; defined below
  local activeSectionRef        -- forward declaration; assigned below with initial value

  -- Left sidebar navigation (vertical tabs) + right content area.
  local SIDEBAR_W = 160
  local GUTTER = 12
  local CONTENT_W = FRAME_W - (BODY_X * 2) - SIDEBAR_W - GUTTER

  local frame = CreateFrame("Frame", "GrosOrteilFrame", UIParent, "BackdropTemplate")
  UI.frame = frame
  -- Clamp saved sizes from older versions that allowed a smaller minimum.
  frame:SetSize(math.max(MIN_W, db.ui.w or FRAME_W), math.max(MIN_H, db.ui.h or FRAME_H))

  -- QoL: allow ESC to close the window.
  -- WoW closes frames listed in UISpecialFrames when pressing Escape.
  do
    if type(_G.UISpecialFrames) ~= "table" then
      _G.UISpecialFrames = {}
    end
    local found = false
    for i = 1, #_G.UISpecialFrames do
      if _G.UISpecialFrames[i] == "GrosOrteilFrame" then
        found = true
        break
      end
    end
    if not found then
      _G.UISpecialFrames[#_G.UISpecialFrames + 1] = "GrosOrteilFrame"
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

  -- Bulletin-board skin: parchment + creamy tooltip border + wooden rails.
  Shared.ApplyBoardSkin(frame)
  Shared.ApplyBoardRails(frame)

  -- Header plaque pinned over the top rail (holds title + close button).
  local plaque = Shared.MakePlaque(frame, 30)
  UI.plaque = plaque

  -- Gentle fade-in whenever the window opens; fade-out when closed.
  local fadeIn = Shared.MakeFadeIn(frame, 0.18)
  frame:HookScript("OnShow", function()
    if fadeIn then fadeIn:Play() end
  end)
  local fadeOut = Shared.MakeFadeOut(frame, 0.15)
  UI.fadeOut = fadeOut

  frame:SetPoint(db.ui.point, UIParent, db.ui.point, db.ui.x, db.ui.y)
  if db.ui.shown then frame:Show() else frame:Hide() end

  -- Title: gold text on the plaque.
  local title = plaque:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  UI.title = title
  title:SetPoint("LEFT", plaque, "LEFT", 10, 0)
  title:SetJustifyH("LEFT")
  title:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
  title:SetShadowOffset(1, -1)
  title:SetShadowColor(0, 0, 0, 0.80)
  updateWindowTitle()

  -- Retry TRP3 hook once after a delay in case TRP3 initializes after us.
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(1.0, function()
      hookTRP3Callbacks()
      updateWindowTitle()
    end)
  end

  local close = CreateFrame("Button", nil, plaque, "UIPanelCloseButton")
  close:SetPoint("RIGHT", plaque, "RIGHT", -2, 0)
  close:SetSize(24, 24)
  close:SetScript("OnClick", function()
    if fadeOut and frame:IsShown() and not fadeOut:IsPlaying() then
      fadeOut:Play()
    else
      frame:Hide()
    end
  end)

  -- Plaque subtitle: current class (or "Familier"), right-aligned by the close button.
  local plaqueSub = plaque:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  plaqueSub:SetPoint("RIGHT", close, "LEFT", -6, 0)
  plaqueSub:SetJustifyH("RIGHT")
  plaqueSub:SetTextColor(0.72, 0.62, 0.50, 1)
  plaqueSub:SetText("")
  UI.plaqueSub = plaqueSub

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
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Redimensionner", C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
    GameTooltip:AddLine("Glisser : ajuster la taille de la fenêtre", 1, 1, 1, true)
    GameTooltip:AddLine("Clic droit : taille par défaut", 0.72, 0.62, 0.50, true)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local function onResizeUpdate()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    local w = math.max(MIN_W, math.min(MAX_W, resizeBaseW + (cx - resizeOriginX) / scale))
    local h = math.max(MIN_H, math.min(MAX_H, resizeBaseH - (cy - resizeOriginY) / scale))
    frame:SetSize(w, h)
  end

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
      grip:SetScript("OnUpdate", onResizeUpdate)
    end
  end)

  grip:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and resizing then
      grip:SetScript("OnUpdate", nil)
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
  -- Always-enabled with full propagation: OnKeyUp and OnChar always
  -- pass through so other panels (Collections, etc.) are never blocked.
  -- OnKeyDown only consumes Ctrl+Z/Y when the mouse is actually over
  -- the addon, so the check works even when mouse is over child frames.
  frame:EnableKeyboard(true)
  local function propagate(self) self:SetPropagateKeyboardInput(true) end
  frame:SetScript("OnKeyUp", propagate)
  frame:SetScript("OnChar",  propagate)
  frame:SetScript("OnKeyDown", function(self, key)
    if IsControlKeyDown() and (key == "z" or key == "Z") and self:IsMouseOver() then
      self:SetPropagateKeyboardInput(false)
      if Core and Core.Undo then
        Core.Undo()
        if UI.refreshUndoRedo then UI.refreshUndoRedo() end
      end
    elseif IsControlKeyDown() and (key == "y" or key == "Y") and self:IsMouseOver() then
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
      "Interface/Icons/inv12_apextalent_priest_benediction",
      "Restaurer PV",
      "Remet tous les PV au maximum (bonus inclus).",
      function()
        if activeSectionRef.v == 2 then Core.PetRestoreHP() else Core.RestoreHP() end
      end)
    iconRestore:SetPoint("BOTTOMRIGHT", grip, "BOTTOMLEFT", -50, 34)

    local iconRegenHP = mkActionIcon(frame,
      "Interface/Icons/inv12_spell_nature_rejuvenation_empowered",
      "Régénération quotidienne PV",
      "Restaure 10 % du max de PV, ignorant les seuils de PV.",
      function()
        if activeSectionRef.v == 2 then Core.PetDailyRegenHP() else Core.DailyRegenHP() end
      end)
    iconRegenHP:SetPoint("RIGHT", iconRestore, "LEFT", -ICON_GAP, 0)

    local iconRegenRes = mkActionIcon(frame,
      "Interface/Icons/inv12_spell_nature_starfall_empowered",
      "Régénération quotidienne mystique",
      "Restaure 20 % de la ressource principale (mana, énergie, etc.).",
      function()
        if activeSectionRef.v == 2 then Core.PetDailyRegenRes() else Core.DailyRegenRes() end
      end)
    iconRegenRes:SetPoint("RIGHT", iconRegenHP, "LEFT", -ICON_GAP, 0)
    -- Pet section has no primary resource (PetDailyRegenRes is a no-op), so
    -- hide the icon while in pet section instead of letting clicks do nothing.
    UI.iconRegenRes = iconRegenRes

  -- Main body: sidebar (left) + content (right), pinned on the parchment.
  local body = CreateFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_X, -BODY_TOP)
  body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BODY_X, BODY_BOTTOM)
  UI.body = body

  -- ── Sidebar ───────────────────────────────────────────────────────────
  local sidebar = CreateFrame("Frame", nil, body, "BackdropTemplate")
  sidebar:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  sidebar:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
  sidebar:SetWidth(SIDEBAR_W)
  Shared.ApplyNoteSkin(sidebar, 0.96)
  UI.sidebar = sidebar

  -- Top gradient overlay on sidebar for depth.
  local sidebarTopGrad = sidebar:CreateTexture(nil, "ARTWORK")
  sidebarTopGrad:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 3, -3)
  sidebarTopGrad:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -3, -3)
  sidebarTopGrad:SetHeight(40)
  sidebarTopGrad:SetTexture(TEX.FLAT)
  sidebarTopGrad:SetColorTexture(0, 0, 0, 0.18)
  sidebarTopGrad:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 1))

  -- Bottom gradient overlay on sidebar.
  local sidebarBotGrad = sidebar:CreateTexture(nil, "ARTWORK")
  sidebarBotGrad:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 3, 3)
  sidebarBotGrad:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -3, 3)
  sidebarBotGrad:SetHeight(30)
  sidebarBotGrad:SetTexture(TEX.FLAT)
  sidebarBotGrad:SetColorTexture(0, 0, 0, 0.15)
  sidebarBotGrad:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))

  -- Faded class emblem filling the sidebar's empty middle (TRP3-style watermark).
  local emblem = sidebar:CreateTexture(nil, "BORDER", nil, 2)
  emblem:SetSize(92, 92)
  emblem:SetPoint("CENTER", sidebar, "CENTER", 0, -14)
  emblem:SetDesaturated(true)
  emblem:SetVertexColor(1.0, 0.85, 0.60, 0.10)

  function UI.updateSidebarEmblem(classKey, isPet)
    if isPet then
      emblem:Show()
      Shared.SetClassEmblem(emblem, "HUNTER")
    elseif classKey and classKey ~= "" then
      emblem:Show()
      Shared.SetClassEmblem(emblem, classKey)
    else
      emblem:Hide()
    end
  end
  UI.updateSidebarEmblem(nil, false)

  -- ── Content area ──────────────────────────────────────────────────────
  -- A second note card; the parchment gutter between the two cards is what
  -- gives the "frames puzzled onto one board" look.
  local content = CreateFrame("Frame", nil, body, "BackdropTemplate")
  content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", GUTTER, 0)
  content:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  Shared.ApplyNoteSkin(content, 0.92)
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

    local function mkUndoBtn(parent, label, tipTitle, tipDesc, tipKey, onClick)
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
        if tipKey then
          GameTooltip:AddLine("Raccourci : " .. tipKey, 0.60, 0.52, 0.36)
        end
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
      "Annule la dernière action.", "Ctrl+Z",
      function() Core.Undo() end)
    undoBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", UBTN_PAD, UBTN_PAD)
    UI.undoBtn = undoBtn

    local redoBtn = mkUndoBtn(content, ">", "Rétablir",
      "Rétablit la dernière action annulée.", "Ctrl+Y",
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

  -- Floating combat text above the HP bar (dégâts, soins, esquive, blocage)
  local showCombatText = Shared.AttachFloatingText(hpBar)
  Core.SetCombatTextHandler(function(kind, amount)
    if kind == "DAMAGE" then
      showCombatText("-" .. Shared.Round(amount or 0), 1.00, 0.25, 0.25)
    elseif kind == "HEAL" then
      showCombatText("+" .. Shared.Round(amount or 0), 0.25, 1.00, 0.35)
    elseif kind == "BLOCK" then
      showCombatText("Blocage total", 0.65, 0.65, 0.65)
    elseif kind == "DODGE" then
      showCombatText("Esquivé", 1.00, 0.85, 0.10)
    end
  end)

  -- Marqueurs 50/25/10%
  UI.hpMarkers, UI.hpCapMarker = Shared.MakeHpThresholdMarkers(hpBar)

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

  local makeMarker = Shared.MakeMarker

  -- Class-resource threshold markers on bar #2 (Corruption / Insanité /
  -- Charge arcanique). Definitions are shared with the popup and raid panel.
  local function mkResMarkerSet(bar, classKey)
    local out = {}
    if bar then
      for i, d in ipairs(Shared.GetResMarkerDefs(classKey, 2)) do
        out[i] = makeMarker(bar, d.pct, d.r, d.g, d.b, d.a, d.w)
      end
    end
    return out
  end
  UI.corruptionMarkers   = mkResMarkerSet(UI.resBars[2], "WARLOCK")
  UI.insanityMarkers     = mkResMarkerSet(UI.resBars[2], "SHADOWPRIEST")
  UI.arcaneChargeMarkers = mkResMarkerSet(UI.resBars[2], "MAGE")

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
  activeSectionRef = { v = 1 }
  local lastStateRef     = { v = nil }
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
    -- Don't activate a tab that belongs to the inactive section.
    if active <= 7 and activeSection ~= 1 then return end
    if active >= 8 and activeSection ~= 2 then return end
    if UI.tabHidden and UI.tabHidden[active] then
      setTab(activeSection == 1 and 1 or 8)
      return
    end
    if UI.tabDisabled and UI.tabDisabled[active] then
      -- The previously-active tab just became disabled (e.g. resources for a
      -- class with no resources). Fall back to the section's home tab so the
      -- pages stay in sync — without this the disabled page kept rendering.
      local fallback = (activeSection == 1) and 1 or 8
      if active ~= fallback and not (UI.tabDisabled and UI.tabDisabled[fallback]) then
        setTab(fallback)
      end
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
    "Affixes",          -- 5
    "Classes",          -- 6 (was 3)
    "Historique",       -- 7
    "Familier",         -- 8  familiar section (merged)
    "Historique",       -- 9  familiar history
    "",                 -- 10 hidden slot
  }

  local NAV_PAD = 5
  local NAV_GAP = 1
  local NAV_BTN_H = 30

  -- Short descriptions shown when hovering the sidebar tabs.
  local TAB_TIPS = {
    [1] = "Points de vie, armure, attaque, actions et ressources du personnage.",
    [5] = "Affixes de zone : bonus et malus temporaires appliqués à la fiche.",
    [6] = "Choix de la classe : couleurs, ressources et seuils associés.",
    [7] = "Journal des évènements du personnage.",
    [8] = "Fiche du familier : PV, armure, attaque et actions.",
    [9] = "Journal des évènements du familier.",
  }

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

    -- Tooltip (also shown on the active/disabled tab via motion scripts).
    if TAB_TIPS[idx] then
      tab:SetMotionScriptsWhileDisabled(true)
      tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(text, C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
        GameTooltip:AddLine(TAB_TIPS[idx], 1, 1, 1, true)
        GameTooltip:Show()
      end)
      tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

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
  local pageAffixes = mkPage()   -- 5
  local pageClasses = mkPage()   -- 6 (was 3)
  local pageHistory = mkPage()   -- 7
  local pagePetHP     = mkPage() -- 8: familiar – Fiche (merged)
  local pagePetArmor  = mkPage() -- 9: familiar – Historique
  local pagePetCombat = mkPage() -- 10: hidden slot
  UI.pageHistory = pageHistory

  -- Tabs 2-4 are merged into tab 1 (Fiche). Tab 5 hosts the Affixes page.
  -- Tab 10 is a hidden slot (familiar has only Fiche + Historique).
  UI.tabHidden[2] = true
  UI.tabHidden[3] = true
  UI.tabHidden[4] = true
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
    activeSection      = sect
    activeSectionRef.v = sect
    repositionSidebarTabs()
    styleSectBtn(sectChar, sect == 1)
    styleSectBtn(sectPet,  sect == 2)
    if sect == 1 then
      if UI.activeTab and UI.activeTab >= 8 then setTab(1) end
    else
      if not UI.activeTab or UI.activeTab < 8 then setTab(8) end
    end
    -- Mystic-regen icon has no pet equivalent, so hide it in the pet section.
    if UI.iconRegenRes then
      if sect == 2 then UI.iconRegenRes:Hide() else UI.iconRegenRes:Show() end
    end
    -- Rég./tour is a character-only stat, so hide its icon in the pet section.
    if UI.iconRegenParTour then
      if sect == 2 then UI.iconRegenParTour:Hide() else UI.iconRegenParTour:Show() end
    end
    -- Full re-render for the newly active section.
    if lastState and onChangeCallback then onChangeCallback(lastState) end
  end

  local function makeSectBtn(btn, label, x, onClick, tip)
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
    if tip then
      btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(label, C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
  end

  makeSectBtn(sectChar, "Personnage", NAV_PAD,                    function() setSidebarSection(1) end,
    "Affiche les onglets du personnage (fiche, classes, historique).")
  makeSectBtn(sectPet,  "Familier",   NAV_PAD + SECT_BTN_W + 4,  function() setSidebarSection(2) end,
    "Affiche les onglets du familier (fiche, historique).")

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

  -- Reset-to-defaults button: text button centred in the sidebar.
  local resetBtn = mkButton(sidebar, "Réinitialiser", SIDEBAR_W - (NAV_PAD * 2), 24, 0, 0, function()
    if StaticPopup_Show then StaticPopup_Show("GROSORTEIL_RESET_DEFAULTS") end
  end)
  resetBtn:ClearAllPoints()
  resetBtn:SetPoint("BOTTOM", popupToggleBtn, "TOP", 0, 10)
  resetBtn:SetBackdropBorderColor(0.85, 0.30, 0.20, 0.80)
  if resetBtn._fs then
    resetBtn._fs:SetTextColor(1.00, 0.55, 0.40, 1)
  end
  resetBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Réinitialiser les paramètres", 1.00, 0.55, 0.40)
    GameTooltip:AddLine("Restaure toutes les valeurs aux valeurs par défaut.", 1, 1, 1, true)
    GameTooltip:AddLine("Cette action est irréversible.", 1, 0.4, 0.3, true)
    GameTooltip:Show()
  end)
  resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  UI.resetBtn = resetBtn

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

  -- Build the per-tab ctx dependency table.
  local tabCtx = {
    C = C, TEX = TEX, Core = Core, Shared = Shared,
    mkLabel = mkLabel, mkLabelCenter = mkLabelCenter,
    mkEdit = mkEdit, mkButton = mkButton, mkRowAnchor = mkRowAnchor,
    getNumber = getNumber, setNumber = setNumber,
    BLOCK_W = 440, CONTENT_W = CONTENT_W,
    setEditBoxEnabled = setEditBoxEnabled, setButtonEnabled = setButtonEnabled,
    positionMarkers = positionMarkers, hideMarkers = hideMarkers,
    roundPct = roundPct,
    getResProfile = getResProfile, getKeysForIdx = getKeysForIdx,
    applyResTextColor = applyResTextColor, formatHistoryText = formatHistoryText,
    setClassIconTexCoords = setClassIconTexCoords,
    setTab = setTab,
    hpBar = hpBar,
    applyContentHostLayout = applyContentHostLayout,
    rowAnchors = rowAnchors,
    activeSectionRef = activeSectionRef,
    lastStateRef     = lastStateRef,
    refreshHpDisplay = nil,  -- patched below after refreshHpDisplay is assigned
    mkActionIcon     = mkActionIcon,
    ICON_GAP         = ICON_GAP,
  }

  -- Onglet 1 : Fiche
  tabCtx.page = pageHP
  ns.UI_BuildFicheTab(tabCtx)
  UI.inputs = tabCtx.inputs

  -- Onglet 7 : Historique
  tabCtx.page = pageHistory
  ns.UI_BuildHistoryTab(tabCtx)

  -- Onglet 8 : Familier — Fiche
  tabCtx.page = pagePetHP
  ns.UI_BuildPetFicheTab(tabCtx)
  UI.inputs.petName            = tabCtx.petInputs.petName
  UI.inputs.petHpCur           = tabCtx.petInputs.petHpCur
  UI.inputs.petHpMax           = tabCtx.petInputs.petHpMax
  UI.inputs.petArmor           = tabCtx.petInputs.petArmor
  UI.inputs.petTrueArmor       = tabCtx.petInputs.petTrueArmor
  UI.inputs.petDodge           = tabCtx.petInputs.petDodge
  UI.inputs.petAttaqueMelee    = tabCtx.petInputs.petAttaqueMelee
  UI.inputs.petAttaqueDistance = tabCtx.petInputs.petAttaqueDistance
  UI.inputs.petTempArmor       = tabCtx.petInputs.petTempArmor
  UI.inputs.petMsHp            = tabCtx.petInputs.petMsHp
  UI.inputs.petMsMaxHp         = tabCtx.petInputs.petMsMaxHp
  UI.inputs.petMsArmor         = tabCtx.petInputs.petMsArmor
  UI.inputs.petActionVal       = tabCtx.petInputs.petActionVal

  -- Onglet 9 : Familier — Historique
  tabCtx.page = pagePetArmor
  ns.UI_BuildPetHistoryTab(tabCtx)

  setSidebarSection(1)

  -- Onglet 5 : Affixes
  tabCtx.page = pageAffixes
  ns.UI_BuildAffixesTab(tabCtx)

  -- Onglet 6 : Classes
  tabCtx.page = pageClasses
  ns.UI_BuildClassesTab(tabCtx)

  refreshHpDisplay = function(s)
    if activeSection == 2 then
      -- Familiar section: show pet HP on the main bar.
      local pet       = type(s.pet) == "table" and s.pet or {}
      local petEnabled = not not pet.enabled
      if UI.updateSidebarEmblem then UI.updateSidebarEmblem(nil, true) end
      if UI.plaqueSub then UI.plaqueSub:SetText("Familier") end
      if petEnabled then
        if UI.title then UI.title:SetText(pet.name or "Familier") end
        local petHp    = tonumber(pet.hp)    or 0
        local petMaxHp = math.max(1, tonumber(pet.maxHp) or 1)
        local petPct   = petHp / petMaxHp
        hpBar:SetValue(math.max(0, math.min(1, petPct)))
        hpText:SetText(string.format("PV familier : %d / %d (%d%%)", petHp, petMaxHp, roundPct(petPct)))
        local petMs = type(pet.magicShield) == "table" and pet.magicShield or {}
        Shared.UpdateHpShieldOverlays(
          UI.hpBlockOverlay, UI.hpMagicBlockOverlay, hpBar,
          petHp, petMaxHp, 0, tonumber(petMs.hp) or 0
        )
        local petCap = Shared.WoundCap(pet.wounds)
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
      if UI.updateSidebarEmblem then UI.updateSidebarEmblem(s.classKey, false) end
      if UI.plaqueSub then UI.plaqueSub:SetText(Shared.GetClassNameFr(s.classKey)) end
      local baseMaxHp = (s.maxHp or 0)
      local hpNow     = (s.hp or 0)
      local hpPct     = (baseMaxHp > 0) and (hpNow / baseMaxHp) or 0
      hpBar:SetValue(math.max(0, math.min(1, hpPct)))
      hpText:SetText(string.format("PV : %d / %d (%d%%)", hpNow, baseMaxHp, roundPct(hpPct)))
      Shared.UpdateHpShieldOverlays(
        UI.hpBlockOverlay, UI.hpMagicBlockOverlay, hpBar,
        hpNow, baseMaxHp, s.tempBlock or 0, (s.magicShield and s.magicShield.hp or 0)
      )
      local cap = Shared.WoundCap(s.wounds)
      UI.hpMarkerCache.baseMaxHp = baseMaxHp
      UI.hpMarkerCache.effMaxHp  = baseMaxHp
      UI.hpMarkerCache.cap       = cap
      UI.repositionHpMarkers()
      if cap >= 0.999 then
        capText:SetText("")
      else
        capText:SetText(string.format("Plafond de soins : %d%%", roundPct(cap)))
      end
    end
  end

  -- Patch refreshHpDisplay into the ctx now that it has been assigned.
  tabCtx.refreshHpDisplay = refreshHpDisplay

  onChangeCallback = ns.UI_BuildOnChangeCallback(tabCtx)

  -- Keep lastState in sync so setSidebarSection can re-invoke onChangeCallback.
  local _innerCb = onChangeCallback
  onChangeCallback = function(s)
    lastState      = s
    lastStateRef.v = s
    _innerCb(s)
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
  if show then
    -- Cancel a pending close fade so a re-open lands at full opacity.
    if UI.fadeOut then UI.fadeOut:Stop() end
    UI.frame:Show()
  else
    -- Fade out instead of vanishing (minimap-button and slash closes land here).
    if UI.fadeOut and UI.frame:IsShown() and not UI.fadeOut:IsPlaying() then
      UI.fadeOut:Play()
    else
      UI.frame:Hide()
    end
  end
end

function ns.UI_ResetPosition()
  local db = (ns.GetDB and ns.GetDB()) or rawget(_G, "GrosOrteilDBPC") or rawget(_G, "GrosOrteilDB") or {}
  db.ui = db.ui or {}
  db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0
  UI.frame:ClearAllPoints()
  UI.frame:SetPoint("CENTER")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- "Mise à jour disponible" reminder
-- WoW Lua cannot reach Curse/GitHub, so peers are the update feed: Comm
-- exchanges .toc versions (TRP3-style) and calls in here when someone runs
-- a newer build. The note hangs under the main window and is closable;
-- closing remembers the version so it only returns for an even newer one.
-- ═══════════════════════════════════════════════════════════════════════════
local updateBanner

function UI.NotifyUpdateAvailable(remoteVersion, localVersion)
  if not UI.frame then return end
  local cmp = Shared.CompareVersions
  if not cmp then return end

  local db = (ns.GetDB and ns.GetDB()) or {}
  db.settings = db.settings or {}
  local dismissed = db.settings.dismissedUpdateVersion
  if dismissed and cmp(remoteVersion, dismissed) ~= 1 then return end

  -- Already showing this (or a higher) version: nothing to update.
  if updateBanner and updateBanner._version
      and cmp(remoteVersion, updateBanner._version) ~= 1 then
    updateBanner:Show()
    return
  end

  if not updateBanner then
    local b = CreateFrame("Frame", nil, UI.frame, "BackdropTemplate")
    b:SetPoint("TOPLEFT",  UI.frame, "BOTTOMLEFT",  8, -4)
    b:SetPoint("TOPRIGHT", UI.frame, "BOTTOMRIGHT", -8, -4)
    b:SetHeight(30)
    Shared.ApplyNoteSkin(b, 0.96)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", b, "LEFT", 10, 0)
    icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")

    local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT",  icon, "RIGHT", 6, 0)
    text:SetPoint("RIGHT", b,    "RIGHT", -26, 0)
    text:SetJustifyH("LEFT")
    text:SetTextColor(1.00, 0.84, 0.30, 1)
    b.text = text

    local close = CreateFrame("Button", nil, b, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", b, "RIGHT", -3, 0)
    close:SetScript("OnClick", function()
      b:Hide()
      local d = (ns.GetDB and ns.GetDB()) or {}
      d.settings = d.settings or {}
      d.settings.dismissedUpdateVersion = b._version
    end)
    updateBanner = b
  end

  updateBanner._version = remoteVersion
  -- The version comes off the network: cap the displayed length.
  local remoteShown = tostring(remoteVersion):sub(1, 24)
  if localVersion and localVersion ~= "" then
    updateBanner.text:SetText(string.format(
      "Mise à jour disponible : version %s (la vôtre : %s)",
      remoteShown, tostring(localVersion):sub(1, 24)))
  else
    updateBanner.text:SetText("Mise à jour disponible : version " .. remoteShown)
  end
  updateBanner:Show()
end
