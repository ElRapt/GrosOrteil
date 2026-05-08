---@diagnostic disable: undefined-global
local _, ns = ...

local _G = _G
local CreateFrame   = rawget(_G, "CreateFrame")
local UIParent      = rawget(_G, "UIParent")
local UnitName      = rawget(_G, "UnitName")
local UnitFullName  = rawget(_G, "UnitFullName")
local GetRealmName  = rawget(_G, "GetRealmName")
local C_Timer       = rawget(_G, "C_Timer")
local PlaySound     = rawget(_G, "PlaySound")
local PlaySoundFile = rawget(_G, "PlaySoundFile")

-- Default popup payload, used when a player entry leaves a field unset.
local DEFAULT_TITLE   = "|cFFD08CFF~ ALERTE GÉNÉRALE~|r"
local DEFAULT_TEXT    = "Personne ne te croira."
local DEFAULT_WHISPER = "|cFF8060A0— murmure dans l'ombre —|r"
local DEFAULT_BUTTON  = "Ok"

-- Players who get the fancy startup popup. Key = "Name-Realm" (no spaces in realm).
-- Value = table with optional fields { title, text, whisper, button }; missing
-- fields fall back to the defaults above. Add new entries by appending here.
local _gabrielConfig = {
  text    = "Personne ne te croira.",
  whisper = "|cFF8060A0— gabriel fdp —|r",
  button  = "Réel mdr",
}
local _tritanConfig = {
  text    = "En vrai j'aime bien ta guilde merci mec",
  whisper = "|cFF8060A0— pas de rand survie stp —|r",
  button  = "Je t'aime Lucas",
}
local _scotiConfig = {
  text    = "Por de ban ?!.",
  whisper = "|cFF8060A0— sudiste de merde —|r",
  button  = "Je mange le crumble",
}
local _kevinConfig = {
  text    = "romance gay Bébé Valère ?",
  whisper = "|cFF8060A0— t'as pas le choix —|r",
  button  = "J'adore la bromance",
}
local _simonConfig = {
  text    = "Simon, si tu vois ça, sache que je t'aime fort et que tu es un mec en or, un peu mon père spirituel du RP",
  whisper = "|cFF8060A0— wow > arc raiders —|r",
  button  = "Mdrrr fort",
}

local BONUS_PLAYERS = {
  ["Marev-KirinTor"]     = _scotiConfig,
  ["Priscïlla-KirinTor"] = _gabrielConfig,
  ["Assast-KirinTor"]    = _tritanConfig,
  ["Claîborne-KirinTor"]     = _scotiConfig,
  ["Johnny-KirinTor"]     = _kevinConfig,
  ["Camichat-KirinTor"]      = _simonConfig,
}

local function getPlayerFullName()
  local name, realm
  if UnitFullName then
    name, realm = UnitFullName("player")
  end
  if (not name) and UnitName then
    name = UnitName("player")
  end
  if (not realm or realm == "") and GetRealmName then
    realm = GetRealmName()
  end
  if type(name) ~= "string" or name == "" then return nil end
  if type(realm) == "string" and realm ~= "" then
    realm = realm:gsub("%s+", "")
    return name .. "-" .. realm
  end
  return name
end

local function getBonusConfig()
  local full = getPlayerFullName()
  if not full then return nil end
  return BONUS_PLAYERS[full]
end

local function resolveConfig(cfg)
  cfg = cfg or {}
  return {
    title   = cfg.title   or DEFAULT_TITLE,
    text    = cfg.text    or DEFAULT_TEXT,
    whisper = cfg.whisper or DEFAULT_WHISPER,
    button  = cfg.button  or DEFAULT_BUTTON,
  }
end

local frame

local function buildFrame(cfg)
  if frame then return frame end
  cfg = resolveConfig(cfg)

  frame = CreateFrame("Frame", "GrosOrteilMarevPopup", UIParent, "BackdropTemplate")
  frame:SetSize(560, 280)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  -- Dim backdrop overlay
  local dim = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
  dim:SetAllPoints(UIParent)
  dim:SetColorTexture(0, 0, 0, 0.55)
  frame.dim = dim

  -- Main parchment / arcane backdrop
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(frame)
  bg:SetColorTexture(0.04, 0.02, 0.10, 0.96)
  frame.bg = bg

  -- Vignette gradient (top dark -> bottom darker)
  local vignette = frame:CreateTexture(nil, "BORDER")
  vignette:SetAllPoints(frame)
  if vignette.SetGradient then
    local CreateColor = rawget(_G, "CreateColor")
    if CreateColor then
      vignette:SetColorTexture(1, 1, 1, 1)
      vignette:SetGradient("VERTICAL",
        CreateColor(0.20, 0.05, 0.40, 0.65),
        CreateColor(0.05, 0.00, 0.10, 0.95))
    end
  end

  -- Outer arcane border (animated)
  local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  border:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 6)
  border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -6)
  if border.SetBackdrop then
    border:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 22,
    })
    border:SetBackdropBorderColor(0.62, 0.20, 0.95, 1)
  end
  frame.border = border

  -- Glow texture behind everything (additive purple pulse)
  local glow = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
  glow:SetTexture("Interface\\Cooldown\\star4")
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(0.65, 0.25, 1.0, 0.6)
  glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -80, 80)
  glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 80, -80)
  frame.glow = glow

  local glowAG = glow:CreateAnimationGroup()
  glowAG:SetLooping("REPEAT")
  local pulseOut = glowAG:CreateAnimation("Alpha")
  pulseOut:SetFromAlpha(0.25); pulseOut:SetToAlpha(0.85)
  pulseOut:SetDuration(1.6); pulseOut:SetOrder(1); pulseOut:SetSmoothing("IN_OUT")
  local pulseIn = glowAG:CreateAnimation("Alpha")
  pulseIn:SetFromAlpha(0.85); pulseIn:SetToAlpha(0.25)
  pulseIn:SetDuration(1.6); pulseIn:SetOrder(2); pulseIn:SetSmoothing("IN_OUT")
  frame.glowAG = glowAG

  -- Slow rotation animation
  local rotAG = glow:CreateAnimationGroup()
  rotAG:SetLooping("REPEAT")
  local rot = rotAG:CreateAnimation("Rotation")
  rot:SetDegrees(360); rot:SetDuration(24); rot:SetOrder(1)
  frame.rotAG = rotAG

  -- Decorative top runes
  local runeL = frame:CreateTexture(nil, "ARTWORK")
  runeL:SetTexture("Interface\\TARGETINGFRAME\\PortraitQuestBadge")
  runeL:SetSize(48, 48)
  runeL:SetPoint("TOP", frame, "TOP", -110, 28)
  runeL:SetVertexColor(0.85, 0.55, 1.0, 1)
  runeL:SetBlendMode("ADD")

  local runeR = frame:CreateTexture(nil, "ARTWORK")
  runeR:SetTexture("Interface\\TARGETINGFRAME\\PortraitQuestBadge")
  runeR:SetSize(48, 48)
  runeR:SetPoint("TOP", frame, "TOP", 110, 28)
  runeR:SetVertexColor(0.85, 0.55, 1.0, 1)
  runeR:SetBlendMode("ADD")

  -- Title bar
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  title:SetPoint("TOP", frame, "TOP", 0, -22)
  title:SetText(cfg.title)
  if title.SetShadowColor then
    title:SetShadowColor(0.4, 0.0, 0.6, 0.9)
    title:SetShadowOffset(2, -2)
  end
  frame.title = title

  -- Decorative divider
  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
  divider:SetSize(420, 8)
  divider:SetPoint("TOP", title, "BOTTOM", 0, -6)
  divider:SetVertexColor(0.85, 0.55, 1.0, 1)

  -- Main message
  local msg = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  msg:SetPoint("CENTER", frame, "CENTER", 0, 8)
  msg:SetWidth(500)
  msg:SetJustifyH("CENTER")
  msg:SetText("")
  if msg.SetShadowColor then
    msg:SetShadowColor(0.0, 0.0, 0.0, 1.0)
    msg:SetShadowOffset(2, -2)
  end
  msg:SetTextColor(1.0, 0.95, 0.85, 1)
  frame.msg = msg

  -- Subtle whisper line under message
  local whisper = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  whisper:SetPoint("TOP", msg, "BOTTOM", 0, -16)
  whisper:SetText(cfg.whisper)
  frame.whisper = whisper

  -- OK button (custom styled)
  local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  btn:SetSize(140, 32)
  btn:SetPoint("BOTTOM", frame, "BOTTOM", -90, 22)
  btn:SetText(cfg.button)
  if btn.SetNormalFontObject then
    btn:SetNormalFontObject("GameFontNormalLarge")
    btn:SetHighlightFontObject("GameFontHighlightLarge")
  end
  frame.btn = btn

  -- Button glow
  local btnGlow = btn:CreateTexture(nil, "BACKGROUND")
  btnGlow:SetTexture("Interface\\Cooldown\\star4")
  btnGlow:SetBlendMode("ADD")
  btnGlow:SetVertexColor(0.7, 0.3, 1.0, 0.7)
  btnGlow:SetPoint("TOPLEFT", btn, "TOPLEFT", -20, 10)
  btnGlow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 20, -10)
  local btnAG = btnGlow:CreateAnimationGroup()
  btnAG:SetLooping("REPEAT")
  local bIn = btnAG:CreateAnimation("Alpha")
  bIn:SetFromAlpha(0.2); bIn:SetToAlpha(0.9); bIn:SetDuration(1.0); bIn:SetOrder(1); bIn:SetSmoothing("IN_OUT")
  local bOut = btnAG:CreateAnimation("Alpha")
  bOut:SetFromAlpha(0.9); bOut:SetToAlpha(0.2); bOut:SetDuration(1.0); bOut:SetOrder(2); bOut:SetSmoothing("IN_OUT")
  frame.btnAG = btnAG

  -- "Leave me alone" button — sets the persistent suppression flag
  local muteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  muteBtn:SetSize(220, 32)
  muteBtn:SetPoint("BOTTOM", frame, "BOTTOM", 90, 22)
  muteBtn:SetText("Laisse moi tranquille wsh")
  if muteBtn.SetNormalFontObject then
    muteBtn:SetNormalFontObject("GameFontNormal")
    muteBtn:SetHighlightFontObject("GameFontHighlight")
  end
  frame.muteBtn = muteBtn

  -- Sparkle particles (six floating motes)
  frame.sparkles = {}
  for i = 1, 8 do
    local s = frame:CreateTexture(nil, "OVERLAY")
    s:SetTexture("Interface\\Cooldown\\star4")
    s:SetBlendMode("ADD")
    s:SetSize(20, 20)
    s:SetVertexColor(1.0, 0.85, 1.0, 0.9)
    local x = math.random(-220, 220)
    local y = math.random(-90, 90)
    s:SetPoint("CENTER", frame, "CENTER", x, y)

    local ag = s:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local up = ag:CreateAnimation("Translation")
    up:SetOffset(math.random(-30, 30), math.random(40, 90))
    up:SetDuration(math.random(20, 40) / 10)
    up:SetOrder(1)
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(0.9); fadeOut:SetToAlpha(0.0)
    fadeOut:SetDuration(math.random(20, 40) / 10); fadeOut:SetOrder(1)
    local down = ag:CreateAnimation("Translation")
    down:SetOffset(math.random(-30, 30), -math.random(40, 90))
    down:SetDuration(0.001); down:SetOrder(2)
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.0); fadeIn:SetToAlpha(0.9)
    fadeIn:SetDuration(0.001); fadeIn:SetOrder(2)
    frame.sparkles[i] = { tex = s, ag = ag }
  end

  -- Show/hide animation (fade + scale)
  frame:SetAlpha(0)
  frame:SetScale(0.85)
  local showAG = frame:CreateAnimationGroup()
  local fade = showAG:CreateAnimation("Alpha")
  fade:SetFromAlpha(0); fade:SetToAlpha(1); fade:SetDuration(0.6); fade:SetSmoothing("OUT")
  local scale = showAG:CreateAnimation("Scale")
  if scale.SetFromScale and scale.SetToScale then
    scale:SetFromScale(0.85, 0.85)
    scale:SetToScale(1.0, 1.0)
  elseif scale.SetScale then
    scale:SetScale(1.18, 1.18)
  end
  scale:SetDuration(0.6); scale:SetSmoothing("OUT")
  showAG:SetScript("OnFinished", function()
    frame:SetAlpha(1)
    frame:SetScale(1)
  end)
  frame.showAG = showAG

  -- Typewriter effect
  local function typeWriter(target, fullText, perChar)
    target:SetText("")
    local i = 0
    local function step()
      i = i + 1
      target:SetText(fullText:sub(1, i))
      if i < #fullText and C_Timer then
        C_Timer.After(perChar, step)
      end
    end
    step()
  end
  frame.typeWriter = typeWriter

  -- Close handler
  local function closePopup()
    if frame.glowAG and frame.glowAG.Stop then frame.glowAG:Stop() end
    if frame.rotAG  and frame.rotAG.Stop  then frame.rotAG:Stop()  end
    if frame.btnAG  and frame.btnAG.Stop  then frame.btnAG:Stop()  end
    for _, s in ipairs(frame.sparkles or {}) do
      if s.ag and s.ag.Stop then s.ag:Stop() end
    end
    if PlaySound then pcall(PlaySound, 624) end -- igMainMenuClose
    frame:Hide()
  end
  btn:SetScript("OnClick", closePopup)
  frame.Close = closePopup

  muteBtn:SetScript("OnClick", function()
    local db = ns.GetDB and ns.GetDB() or nil
    if type(db) == "table" then
      db.bonus = db.bonus or {}
      db.bonus.suppressed = true
    end
    closePopup()
  end)

  return frame
end

local function showPopup(cfg)
  cfg = resolveConfig(cfg)
  local f = buildFrame(cfg)

  f:Show()
  f:SetAlpha(0)
  if f.showAG and f.showAG.Play then f.showAG:Play() end
  if f.glowAG and f.glowAG.Play then f.glowAG:Play() end
  if f.rotAG  and f.rotAG.Play  then f.rotAG:Play()  end
  if f.btnAG  and f.btnAG.Play  then f.btnAG:Play()  end
  for _, s in ipairs(f.sparkles or {}) do
    if s.ag and s.ag.Play then s.ag:Play() end
  end

  -- Mystical sound: arcane portal shimmer (fallback to simple sound)
  if PlaySound then
    pcall(PlaySound, 73277) -- UI_LegendaryLoot_Toast
  end

  -- Typewriter the main message after fade-in
  if C_Timer and f.typeWriter then
    C_Timer.After(0.45, function()
      f.typeWriter(f.msg, cfg.text, 0.06)
    end)
  else
    f.msg:SetText(cfg.text)
  end
end

local function isSuppressed()
  local db = ns.GetDB and ns.GetDB() or nil
  return type(db) == "table" and type(db.bonus) == "table" and db.bonus.suppressed == true
end

function ns.Bonus_Init()
  local cfg = getBonusConfig()
  if not cfg then return end
  if isSuppressed() then return end
  if C_Timer then
    C_Timer.After(2.5, function() showPopup(cfg) end)
  else
    showPopup(cfg)
  end
end

-- Re-enable the popup for the current character (for testing or unmuting).
function ns.Bonus_Reset()
  local db = ns.GetDB and ns.GetDB() or nil
  if type(db) == "table" and type(db.bonus) == "table" then
    db.bonus.suppressed = nil
  end
end

-- Debug helper: force show regardless of identity (useful for testing).
-- Pass an optional config override; otherwise the current player's entry
-- (or pure defaults) is used.
function ns.Bonus_ForceShow(cfg)
  showPopup(cfg or getBonusConfig())
end
