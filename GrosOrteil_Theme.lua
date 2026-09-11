---@diagnostic disable: undefined-global
-- Addon-owned presentation only. No Blizzard globals, secure handlers or game
-- state are replaced here. Every window uses this palette and animation lifecycle.
local _, ns = ...
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
local TOOLTIP_BORDER = "Interface/Tooltips/UI-Tooltip-Border"
local LEGACY_SURFACES = {
  CREAMY_BROWN = {0.48, 0.39, 0.32},
  CARD_BG = {0.085, 0.065, 0.045}, PLAQUE_BG = {0.10, 0.075, 0.05},
  EDGE = 4, WOOD = 20,
}
local TRP3_BG = "Interface/AddOns/totalRP3/Resources/UI/ui-frame-neutral-background"
local TRP3_WOOD_V = "Interface/AddOns/totalRP3/Resources/UI/!ui-frame-wooden-border"
local TRP3_WOOD_H = "Interface/AddOns/totalRP3/Resources/UI/_ui-frame-wooden-border"
local BLIZZ_BG = "Interface/FrameGeneral/UIFrameNeutralBackground"

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
local DEFAULTS = {
  slate = { border = "flat", borderSize = 1, background = "gradient", opacity = 98,
    decorations = true, bars = "flat" },
  legacy = { border = "tooltip", borderSize = 12, background = "textured", opacity = 100,
    decorations = true, bars = "classic" },
}
-- Color recipes use the same three overrides as the individual pickers.
-- The selected recipe is derived from those colors, never saved separately.
Theme.ColorPresets = {
  {label = "Noir & blanc", colors = {accentColor = "F5F5F5", backgroundColor = "101010", borderColor = "A3A3A3"}},
  {label = "Bleu nuit & or", colors = {accentColor = "E4BF72", backgroundColor = "101A2D", borderColor = "8F7545"}},
  {label = "Forêt & ivoire", colors = {accentColor = "ECE5CE", backgroundColor = "142B24", borderColor = "719780"}},
  {label = "Prune & rose", colors = {accentColor = "EDB5CF", backgroundColor = "2B192D", borderColor = "986A91"}},
  {label = "Océan", colors = {accentColor = "79D9D0", backgroundColor = "102830", borderColor = "3B8695"}},
  {label = "Charbon & cuivre", colors = {accentColor = "E2AA83", backgroundColor = "202124", borderColor = "A66F50"}},
}
function Theme.ColorHex(r, g, b)
  return string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
for name, defaults in pairs(DEFAULTS) do
  local accent, background = PALETTES[name].GOLD, PALETTES[name].BG_PANEL
  local border = name == "legacy" and LEGACY_SURFACES.CREAMY_BROWN or PALETTES[name].GOLD_MUTED
  defaults.accentColor = Theme.ColorHex(accent[1], accent[2], accent[3])
  defaults.backgroundColor = Theme.ColorHex(background[1], background[2], background[3])
  defaults.borderColor = Theme.ColorHex(border[1], border[2], border[3])
end
local CHOICES = { border = {flat = true, tooltip = true, none = true},
  background = {flat = true, gradient = true, textured = true}, bars = {flat = true, classic = true} }
local style = {}
-- Only addon-owned presentation is tracked. Stable RGB references let static
-- labels and current selected/focused colors update without rebuilding frames.
local colors = setmetatable({}, {__mode = "k"})
local surfaces = setmetatable({}, {__mode = "k"})
local pending = false
local apply

local function validOption(key, value)
  if CHOICES[key] then return CHOICES[key][value] and value or nil end
  if key == "decorations" and type(value) == "boolean" then return value end
  if key == "opacity" or key == "borderSize" then
    local low, high = key == "opacity" and 0 or 1, key == "opacity" and 100 or 16
    if type(value) == "number" and value >= low and value <= high and value == math.floor(value) then return value end
  elseif key == "accentColor" or key == "backgroundColor" or key == "borderColor" then
    if type(value) == "string" and value:match("^%x%x%x%x%x%x$") then return value:upper() end
  end
end

local function options(name)
  local db = ns.GetDB and ns.GetDB()
  local settings = type(db) == "table" and db.settings
  local all = type(settings) == "table" and settings.themeOptions
  return type(all) == "table" and type(all[name]) == "table" and all[name] or {}
end

function Theme.GetOption(key)
  local name = Theme.GetSelectedName()
  local value = validOption(key, options(name)[key])
  -- The second result distinguishes an override from an unmodified preset.
  if value ~= nil then return value, true end
  return DEFAULTS[name][key], false
end

function Theme.ColorRGB(hex)
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function Theme.BindColor(region, method, rgb, alpha)
  local entry = colors[region]
  if not entry then entry = {}; colors[region] = entry end
  local value = entry[method]
  if not value then value = {}; entry[method] = value end
  value.rgb, value.alpha = rgb, alpha
  region[method](region, rgb[1], rgb[2], rgb[3], alpha or rgb[4] or 1)
end

function Theme.BindBackdrop(frame)
  surfaces[frame] = "backdrop"
  frame:SetBackdrop(Theme.Backdrop)
end

function Theme.StyleBar(bar)
  surfaces[bar] = "bar"
  bar:SetStatusBarTexture(Theme.Textures.STATUSBAR)
end

local function applyPalette(name)
  activeName = name
  local legacy = name == "legacy"
  local overrides = options(name)
  for key, default in pairs(DEFAULTS[name]) do
    local value = validOption(key, overrides[key])
    style[key] = value == nil and default or value
  end
  for key, rgb in pairs(PALETTES[name]) do
    C[key] = C[key] or {}; copyInto(C[key], rgb)
  end
  -- These surface colors used to be private to the Legacy skin.
  C.NOTE_BG = C.NOTE_BG or {}; C.BORDER = C.BORDER or {}; C.PLAQUE_BG = C.PLAQUE_BG or {}
  copyInto(C.NOTE_BG, legacy and LEGACY_SURFACES.CARD_BG or C.BROWN_DARK)
  copyInto(C.BORDER, legacy and LEGACY_SURFACES.CREAMY_BROWN or C.GOLD_MUTED)
  copyInto(C.PLAQUE_BG, legacy and LEGACY_SURFACES.PLAQUE_BG or C.BROWN_DARK)
  C.NOTE_BG[4], C.BORDER[4] = legacy and 0.92 or 0.98, legacy and 0.90 or 0.65
  local function tint(key, hex, shade, light)
    local r, g, b = Theme.ColorRGB(hex)
    local rgb = C[key]
    for i, v in ipairs({r, g, b}) do rgb[i] = v * shade + (1 - v) * (light or 0) end
  end
  if validOption("accentColor", overrides.accentColor) then
    for _, key in ipairs({"GOLD", "GOLD_BRIGHT", "GOLD_LIGHT", "GOLD_DIM", "TEXT_TITLE"}) do
      tint(key, style.accentColor, 1, key == "GOLD" and 0 or key == "GOLD_LIGHT" and 0.45 or 0.22)
    end
  end
  if validOption("backgroundColor", overrides.backgroundColor) then
    tint("BG_PANEL", style.backgroundColor, 1)
    for _, key in ipairs({"BROWN_DEEP", "BROWN_DARK", "BROWN_MED", "BROWN_WARM", "NOTE_BG", "PLAQUE_BG"}) do
      tint(key, style.backgroundColor, 1, key == "BROWN_MED" and 0.12 or key == "BROWN_WARM" and 0.18 or 0.03)
    end
  end
  if validOption("borderColor", overrides.borderColor) then
    tint("GOLD_MUTED", style.borderColor, 1); tint("BORDER", style.borderColor, 1)
  end
  style.textureTint = validOption("backgroundColor", overrides.backgroundColor) and C.BG_PANEL or {0.60, 0.60, 0.60}
  -- Blizzard's SetBackdrop skips the same table identity. A fresh description
  -- is required when the border style/size changes; RGB tables remain stable.
  local inset = style.border == "none" and 0 or style.border == "tooltip" and 3 or style.borderSize
  local edge = style.border == "flat" and FLAT or style.border == "tooltip" and TOOLTIP_BORDER or nil
  if not Theme.Backdrop or Theme.Backdrop.edgeFile ~= edge or Theme.Backdrop.edgeSize ~= style.borderSize then
    Theme.Backdrop = {bgFile = FLAT, edgeFile = edge, edgeSize = style.borderSize,
      insets = {left = inset, right = inset, top = inset, bottom = inset}}
  end
  Theme.Textures.STATUSBAR = style.bars == "classic" and "Interface/TargetingFrame/UI-StatusBar" or FLAT
end
applyPalette("slate")

function Theme.GetName() return activeName end

function Theme.GetSelectedName()
  local db = ns.GetDB and ns.GetDB()
  local settings = type(db) == "table" and db.settings
  return type(settings) == "table" and settings.theme == "legacy" and "legacy" or "slate"
end

function Theme.SetName(name)
  if type(name) ~= "string" or not PALETTES[name] then return false end
  local db = ns.GetDB and ns.GetDB()
  if type(db) ~= "table" then return false end
  if type(db.settings) ~= "table" then db.settings = {} end
  if db.settings.theme == name then return true end
  db.settings.theme = name
  apply()
  return true
end

function Theme.SetOptions(values)
  if type(values) ~= "table" then return false end
  local changed = {}
  for key, value in pairs(values) do
    value = validOption(key, value)
    if value == nil then return false end
    if Theme.GetOption(key) ~= value then changed[key] = value end
  end
  local db = ns.GetDB and ns.GetDB()
  if type(db) ~= "table" then return false end
  if not next(changed) then return true end
  if type(db.settings) ~= "table" then db.settings = {} end
  if type(db.settings.themeOptions) ~= "table" then db.settings.themeOptions = {} end
  local name = Theme.GetSelectedName()
  if type(db.settings.themeOptions[name]) ~= "table" then db.settings.themeOptions[name] = {} end
  for key, value in pairs(changed) do db.settings.themeOptions[name][key] = value end
  apply()
  return true
end

function Theme.SetOption(key, value)
  if key == nil or value == nil then return false end
  return Theme.SetOptions({[key] = value})
end

function Theme.ResetOptions(key)
  local db = ns.GetDB and ns.GetDB()
  local all = db and db.settings and db.settings.themeOptions
  if type(all) ~= "table" or all[Theme.GetSelectedName()] == nil then return end
  if key ~= nil then
    local selected = all[Theme.GetSelectedName()]
    if type(selected) ~= "table" or selected[key] == nil then return end
    selected[key] = nil
  else
    all[Theme.GetSelectedName()] = nil
  end
  apply()
end

function Theme.IsPending() return pending end

-- Called after SavedVariables load, before any UI is built.
function Theme.Initialize()
  if initialized then return end
  local name = Theme.GetSelectedName()
  local db = ns.GetDB and ns.GetDB()
  if type(db) == "table" then
    if type(db.settings) ~= "table" then db.settings = {} end
    db.settings.theme, db.settings.reduceMotion = name, nil
  end
  applyPalette(name)
  initialized = true
end

local function color(region, rgb, alpha)
  Theme.BindColor(region, "SetColorTexture", rgb, alpha)
end

local function noteColors(frame, alpha)
  Theme.BindColor(frame, "SetBackdropColor", C.NOTE_BG, alpha)
  Theme.BindColor(frame, "SetBackdropBorderColor", C.BORDER)
end

function Theme.ApplyNoteSkin(frame, alpha)
  Theme.BindBackdrop(frame)
  noteColors(frame, alpha)
end

function Theme.ApplyBoardSkin(frame)
  surfaces[frame] = "board"
  local bg = rawget(frame, "_goBoard")
  if not bg then
    bg = frame:CreateTexture(nil, "BACKGROUND")
    frame._goBoard = bg
    local wash = frame:CreateTexture(nil, "BORDER")
    wash:SetPoint("TOPLEFT", 2, -2); wash:SetPoint("TOPRIGHT", -2, -2)
    wash:SetHeight(130)
    frame._goWash = wash
  end
  -- Use a single background layer so opacity remains meaningful.
  frame:SetBackdrop({edgeFile = Theme.Backdrop.edgeFile, edgeSize = Theme.Backdrop.edgeSize})
  frame:SetBackdropBorderColor(C.BORDER[1], C.BORDER[2], C.BORDER[3], 1)
  local inset = style.border == "none" and 0 or style.border == "tooltip" and 4 or style.borderSize
  bg:ClearAllPoints()
  bg:SetPoint("TOPLEFT", inset, -inset); bg:SetPoint("BOTTOMRIGHT", -inset, inset)
  local opacity = style.opacity / 100
  if style.background == "textured" then
    bg:SetTexture(rawget(_G, "TRP3_API") and TRP3_BG or BLIZZ_BG, "REPEAT", "REPEAT")
    bg:SetHorizTile(true); bg:SetVertTile(true)
    local tint = style.textureTint
    bg:SetVertexColor(tint[1], tint[2], tint[3], opacity)
  else
    bg:SetTexture(FLAT); bg:SetHorizTile(false); bg:SetVertTile(false)
    bg:SetVertexColor(C.BG_PANEL[1], C.BG_PANEL[2], C.BG_PANEL[3], opacity)
  end
  local wash = frame._goWash
  wash:SetTexture(FLAT)
  wash:SetGradient("VERTICAL", CreateColor(C.BROWN_MED[1], C.BROWN_MED[2], C.BROWN_MED[3], 0),
    CreateColor(C.BROWN_MED[1], C.BROWN_MED[2], C.BROWN_MED[3], opacity * 0.60))
  wash:SetShown(style.background == "gradient")
  return bg
end

local function applyLegacyRails(frame)
  frame._goLegacyRails = {}
  local function texture(layer)
    local t = frame:CreateTexture(nil, "BORDER", nil, layer)
    table.insert(frame._goLegacyRails, t)
    return t
  end
  local EDGE, WOOD = LEGACY_SURFACES.EDGE, LEGACY_SURFACES.WOOD
  if rawget(_G, "TRP3_API") then
    local function woodV(point, x, flip)
      local t = texture(-3)
      t:SetTexture(TRP3_WOOD_V, "REPEAT", "REPEAT"); t:SetVertTile(true)
      t:SetWidth(WOOD)
      t:SetPoint("TOP" .. point, frame, "TOP" .. point, x, -EDGE)
      t:SetPoint("BOTTOM" .. point, frame, "BOTTOM" .. point, x, EDGE)
      if flip then t:SetTexCoord(0.2265625, 0.0078125, 0, 1)
      else t:SetTexCoord(0.0078125, 0.2265625, 0, 1) end
      t:SetVertexColor(1, 0.8, 0.8)
    end
    local function woodH(point, y, top, bottom)
      local t = texture(-2)
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
      local t = texture(-2)
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
  frame._goRails = true
  if not rawget(frame, "_goLegacyRails") then applyLegacyRails(frame) end
  if not rawget(frame, "_goSlateRails") then
    frame._goSlateRails = {}
    for _, corner in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
      local left = corner:find("LEFT", 1, true)
      local top = corner:find("TOP", 1, true)
      local x, y = left and 1 or -1, top and -1 or 1
      local h = frame:CreateTexture(nil, "BORDER")
      h:SetSize(24, 2); h:SetPoint(corner, frame, corner, x, y); color(h, C.GOLD, 0.70)
      local v = frame:CreateTexture(nil, "BORDER")
      v:SetSize(2, 18); v:SetPoint(corner, frame, corner, x, y); color(v, C.GOLD, 0.70)
      table.insert(frame._goSlateRails, h); table.insert(frame._goSlateRails, v)
    end
  end
  for _, t in ipairs(frame._goLegacyRails) do t:SetShown(style.decorations and activeName == "legacy") end
  for _, t in ipairs(frame._goSlateRails) do t:SetShown(style.decorations and activeName == "slate") end
end

local function plaqueSkin(plaque)
  if activeName == "legacy" then
    plaque:SetBackdrop(Theme.Backdrop)
    plaque:SetBackdropColor(C.PLAQUE_BG[1], C.PLAQUE_BG[2], C.PLAQUE_BG[3], 0.97)
    plaque:SetBackdropBorderColor(C.BORDER[1], C.BORDER[2], C.BORDER[3], 1)
  else
    plaque:SetBackdrop(nil)
  end
  plaque._goLine:SetShown(activeName == "slate" and style.decorations)
end

function Theme.MakePlaque(frame, height)
  local plaque = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  plaque:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -10)
  plaque:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -10)
  plaque:SetHeight(height or 38)
  local line = plaque:CreateTexture(nil, "BACKGROUND")
  line:SetPoint("BOTTOMLEFT", 0, 0); line:SetPoint("BOTTOMRIGHT", 0, 0)
  line:SetHeight(1); color(line, C.GOLD, 0.32)
  plaque._goLine = line
  surfaces[plaque] = "plaque"
  plaqueSkin(plaque)
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

local function buttonColors(button)
  local role, selection = button._goRole, rawget(button, "_goSelection")
  local enabled = button:IsEnabled()
  local label = rawget(button, "_fs") or rawget(button, "_text")
  local rgb = role == "danger" and C.DANGER or role == "primary" and C.SUCCESS or C.TEXT_NORMAL
  local text = enabled and rgb or C.TEXT_DISABLED
  if label then Theme.BindColor(label, "SetTextColor", text, 1) end
  if selection then
    Theme.BindColor(button, "SetBackdropColor", {selection.r * 0.35, selection.g * 0.35, selection.b * 0.35}, 0.95)
    Theme.BindColor(button, "SetBackdropBorderColor", {selection.r, selection.g, selection.b}, 1)
  elseif selection == false then
    Theme.BindColor(button, "SetBackdropColor", C.BROWN_DARK, 0.90)
    Theme.BindColor(button, "SetBackdropBorderColor", C.GOLD_MUTED, 0.80)
  elseif not enabled then
    Theme.BindColor(button, "SetBackdropColor", C.BROWN_DEEP, 0.65)
    Theme.BindColor(button, "SetBackdropBorderColor", C.GOLD_MUTED, 0.35)
  else
    noteColors(button)
    if role then Theme.BindColor(button, "SetBackdropBorderColor", rgb, 0.65) end
  end
end

function Theme.StyleButton(button, role)
  button._goRole = role
  if not rawget(button, "_goStyled") then
    button._goStyled = true
    Theme.BindBackdrop(button)
    local enable, disable = button.Enable, button.Disable
    function button:Enable()
      if self:IsEnabled() then return end
      enable(self); buttonColors(self)
    end
    function button:Disable()
      if not self:IsEnabled() then return end
      disable(self)
      if self._goHover then self._goHover:Hide() end
      buttonColors(self)
    end
    Theme.AddHover(button)
  end
  buttonColors(button)
end

-- Affixes and postures share the same selected tint, including when disabled.
function Theme.SetButtonSelected(button, tint)
  if rawget(button, "_goSelection") == tint then return end
  button._goSelection = tint
  buttonColors(button)
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
  Theme.BindColor(label, "SetTextColor", C.TEXT_TITLE, 1)
  label:SetText(text)
  return label
end

function Theme.StyleClose(button)
  if rawget(button, "_goClose") then return end
  for _, getter in ipairs({
    "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture",
  }) do
    local texture = button[getter](button)
    if texture then texture:Hide() end
  end
  local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  button._goClose = label
  label:SetPoint("CENTER", 0, 0); label:SetText("×")
  Theme.BindColor(label, "SetTextColor", C.TEXT_LABEL, 1)
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

-- Restyling never runs from a timer or a game-state refresh. Combat queues only
-- the saved choice; the existing frames are updated once combat has ended.
local events = CreateFrame("Frame")
apply = function()
  if InCombatLockdown() then
    pending = true
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    if ns.UI and ns.UI.RefreshThemes then ns.UI.RefreshThemes() end
    return
  end
  pending = false
  events:UnregisterEvent("PLAYER_REGEN_ENABLED")
  applyPalette(Theme.GetSelectedName())
  for frame, skin in pairs(surfaces) do
    if skin == "board" then
      Theme.ApplyBoardSkin(frame)
      if rawget(frame, "_goRails") then Theme.ApplyBoardRails(frame) end
    elseif skin == "plaque" then plaqueSkin(frame)
    elseif skin == "bar" then frame:SetStatusBarTexture(Theme.Textures.STATUSBAR)
    else frame:SetBackdrop(Theme.Backdrop) end
  end
  for region, entry in pairs(colors) do
    for method, value in pairs(entry) do
      local rgb = value.rgb
      region[method](region, rgb[1], rgb[2], rgb[3], value.alpha or rgb[4] or 1)
    end
  end
  if ns.UI and ns.UI.RefreshThemes then ns.UI.RefreshThemes() end
end
events:SetScript("OnEvent", function() apply() end)
