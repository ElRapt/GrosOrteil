---@diagnostic disable: undefined-global
-- Addon-owned presentation only. No Blizzard globals, secure handlers or game
-- state are replaced here. Shared's public skin helpers remain compatibility
-- aliases so every window uses the same palette and animation lifecycle.
local _, ns = ...
local Shared = ns.Shared
local Theme = {}
ns.Theme = Theme

local PALETTES = { slate = {
  GOLD = {0.78, 0.64, 0.39}, GOLD_BRIGHT = {0.94, 0.79, 0.49},
  GOLD_LIGHT = {0.98, 0.88, 0.68}, GOLD_DIM = {0.71, 0.67, 0.57},
  GOLD_MUTED = {0.30, 0.35, 0.42},
  -- Retain the tab builders' color keys while giving them neutral surfaces.
  BROWN_DEEP = {0.035, 0.045, 0.065}, BROWN_DARK = {0.065, 0.085, 0.115},
  BROWN_MED = {0.12, 0.16, 0.21}, BROWN_WARM = {0.18, 0.22, 0.28},
  CREAM = {0.92, 0.91, 0.87}, CREAM_DIM = {0.73, 0.77, 0.81},
  TEXT_TITLE = {0.98, 0.88, 0.68}, TEXT_BRIGHT = {0.96, 0.97, 0.98},
  TEXT_NORMAL = {0.83, 0.87, 0.91}, TEXT_LABEL = {0.72, 0.78, 0.84},
  TEXT_DIM = {0.57, 0.64, 0.72}, TEXT_DISABLED = {0.40, 0.46, 0.53},
  RED_HP = {0.72, 0.20, 0.27}, BG_PANEL = {0.025, 0.035, 0.05},
  SUCCESS = {0.36, 0.78, 0.65}, DANGER = {0.95, 0.48, 0.43},
}, legacy = {
  GOLD = {1.00, 0.675, 0.125}, GOLD_BRIGHT = {1.00, 0.82, 0.22},
  GOLD_LIGHT = {1.00, 0.90, 0.55}, GOLD_DIM = {0.85, 0.70, 0.40},
  GOLD_MUTED = {0.55, 0.42, 0.18},
  BROWN_DEEP = {0.08, 0.05, 0.02}, BROWN_DARK = {0.14, 0.09, 0.04},
  BROWN_MED = {0.24, 0.17, 0.08}, BROWN_WARM = {0.32, 0.24, 0.12},
  CREAM = {0.92, 0.86, 0.74}, CREAM_DIM = {0.78, 0.72, 0.58},
  TEXT_TITLE = {1.00, 0.84, 0.30}, TEXT_BRIGHT = {1.00, 0.95, 0.80},
  TEXT_NORMAL = {0.90, 0.84, 0.68}, TEXT_LABEL = {0.82, 0.74, 0.55},
  TEXT_DIM = {0.60, 0.52, 0.36}, TEXT_DISABLED = {0.40, 0.34, 0.22},
  RED_HP = {0.80, 0.15, 0.15}, BG_PANEL = {0.06, 0.04, 0.02},
  SUCCESS = {0.36, 0.78, 0.65}, DANGER = {0.95, 0.48, 0.43},
} }
local C = {}
Theme.Colors = C
Theme.Textures = {
  FLAT = "Interface/Buttons/WHITE8x8",
  STATUSBAR = "Interface/Buttons/WHITE8x8",
}
local FLAT = Theme.Textures.FLAT
local SLATE_BACKDROP = {
  bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
  insets = {left = 1, right = 1, top = 1, bottom = 1},
}

local LEGACY_BACKDROP = {
  bgFile = FLAT, edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 12,
  insets = {left = 3, right = 3, top = 3, bottom = 3},
}
local LEGACY_BOARD = {edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 16}
local LEGACY_SURFACES = {
  CREAMY_BROWN = {0.48, 0.39, 0.32}, GOLD = PALETTES.legacy.GOLD,
  CARD_BG = {0.085, 0.065, 0.045}, PLAQUE_BG = {0.10, 0.075, 0.05},
  EDGE = 4, WOOD = 20,
}
local TRP3_BG = "Interface/AddOns/totalRP3/Resources/UI/ui-frame-neutral-background"
local TRP3_WOOD_V = "Interface/AddOns/totalRP3/Resources/UI/!ui-frame-wooden-border"
local TRP3_WOOD_H = "Interface/AddOns/totalRP3/Resources/UI/_ui-frame-wooden-border"
local BLIZZ_BG = "Interface/FrameGeneral/UIFrameNeutralBackground"
Theme.Backdrop = {}
Shared.THEME = {}
Shared.BACKDROP_BOARD = {}
Shared.BACKDROP_NOTE = Theme.Backdrop

-- UI modules capture these tables (and individual RGB tables) while loading,
-- before WoW restores SavedVariables. Preserve every captured reference.
local function copyInto(target, source)
  for key in pairs(target) do
    if source[key] == nil then target[key] = nil end
  end
  for key, value in pairs(source) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then target[key] = {} end
      copyInto(target[key], value)
    else
      target[key] = value
    end
  end
end

local activeName, initialized = "slate", false
local function applyPalette(name)
  activeName = name
  local legacy = name == "legacy"
  copyInto(C, PALETTES[name])
  copyInto(Theme.Backdrop, legacy and LEGACY_BACKDROP or SLATE_BACKDROP)
  copyInto(Shared.BACKDROP_BOARD, legacy and LEGACY_BOARD or SLATE_BACKDROP)
  copyInto(Shared.THEME, legacy and LEGACY_SURFACES or {
    CREAMY_BROWN = C.GOLD_MUTED, GOLD = C.GOLD,
    CARD_BG = C.BROWN_DARK, PLAQUE_BG = C.BROWN_MED, EDGE = 4, WOOD = 0,
  })
  Theme.Textures.STATUSBAR = legacy and "Interface/TargetingFrame/UI-StatusBar" or FLAT
end
applyPalette("slate")

function Theme.GetName() return activeName end

function Theme.GetSelectedName()
  local db = ns.GetDB and ns.GetDB()
  local settings = type(db) == "table" and db.settings
  return type(settings) == "table" and settings.theme == "legacy" and "legacy" or "slate"
end

-- Saving the selection never restyles existing (potentially secure) frames.
-- The UI applies it through an explicit reload, outside combat.
function Theme.SetName(name)
  if type(name) ~= "string" or not PALETTES[name] then return false end
  local db = ns.GetDB and ns.GetDB()
  if type(db) ~= "table" then return false end
  if type(db.settings) ~= "table" then db.settings = {} end
  db.settings.theme = name
  return true
end

function Theme.RequiresReload()
  return Theme.GetSelectedName() ~= activeName
end

-- Called after ADDON_LOADED restores the character's settings, before any UI
-- is built. Repeated initialization must not apply a pending choice live.
function Theme.Initialize()
  if initialized then return end
  local name = Theme.GetSelectedName()
  Theme.SetName(name)
  local db = ns.GetDB and ns.GetDB()
  if type(db) == "table" and type(db.settings) == "table" then db.settings.reduceMotion = nil end
  applyPalette(name)
  initialized = true
end

local function color(region, rgb, alpha)
  region:SetColorTexture(rgb[1], rgb[2], rgb[3], alpha or 1)
end

function Theme.ApplyNoteSkin(frame, alpha)
  frame:SetBackdrop(Theme.Backdrop)
  if activeName == "legacy" then
    local T = Shared.THEME
    frame:SetBackdropColor(T.CARD_BG[1], T.CARD_BG[2], T.CARD_BG[3], alpha or 0.92)
    frame:SetBackdropBorderColor(T.CREAMY_BROWN[1], T.CREAMY_BROWN[2], T.CREAMY_BROWN[3], 0.90)
    return
  end
  frame:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], alpha or 0.98)
  frame:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.65)
end

function Theme.ApplyBoardSkin(frame)
  if activeName == "legacy" then
    local T = Shared.THEME
    frame:SetBackdrop(Shared.BACKDROP_BOARD)
    frame:SetBackdropBorderColor(T.CREAMY_BROWN[1], T.CREAMY_BROWN[2], T.CREAMY_BROWN[3], 1)
    if rawget(frame, "_goBoard") then return frame._goBoard end
    local board = frame:CreateTexture(nil, "BACKGROUND")
    board:SetTexture(rawget(_G, "TRP3_API") and TRP3_BG or BLIZZ_BG, "REPEAT", "REPEAT")
    board:SetHorizTile(true); board:SetVertTile(true)
    board:SetPoint("TOPLEFT", frame, "TOPLEFT", T.EDGE, -T.EDGE)
    board:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.EDGE, T.EDGE)
    board:SetVertexColor(0.60, 0.60, 0.60)
    frame._goBoard = board
    return board
  end
  Theme.ApplyNoteSkin(frame, 1)
  frame:SetBackdropColor(C.BG_PANEL[1], C.BG_PANEL[2], C.BG_PANEL[3], 0.98)
  if rawget(frame, "_goBoard") then return frame._goBoard end
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 1, -1)
  bg:SetPoint("BOTTOMRIGHT", -1, 1)
  color(bg, C.BG_PANEL, 0.98)
  local wash = frame:CreateTexture(nil, "BORDER")
  wash:SetPoint("TOPLEFT", 2, -2)
  wash:SetPoint("TOPRIGHT", -2, -2)
  wash:SetHeight(130)
  wash:SetTexture(FLAT)
  wash:SetGradient("VERTICAL", CreateColor(0.10, 0.15, 0.22, 0), CreateColor(0.10, 0.15, 0.22, 0.60))
  frame._goBoard = bg
  return bg
end

local function applyLegacyRails(frame)
  local EDGE, WOOD = Shared.THEME.EDGE, Shared.THEME.WOOD
  if rawget(_G, "TRP3_API") then
    local function woodV(point, x, flip)
      local t = frame:CreateTexture(nil, "BORDER", nil, -3)
      t:SetTexture(TRP3_WOOD_V, "REPEAT", "REPEAT"); t:SetVertTile(true)
      t:SetWidth(WOOD)
      t:SetPoint("TOP" .. point, frame, "TOP" .. point, x, -EDGE)
      t:SetPoint("BOTTOM" .. point, frame, "BOTTOM" .. point, x, EDGE)
      if flip then t:SetTexCoord(0.2265625, 0.0078125, 0, 1)
      else t:SetTexCoord(0.0078125, 0.2265625, 0, 1) end
      t:SetVertexColor(1, 0.8, 0.8)
    end
    local function woodH(point, y, top, bottom)
      local t = frame:CreateTexture(nil, "BORDER", nil, -2)
      t:SetTexture(TRP3_WOOD_H, "REPEAT", "REPEAT"); t:SetHorizTile(true)
      t:SetHeight(WOOD)
      t:SetPoint(point .. "LEFT", frame, point .. "LEFT", EDGE, y)
      t:SetPoint(point .. "RIGHT", frame, point .. "RIGHT", -EDGE, y)
      t:SetTexCoord(0, 1, top, bottom); t:SetVertexColor(1, 0.8, 0.8)
    end
    woodV("LEFT", EDGE, false); woodV("RIGHT", -EDGE, true)
    woodH("TOP", -EDGE, 0.484375, 0.921875)
    woodH("BOTTOM", EDGE, 0.015625, 0.453125)
  else
    local function rail()
      local t = frame:CreateTexture(nil, "BORDER", nil, -2)
      t:SetColorTexture(0.23, 0.16, 0.10, 1)
      return t
    end
    local left, right, top, bottom = rail(), rail(), rail(), rail()
    left:SetPoint("TOPLEFT", EDGE, -EDGE); left:SetPoint("BOTTOMLEFT", EDGE, EDGE); left:SetWidth(WOOD)
    right:SetPoint("TOPRIGHT", -EDGE, -EDGE); right:SetPoint("BOTTOMRIGHT", -EDGE, EDGE); right:SetWidth(WOOD)
    top:SetPoint("TOPLEFT", EDGE, -EDGE); top:SetPoint("TOPRIGHT", -EDGE, -EDGE); top:SetHeight(WOOD)
    bottom:SetPoint("BOTTOMLEFT", EDGE, EDGE); bottom:SetPoint("BOTTOMRIGHT", -EDGE, EDGE); bottom:SetHeight(WOOD)
  end
end

function Theme.ApplyBoardRails(frame)
  if rawget(frame, "_goRails") then return end
  frame._goRails = true
  if activeName == "legacy" then applyLegacyRails(frame); return end
  for _, corner in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
    local left = corner:find("LEFT", 1, true)
    local top = corner:find("TOP", 1, true)
    local x, y = left and 1 or -1, top and -1 or 1
    local h = frame:CreateTexture(nil, "BORDER")
    h:SetSize(24, 2); h:SetPoint(corner, frame, corner, x, y); color(h, C.GOLD, 0.70)
    local v = frame:CreateTexture(nil, "BORDER")
    v:SetSize(2, 18); v:SetPoint(corner, frame, corner, x, y); color(v, C.GOLD, 0.70)
  end
end

function Theme.MakePlaque(frame, height)
  local plaque = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  plaque:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -10)
  plaque:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -10)
  plaque:SetHeight(height or 38)
  if activeName == "legacy" then
    local T = Shared.THEME
    Theme.ApplyNoteSkin(plaque)
    plaque:SetBackdropColor(T.PLAQUE_BG[1], T.PLAQUE_BG[2], T.PLAQUE_BG[3], 0.97)
    plaque:SetBackdropBorderColor(T.CREAMY_BROWN[1], T.CREAMY_BROWN[2], T.CREAMY_BROWN[3], 1)
    return plaque
  end
  local line = plaque:CreateTexture(nil, "BACKGROUND")
  line:SetPoint("BOTTOMLEFT", 0, 0); line:SetPoint("BOTTOMRIGHT", 0, 0)
  line:SetHeight(1); color(line, C.GOLD, 0.32)
  return plaque
end

local fades = setmetatable({}, {__mode = "k"})

-- Small controllers keep native animation groups private. Stopping a close
-- must never run its completion action; fast close/open and Escape are safe.
local function animation(region, from, to, duration, finish, allowed, looping)
  local group = region:CreateAnimationGroup()
  local alpha = group:CreateAnimation("Alpha")
  alpha:SetFromAlpha(from); alpha:SetToAlpha(to)
  alpha:SetDuration(duration); alpha:SetSmoothing("OUT")
  if looping then group:SetLooping("BOUNCE") end
  local control = {}
  function control:Stop()
    group:Stop()
  end
  function control:IsPlaying() return group:IsPlaying() end
  function control:Play()
    self:Stop()
    if allowed and not allowed() then return end
    group:Play()
  end
  group:SetScript("OnFinished", function()
    if finish and (not allowed or allowed()) then finish() end
  end)
  return control
end

local function makeFade(frame, closing, duration, allowed)
  local entry = fades[frame]
  if not entry then
    entry = {}
    fades[frame] = entry
    frame:HookScript("OnHide", function()
      if entry.open then entry.open:Stop() end
      if entry.close then entry.close:Stop() end
    end)
    frame:HookScript("OnShow", function()
      if entry.close then entry.close:Stop() end
    end)
  end
  local key = closing and "close" or "open"
  if entry[key] then return entry[key] end
  local control = animation(frame, closing and 1 or 0, closing and 0 or 1,
    duration, closing and function() frame:Hide() end or nil, allowed)
  local play = control.Play
  function control:Play()
    local other = entry[closing and "open" or "close"]
    if other then other:Stop() end
    play(self)
  end
  entry[key] = control
  return control
end

function Theme.MakeFadeIn(frame, duration)
  return makeFade(frame, false, duration or 0.18)
end
function Theme.MakeFadeOut(frame, duration, allowed)
  return makeFade(frame, true, duration or 0.12, allowed)
end
function Theme.MakePulse(region)
  return animation(region, 1, 0.55, 0.85, nil, nil, true)
end

-- Texture-only hover feedback. HookScript preserves each control's tooltip
-- and click behavior. Never apply this helper to secure targeting buttons.
function Theme.AddHover(button)
  if rawget(button, "_goHover") then return end
  local glow = button:CreateTexture(nil, "OVERLAY")
  glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("BOTTOMRIGHT", -1, 1)
  color(glow, C.GOLD, 0.08)
  glow:Hide()
  local fade = animation(glow, 0, 1, 0.12)
  button._goHover = glow
  local function clear() fade:Stop(); glow:Hide() end
  button:HookScript("OnEnter", function()
    if button:IsEnabled() then glow:Show(); fade:Play() end
  end)
  button:HookScript("OnLeave", clear)
  button:HookScript("OnHide", clear)
end

function Theme.StyleButton(button, role)
  button._goRole = role
  Theme.ApplyNoteSkin(button)
  local label = rawget(button, "_fs") or rawget(button, "_text")
  local rgb = role == "danger" and C.DANGER or role == "primary" and C.SUCCESS or C.TEXT_NORMAL
  if label then label:SetTextColor(rgb[1], rgb[2], rgb[3], 1) end
  if role then button:SetBackdropBorderColor(rgb[1], rgb[2], rgb[3], 0.65) end
  Theme.AddHover(button)
end

function Theme.SectionHeader(parent, text, y, width)
  local band = parent:CreateTexture(nil, "BACKGROUND")
  band:SetPoint("TOPLEFT", -8, y + 5)
  band:SetSize(width + 16, 25)
  color(band, C.BROWN_MED, 0.7)
  local accent = parent:CreateTexture(nil, "ARTWORK")
  accent:SetPoint("TOPLEFT", -8, y + 5)
  accent:SetSize(2, 25)
  color(accent, C.GOLD, 0.8)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 8, y)
  label:SetWidth(width - 16)
  label:SetJustifyH("LEFT")
  label:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
  label:SetText(text)
  return label
end

function Theme.StyleClose(button)
  if activeName == "legacy" then Theme.AddHover(button); return end
  for _, getter in ipairs({
    "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture",
  }) do
    local texture = button[getter](button)
    if texture then texture:Hide() end
  end
  local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  label:SetPoint("CENTER", 0, 0); label:SetText("×")
  label:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)
  Theme.AddHover(button)
end

-- Values/thresholds stay authoritative. A brief tint acknowledges a change
-- without interpolating health, delaying actions or installing OnUpdate loops.
function Theme.WatchBar(bar)
  if rawget(bar, "_goValueFlash") then return end
  local flash = bar:CreateTexture(nil, "OVERLAY", nil, -1)
  flash:SetAllPoints(bar); flash:Hide()
  local effect = animation(flash, 1, 0, 0.28, function() flash:Hide() end)
  bar._goValueFlash = flash
  local previous
  bar:HookScript("OnValueChanged", function(_, value)
    if previous ~= nil and value ~= previous and bar:IsVisible() then
      color(flash, value < previous and C.DANGER or C.SUCCESS, 0.24)
      flash:Show(); effect:Play()
    end
    previous = value
  end)
  bar:HookScript("OnHide", function() effect:Stop(); flash:Hide(); previous = nil end)
end

Shared.ApplyBoardSkin = Theme.ApplyBoardSkin
Shared.ApplyBoardRails = Theme.ApplyBoardRails
Shared.ApplyNoteSkin = Theme.ApplyNoteSkin
Shared.MakePlaque = Theme.MakePlaque
Shared.MakeFadeIn = Theme.MakeFadeIn
Shared.MakeFadeOut = Theme.MakeFadeOut
Shared.MakePulse = Theme.MakePulse
