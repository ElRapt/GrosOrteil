---@diagnostic disable: undefined-global
-- Addon-owned presentation only. No Blizzard globals, secure handlers or game
-- state are replaced here. Shared's public skin helpers remain compatibility
-- aliases so every window uses the same palette and animation lifecycle.
local _, ns = ...
local Shared = ns.Shared
local Theme = {}
ns.Theme = Theme

local C = {
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
}
Theme.Colors = C
Theme.Textures = {
  FLAT = "Interface/Buttons/WHITE8x8",
  STATUSBAR = "Interface/Buttons/WHITE8x8",
}
local FLAT = Theme.Textures.FLAT
Theme.Backdrop = {
  bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
  insets = {left = 1, right = 1, top = 1, bottom = 1},
}

Shared.THEME = {
  CREAMY_BROWN = C.GOLD_MUTED, GOLD = C.GOLD,
  CARD_BG = C.BROWN_DARK, PLAQUE_BG = C.BROWN_MED, EDGE = 4, WOOD = 0,
}
Shared.BACKDROP_BOARD = Theme.Backdrop
Shared.BACKDROP_NOTE = Theme.Backdrop

local function color(region, rgb, alpha)
  region:SetColorTexture(rgb[1], rgb[2], rgb[3], alpha or 1)
end

function Theme.ApplyNoteSkin(frame, alpha)
  frame:SetBackdrop(Theme.Backdrop)
  frame:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], alpha or 0.98)
  frame:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.65)
end

function Theme.ApplyBoardSkin(frame)
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

-- Fine corner accents replace thick wooden rails; no external art dependency.
function Theme.ApplyBoardRails(frame)
  if rawget(frame, "_goRails") then return end
  frame._goRails = true
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
  local line = plaque:CreateTexture(nil, "BACKGROUND")
  line:SetPoint("BOTTOMLEFT", 0, 0); line:SetPoint("BOTTOMRIGHT", 0, 0)
  line:SetHeight(1); color(line, C.GOLD, 0.32)
  return plaque
end

function Theme.MotionEnabled()
  local db = ns.GetDB and ns.GetDB()
  return not (type(db) == "table" and type(db.settings) == "table" and db.settings.reduceMotion)
end

local animations = setmetatable({}, {__mode = "k"})
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
  function control:Settle()
    local playing = group:IsPlaying()
    self:Stop()
    if playing and finish and (not allowed or allowed()) then finish() end
  end
  function control:Play()
    self:Stop()
    if allowed and not allowed() then return end
    if not Theme.MotionEnabled() then
      if finish then finish() end
      return
    end
    group:Play()
  end
  group:SetScript("OnFinished", function()
    if finish and (not allowed or allowed()) then finish() end
  end)
  animations[control] = true
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

function Theme.SetReducedMotion(reduced)
  local db = ns.GetDB and ns.GetDB()
  if type(db) ~= "table" then return end
  db.settings = type(db.settings) == "table" and db.settings or {}
  db.settings.reduceMotion = not not reduced
  if reduced then
    -- Finish pending closes through their normal guards; stop decorative work.
    for control in pairs(animations) do control:Settle() end
  end
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
    if previous ~= nil and value ~= previous and bar:IsVisible() and Theme.MotionEnabled() then
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
