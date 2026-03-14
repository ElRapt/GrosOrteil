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
local UnitGUID = rawget(_G, "UnitGUID")
local CreateFrame = rawget(_G, "CreateFrame")
local UIParent = rawget(_G, "UIParent")
local C_Timer = rawget(_G, "C_Timer")
local LibRPNames = rawget(_G, "LibRPNames")

local pendingTarget
local popupFrame

local CLASS_STYLES = {
  MEDIC = { label = "Fournitures", r = 0.85, g = 0.12, b = 0.12 },
  PALADIN = { label = "Puissance sacree", r = 1.0, g = 0.82, b = 0.22 },
  PRIEST = { label = "Puissance sacree", r = 1.0, g = 0.82, b = 0.22 },
  SHADOWPRIEST = { label = "Points de foi et insanite", r = 0.60, g = 0.20, b = 0.85 },
  MAGE = { label = "Mana", r = 0.20, g = 0.55, b = 1.00 },
  ROGUE = { label = "Energie", r = 1.00, g = 0.90, b = 0.10 },
  WARLOCK = { label = "Energie gangrenee et Corruption", r = 0.20, g = 0.85, b = 0.25 },
  DRUID = { label = "Esprit", r = 1.00, g = 0.55, b = 0.10 },
  MONK = { label = "Chi", r = 0.55, g = 1.00, b = 0.55 },
  SHAMAN = { label = "Points elementaires", r = 0.00, g = 0.44, b = 0.87 },
}

local RES_PROFILES_BY_CLASS = {
  WARRIOR = {},
  MEDIC = {
    { idx = 1, label = "Fournitures", r = 0.85, g = 0.12, b = 0.12 },
  },
  WARLOCK = {
    { idx = 1, label = "Energie gangrenee", r = 0.20, g = 0.85, b = 0.25 },
    { idx = 2, label = "Corruption", r = 0.55, g = 0.20, b = 0.85 },
  },
  SHADOWPRIEST = {
    { idx = 1, label = "Points de foi", r = 1.0, g = 1.0, b = 1.0 },
    { idx = 2, label = "Insanite", r = 0.60, g = 0.20, b = 0.85 },
  },
  SHAMAN = {
    { idx = 1, label = "Terre", r = 0.55, g = 0.35, b = 0.15 },
    { idx = 2, label = "Air", r = 0.60, g = 0.95, b = 0.95 },
    { idx = 3, label = "Eau", r = 0.20, g = 0.55, b = 1.00 },
    { idx = 4, label = "Feu", r = 1.00, g = 0.35, b = 0.10 },
  },
}

local CLASS_NAMES_FR = {
  WARRIOR = "Guerrier",
  MAGE = "Mage",
  ROGUE = "Voleur",
  DRUID = "Druide",
  HUNTER = "Chasseur",
  SHAMAN = "Chaman",
  PRIEST = "Pretre",
  WARLOCK = "Demoniste",
  PALADIN = "Paladin",
  DEATHKNIGHT = "Chevalier de la mort",
  MONK = "Moine",
  DEMONHUNTER = "Chasseur de demons",
  EVOKER = "Evocateur",
  MEDIC = "Médecin",
  SHADOWPRIEST = "Prêtre ombre",
}

local CLASS_ICON_COORDS = {
  WARRIOR = { 0, 0.25, 0, 0.25 },
  MAGE = { 0.25, 0.50, 0, 0.25 },
  ROGUE = { 0.50, 0.75, 0, 0.25 },
  DRUID = { 0.75, 1.00, 0, 0.25 },
  HUNTER = { 0, 0.25, 0.25, 0.50 },
  SHAMAN = { 0.25, 0.50, 0.25, 0.50 },
  PRIEST = { 0.50, 0.75, 0.25, 0.50 },
  WARLOCK = { 0.75, 1.00, 0.25, 0.50 },
  PALADIN = { 0, 0.25, 0.50, 0.75 },
  DEATHKNIGHT = { 0.25, 0.50, 0.50, 0.75 },
  MONK = { 0.50, 0.75, 0.50, 0.75 },
  DEMONHUNTER = { 0.75, 1.00, 0.50, 0.75 },
  EVOKER = { 0, 0.25, 0.75, 1.00 },
}

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
  if not aRealm or not bRealm then return true end
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

local function baseCharacterName(name)
  if type(name) ~= "string" or name == "" then return "Inconnu" end
  return name:match("^[^-]+") or name
end

local function getClassNameFr(classKey)
  local key = type(classKey) == "string" and classKey or ""
  local name = CLASS_NAMES_FR[key]
  if name then
    return name
  end
  if key ~= "" then
    return key
  end
  return "Inconnue"
end

local function getResProfile(classKey)
  local p = (type(classKey) == "string") and RES_PROFILES_BY_CLASS[classKey] or nil
  if p then return p end
  local s = (type(classKey) == "string" and CLASS_STYLES[classKey]) or nil
  if s then
    return { { idx = 1, label = s.label or "Ressource", r = s.r or 0.2, g = s.g or 0.55, b = s.b or 1.0 } }
  end
  return { { idx = 1, label = "Ressource", r = 0.20, g = 0.55, b = 1.00 } }
end

local function getKeysForIdx(i)
  if i == 1 then return "res", "maxRes" end
  if i == 2 then return "res2", "maxRes2" end
  if i == 3 then return "res3", "maxRes3" end
  if i == 4 then return "res4", "maxRes4" end
  return nil, nil
end

local function makeMarker(bar, pct, r, g, b, a, w)
  local t = bar:CreateTexture(nil, "OVERLAY")
  t:SetTexture("Interface/Buttons/WHITE8x8")
  t:SetWidth(w or 2)
  t:SetHeight(bar:GetHeight() or 14)
  t:SetColorTexture(r or 1, g or 1, b or 1, a or 0.45)
  t.pct = pct or 0
  t:Hide()
  return t
end

local function hideMarkers(markers)
  if not markers then return end
  for i = 1, #markers do
    if markers[i] then
      markers[i]:Hide()
    end
  end
end

local function positionMarkers(markers, bar)
  if not markers or not bar or not bar.GetWidth then return end
  local wBar = bar:GetWidth() or 0
  if wBar <= 0 then return end
  for i = 1, #markers do
    local m = markers[i]
    if m then
      local x = wBar * (m.pct or 0)
      if x < 0 then x = 0 elseif x > wBar then x = wBar end
      m:Show()
      m:ClearAllPoints()
      m:SetPoint("LEFT", bar, "LEFT", x, 0)
    end
  end
end

local function getRPDisplayName(playerName)
  local guid
  local targetName = unitTargetName("target")
  if targetName and namesMatch(targetName, playerName) and UnitGUID then
    guid = UnitGUID("target")
  end

  if LibRPNames and LibRPNames.Get then
    local fullName, _, _, color = LibRPNames.Get(playerName, guid)
    if type(fullName) == "string" and fullName ~= "" then
      return fullName, color
    end
  end

  return baseCharacterName(playerName), nil
end

local function hidePopup()
  if popupFrame then
    popupFrame:Hide()
  end
end

local function createStatBar(parent, yOffset)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(304, 34)
  holder:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, yOffset)

  local topText = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  topText:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  topText:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
  topText:SetJustifyH("LEFT")
  topText:SetText("")

  local barFrame = CreateFrame("Frame", nil, holder, "BackdropTemplate")
  barFrame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -14)
  barFrame:SetSize(304, 20)

  barFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  barFrame:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
  barFrame:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.90)

  local bar = CreateFrame("StatusBar", nil, barFrame)
  bar:SetAllPoints(barFrame)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(0)

  local sheen = bar:CreateTexture(nil, "OVERLAY")
  sheen:SetTexture("Interface\\Buttons\\WHITE8x8")
  sheen:SetVertexColor(1, 1, 1, 0.10)
  sheen:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  sheen:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  sheen:SetHeight(10)

  return {
    holder = holder,
    topText = topText,
    frame = barFrame,
    bar = bar,
    markers = {},
  }
end

local function hideOverlay(tex)
  if not tex then return end
  tex:Hide()
  tex:SetAlpha(0)
  tex:SetWidth(0.001)
end

local function updateHpShieldOverlays(row, hpNow, maxHp, blockValue, magicValue)
  if not row or not row.bar then return end
  local bar = row.bar
  local wBar = bar:GetWidth() or 0
  local hpForOverlay = math.max(0, hpNow or 0)
  local block = math.max(0, blockValue or 0)
  local magic = math.max(0, magicValue or 0)
  local total = math.min(hpForOverlay, block + magic)

  if maxHp <= 0 or wBar <= 0 or total <= 0 then
    hideOverlay(row.blockOverlay)
    hideOverlay(row.magicOverlay)
    return
  end

  local hpFrac = hpForOverlay / maxHp
  if hpFrac < 0 then hpFrac = 0 elseif hpFrac > 1 then hpFrac = 1 end
  local endX = wBar * hpFrac

  local magicShown = math.min(magic, total)
  local blockShown = math.min(block, total - magicShown)

  local magicW = wBar * (magicShown / maxHp)
  local blockW = wBar * (blockShown / maxHp)

  if row.magicOverlay and magicW > 0.5 and endX > 0.5 then
    row.magicOverlay:Show()
    row.magicOverlay:SetAlpha(0.75)
    row.magicOverlay:ClearAllPoints()
    row.magicOverlay:SetPoint("TOPLEFT", bar, "TOPLEFT", math.max(0, endX - magicW), 0)
    row.magicOverlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", math.max(0, endX - magicW), 0)
    row.magicOverlay:SetWidth(magicW)
  else
    hideOverlay(row.magicOverlay)
  end

  if row.blockOverlay and blockW > 0.5 and endX > 0.5 then
    local startX = math.max(0, endX - magicW - blockW)
    row.blockOverlay:Show()
    row.blockOverlay:SetAlpha(0.65)
    row.blockOverlay:ClearAllPoints()
    row.blockOverlay:SetPoint("TOPLEFT", bar, "TOPLEFT", startX, 0)
    row.blockOverlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", startX, 0)
    row.blockOverlay:SetWidth(blockW)
  else
    hideOverlay(row.blockOverlay)
  end
end

local function setBarValue(row, label, value, maxValue, color)
  local v = tonumber(value) or 0
  local m = tonumber(maxValue) or 0
  if m <= 0 then m = 1 end

  local clamped = v
  if clamped < 0 then clamped = 0 end
  if clamped > m then clamped = m end

  row.bar:SetMinMaxValues(0, m)
  row.bar:SetValue(clamped)

  local r, g, b = 0.20, 0.55, 1.00
  if type(color) == "table" then
    r = color[1] or r
    g = color[2] or g
    b = color[3] or b
  end
  row.bar:SetStatusBarColor(r, g, b, 1)

  local pct = 0
  if m > 0 then
    pct = math.floor((clamped / m) * 100 + 0.5)
  end

  row.topText:SetText(string.format("%s : %d / %d (%d%%)", label, roundNumber(v), roundNumber(m), pct))
end

local function applyClassIcon(classKey)
  if not popupFrame or not popupFrame.classIcon then return end

  local coords = CLASS_ICON_COORDS[classKey or ""]
  if coords then
    popupFrame.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    popupFrame.classIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    popupFrame.classIcon:Show()
  else
    popupFrame.classIcon:Hide()
  end
end

local function createPopup()
  if popupFrame then return end

  popupFrame = CreateFrame("Frame", "GrosOrteilTargetPopup", UIParent, "BackdropTemplate")
  popupFrame:SetSize(340, 236)
  popupFrame:SetFrameStrata("DIALOG")
  popupFrame:SetMovable(true)
  popupFrame:EnableMouse(true)
  popupFrame:RegisterForDrag("LeftButton")
  popupFrame:SetScript("OnDragStart", popupFrame.StartMoving)
  popupFrame:SetScript("OnDragStop", popupFrame.StopMovingOrSizing)

  popupFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true,
    tileSize = 24,
    edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
  popupFrame:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
  popupFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -56, 220)

  popupFrame.header = popupFrame:CreateTexture(nil, "BORDER")
  popupFrame.header:SetTexture("Interface\\Buttons\\WHITE8x8")
  popupFrame.header:SetVertexColor(0.17, 0.12, 0.06, 0.60)
  popupFrame.header:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 14, -14)
  popupFrame.header:SetPoint("TOPRIGHT", popupFrame, "TOPRIGHT", -14, -14)
  popupFrame.header:SetHeight(42)

  popupFrame.title = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  popupFrame.title:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 22, -22)
  popupFrame.title:SetJustifyH("LEFT")
  popupFrame.title:SetText("Inconnu")

  popupFrame.classText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  popupFrame.classText:SetPoint("TOPLEFT", popupFrame.title, "BOTTOMLEFT", 0, -3)
  popupFrame.classText:SetJustifyH("LEFT")
  popupFrame.classText:SetText("Classe: Inconnue")

  popupFrame.armorIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.armorIcon:SetSize(14, 14)
  popupFrame.armorIcon:SetTexture("Interface\\Icons\\INV_Shield_06")
  popupFrame.armorIcon:SetPoint("TOPLEFT", popupFrame.classText, "BOTTOMLEFT", 0, -8)

  popupFrame.armorText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.armorText:SetPoint("LEFT", popupFrame.armorIcon, "RIGHT", 4, 0)
  popupFrame.armorText:SetJustifyH("LEFT")
  popupFrame.armorText:SetText("Armure: 0")

  popupFrame.dodgeIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.dodgeIcon:SetSize(14, 14)
  popupFrame.dodgeIcon:SetTexture("Interface\\Icons\\Ability_Rogue_Sprint")
  popupFrame.dodgeIcon:SetPoint("LEFT", popupFrame.armorText, "RIGHT", 18, 0)

  popupFrame.dodgeText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.dodgeText:SetPoint("LEFT", popupFrame.dodgeIcon, "RIGHT", 4, 0)
  popupFrame.dodgeText:SetJustifyH("LEFT")
  popupFrame.dodgeText:SetText("Esquive: 0")

  popupFrame.classIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.classIcon:SetSize(28, 28)
  popupFrame.classIcon:SetPoint("TOPRIGHT", popupFrame, "TOPRIGHT", -26, -24)

  popupFrame.hpRow = createStatBar(popupFrame, -92)

  popupFrame.hpRow.blockOverlay = popupFrame.hpRow.bar:CreateTexture(nil, "OVERLAY")
  popupFrame.hpRow.blockOverlay:SetTexture("Interface/Buttons/WHITE8x8")
  popupFrame.hpRow.blockOverlay:SetColorTexture(0.65, 0.65, 0.65, 0.55)
  popupFrame.hpRow.blockOverlay:SetPoint("TOP", popupFrame.hpRow.bar, "TOP", 0, 0)
  popupFrame.hpRow.blockOverlay:SetPoint("BOTTOM", popupFrame.hpRow.bar, "BOTTOM", 0, 0)
  popupFrame.hpRow.blockOverlay:Hide()

  popupFrame.hpRow.magicOverlay = popupFrame.hpRow.bar:CreateTexture(nil, "OVERLAY")
  popupFrame.hpRow.magicOverlay:SetTexture("Interface/Buttons/WHITE8x8")
  popupFrame.hpRow.magicOverlay:SetColorTexture(1.0, 0.82, 0.22, 0.60)
  popupFrame.hpRow.magicOverlay:SetPoint("TOP", popupFrame.hpRow.bar, "TOP", 0, 0)
  popupFrame.hpRow.magicOverlay:SetPoint("BOTTOM", popupFrame.hpRow.bar, "BOTTOM", 0, 0)
  popupFrame.hpRow.magicOverlay:Hide()

  popupFrame.resRows = {}
  for i = 1, 4 do
    popupFrame.resRows[i] = createStatBar(popupFrame, -128 - ((i - 1) * 34))
    popupFrame.resRows[i].holder:Hide()
  end

  popupFrame.hpMarkers = {
    makeMarker(popupFrame.hpRow.bar, 0.50, 1.0, 1.0, 1.0, 0.35, 2),
    makeMarker(popupFrame.hpRow.bar, 0.25, 1.0, 0.65, 0.10, 0.45, 2),
    makeMarker(popupFrame.hpRow.bar, 0.10, 1.0, 0.15, 0.15, 0.55, 2),
  }
  popupFrame.hpCapMarker = makeMarker(popupFrame.hpRow.bar, 1.0, 1.0, 0.9, 0.2, 0.7, 3)

  popupFrame.closeButton = CreateFrame("Button", nil, popupFrame, "UIPanelCloseButton")
  popupFrame.closeButton:SetPoint("TOPRIGHT", popupFrame, "TOPRIGHT", -3, -2)
  popupFrame.closeButton:SetScript("OnClick", hidePopup)
end

local function showForState(targetName, state)
  createPopup()

  local rpName, rpColor = getRPDisplayName(targetName)
  if rpColor and type(rpColor) == "string" and rpColor:match("^%x%x%x%x%x%x%x%x$") then
    popupFrame.title:SetText("|c" .. rpColor .. rpName .. "|r")
  else
    popupFrame.title:SetText(rpName)
  end

  local className = getClassNameFr(state.classKey)
  popupFrame.classText:SetText("Classe: " .. className)
  applyClassIcon(state.classKey)

  local armor = tonumber(state.armor) or 0
  local trueArmor = tonumber(state.trueArmor) or 0
  local dodge = tonumber(state.dodge) or 0
  popupFrame.armorText:SetText(string.format("Armure: %d (+%d)", roundNumber(armor), roundNumber(trueArmor)))
  popupFrame.dodgeText:SetText(string.format("Esquive: %d", roundNumber(dodge)))

  local baseHp = tonumber(state.maxHp) or 0
  local bonusHp = tonumber(state.bonusHp) or 0
  if bonusHp < 0 then bonusHp = 0 end
  local effMaxHp = baseHp + bonusHp
  if effMaxHp <= 0 then effMaxHp = 1 end

  setBarValue(popupFrame.hpRow, "Vie", state.hp, effMaxHp, { 0.85, 0.16, 0.18 })
  updateHpShieldOverlays(
    popupFrame.hpRow,
    tonumber(state.hp) or 0,
    effMaxHp,
    tonumber(state.tempBlock) or 0,
    tonumber(state.tempMagicBlock) or 0
  )

  for i = 1, #popupFrame.hpMarkers do
    local m = popupFrame.hpMarkers[i]
    local pct = m.pct or 0
    local thresholdHp = baseHp * pct
    m.pct = thresholdHp / effMaxHp
  end
  positionMarkers(popupFrame.hpMarkers, popupFrame.hpRow.bar)

  local woundCap = 1.0
  if state.wounds and state.wounds.hit10 then
    woundCap = 0.25
  elseif state.wounds and state.wounds.hit25 then
    woundCap = 0.50
  end
  if woundCap >= 1.0 then
    popupFrame.hpCapMarker:Hide()
  else
    popupFrame.hpCapMarker.pct = (baseHp * woundCap) / effMaxHp
    positionMarkers({ popupFrame.hpCapMarker }, popupFrame.hpRow.bar)
  end

  local profile = getResProfile(state.classKey)
  local shownRes = 0
  for i = 1, 4 do
    local row = popupFrame.resRows[i]
    local p = profile[i]
    if row and p then
      local resKey, maxKey = getKeysForIdx(p.idx)
      local cur = state[resKey] or 0
      local maxv = state[maxKey] or 0
      local displayMax = maxv

      local isWarlockCorruption = (state.classKey == "WARLOCK" and p.idx == 2)
      local isShadowInsanity = (state.classKey == "SHADOWPRIEST" and p.idx == 2)

      if isWarlockCorruption then
        displayMax = 60
      elseif isShadowInsanity then
        displayMax = 25
      end

      setBarValue(row, p.label or "Ressource", cur, displayMax, { p.r, p.g, p.b })
      hideMarkers(row.markers)
      if isWarlockCorruption then
        if #row.markers == 0 then
          row.markers[1] = makeMarker(row.bar, 10 / 60, 0.65, 0.95, 0.65, 0.55, 2)
          row.markers[2] = makeMarker(row.bar, 25 / 60, 1.00, 0.82, 0.22, 0.55, 2)
          row.markers[3] = makeMarker(row.bar, 45 / 60, 1.00, 0.25, 0.25, 0.65, 3)
        end
        positionMarkers(row.markers, row.bar)
      elseif isShadowInsanity then
        if #row.markers == 0 then
          row.markers[1] = makeMarker(row.bar, 4 / 25, 0.65, 0.95, 0.65, 0.45, 2)
          row.markers[2] = makeMarker(row.bar, 12 / 25, 1.00, 0.82, 0.22, 0.55, 2)
          row.markers[3] = makeMarker(row.bar, 20 / 25, 1.00, 0.55, 0.10, 0.60, 2)
          row.markers[4] = makeMarker(row.bar, 25 / 25, 1.00, 0.25, 0.25, 0.70, 3)
        end
        positionMarkers(row.markers, row.bar)
      end

      row.holder:Show()
      shownRes = shownRes + 1
    elseif row then
      row.holder:Hide()
      hideMarkers(row.markers)
    end
  end

  local dynamicHeight = 140 + (shownRes * 34)
  if dynamicHeight < 180 then dynamicHeight = 180 end
  popupFrame:SetHeight(dynamicHeight)

  popupFrame:Show()
end

function Popup:OnStateReceived(sender, state)
  local _ = self
  if type(state) ~= "table" then
    return
  end

  local senderKey = normalizeName(sender)
  if not senderKey then
    return
  end

  local targetKey = normalizeName(unitTargetName("target"))
  local pendingKey = normalizeName(pendingTarget)

  if targetKey and namesMatch(senderKey, targetKey) then
    showForState(sender, state)
    pendingTarget = nil
    return
  end

  if pendingKey and namesMatch(senderKey, pendingKey) then
    showForState(sender, state)
    pendingTarget = nil
  end
end

function Popup:OnTargetChanged()
  local _ = self
  hidePopup()
  pendingTarget = nil

  if not UnitExists("target") or not UnitIsPlayer("target") then
    return
  end

  local targetName = unitTargetName("target")
  if not targetName then
    return
  end

  pendingTarget = targetName

  if ns.Comm and ns.Comm.RequestState then
    ns.Comm:RequestState(targetName)
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(5, function()
      if pendingTarget and normalizeName(pendingTarget) == normalizeName(targetName) then
        pendingTarget = nil
      end
    end)
  end
end

function Popup:Initialize()
  if self.eventFrame then
    return
  end

  self.eventFrame = CreateFrame("Frame")
  self.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
  self.eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
      self:OnTargetChanged()
    end
  end)
end

function ns.TargetPopup_Init()
  Popup:Initialize()
end
