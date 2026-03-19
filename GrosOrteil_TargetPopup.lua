---@diagnostic disable: undefined-global
local _, ns = ...

local Popup = {}
ns.TargetPopup = Popup

local Shared = ns.Shared

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
-- LibRPNames is looked up lazily at call time (may not be ready at load time).

local getResProfile    = Shared.GetResProfile
local getKeysForIdx    = Shared.GetKeysForIdx
local makeMarker       = Shared.MakeMarker
local hideMarkers      = Shared.HideMarkers
local positionMarkers  = Shared.PositionMarkers
local hideOverlay      = Shared.HideOverlay
local roundNumber      = Shared.Round
local getClassNameFr   = Shared.GetClassNameFr

local pendingTarget
local popupFrame

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


local function baseCharacterName(name)
  if type(name) ~= "string" or name == "" then return "Inconnu" end
  return name:match("^[^-]+") or name
end





local function getRPDisplayName(playerName)
  local guid
  local targetName = unitTargetName("target")
  if targetName and namesMatch(targetName, playerName) and UnitGUID then
    guid = UnitGUID("target")
  end

  -- Lazy lookup: LibRPNames may not be in _G at addon load time.
  local lrn = rawget(_G, "LibRPNames")
  if lrn and lrn.Get then
    local fullName, _, _, color = lrn.Get(playerName, guid)
    if type(fullName) == "string" and fullName ~= "" then
      return fullName, color
    end
  end

  -- Fallback: query TRP3 registry directly for the sender's profile.
  local api = rawget(_G, "TRP3_API")
  if type(api) == "table" then
    local reg = api.register
    if type(reg) == "table" and type(reg.getProfile) == "function" then
      local ok, profile = pcall(reg.getProfile, playerName)
      if ok and type(profile) == "table" then
        local char = profile.player and profile.player.characteristics
        if type(char) == "table" then
          local first = char.FN
          local last  = char.LN
          if type(first) == "string" then first = string.gsub(string.gsub(first, "^%s+", ""), "%s+$", "") end
          if type(last)  == "string" then last  = string.gsub(string.gsub(last,  "^%s+", ""), "%s+$", "") end
          if type(first) == "string" and first ~= "" then
            if type(last) == "string" and last ~= "" then
              return first .. " " .. last, nil
            end
            return first, nil
          end
        end
      end
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

local function updateHpShieldOverlays(row, hpNow, maxHp, blockValue, magicValue)
  if not row or not row.bar then return end
  Shared.UpdateHpShieldOverlays(
    row.blockOverlay, row.magicOverlay, row.bar,
    hpNow, maxHp, blockValue, magicValue
  )
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
  if not classKey or classKey == "" then
    popupFrame.classIcon:Hide()
    return
  end
  Shared.SetClassIconTexCoords(popupFrame.classIcon, classKey)
  popupFrame.classIcon:Show()
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
  for i = 1, 5 do
    popupFrame.resRows[i] = createStatBar(popupFrame, -128 - ((i - 1) * 34))
    popupFrame.resRows[i].holder:Hide()
  end

  popupFrame.petNameText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  popupFrame.petNameText:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, -264)
  popupFrame.petNameText:SetJustifyH("LEFT")
  popupFrame.petNameText:SetText("Familier")
  popupFrame.petNameText:Hide()

  popupFrame.petArmorIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.petArmorIcon:SetSize(14, 14)
  popupFrame.petArmorIcon:SetTexture("Interface\\Icons\\INV_Shield_06")
  popupFrame.petArmorIcon:SetPoint("TOPLEFT", popupFrame.petNameText, "BOTTOMLEFT", 0, -4)
  popupFrame.petArmorIcon:Hide()

  popupFrame.petArmorText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.petArmorText:SetPoint("LEFT", popupFrame.petArmorIcon, "RIGHT", 4, 0)
  popupFrame.petArmorText:SetJustifyH("LEFT")
  popupFrame.petArmorText:SetText("Armure: 0")
  popupFrame.petArmorText:Hide()

  popupFrame.petDodgeIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.petDodgeIcon:SetSize(14, 14)
  popupFrame.petDodgeIcon:SetTexture("Interface\\Icons\\Ability_Rogue_Sprint")
  popupFrame.petDodgeIcon:SetPoint("LEFT", popupFrame.petArmorText, "RIGHT", 18, 0)
  popupFrame.petDodgeIcon:Hide()

  popupFrame.petDodgeText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.petDodgeText:SetPoint("LEFT", popupFrame.petDodgeIcon, "RIGHT", 4, 0)
  popupFrame.petDodgeText:SetJustifyH("LEFT")
  popupFrame.petDodgeText:SetText("Esquive: 0")
  popupFrame.petDodgeText:Hide()

  popupFrame.petHpRow = createStatBar(popupFrame, -298)
  popupFrame.petHpRow.blockOverlay = popupFrame.petHpRow.bar:CreateTexture(nil, "OVERLAY")
  popupFrame.petHpRow.blockOverlay:SetTexture("Interface/Buttons/WHITE8x8")
  popupFrame.petHpRow.blockOverlay:SetColorTexture(0.65, 0.65, 0.65, 0.55)
  popupFrame.petHpRow.blockOverlay:SetPoint("TOP", popupFrame.petHpRow.bar, "TOP", 0, 0)
  popupFrame.petHpRow.blockOverlay:SetPoint("BOTTOM", popupFrame.petHpRow.bar, "BOTTOM", 0, 0)
  popupFrame.petHpRow.blockOverlay:Hide()

  popupFrame.petHpRow.magicOverlay = popupFrame.petHpRow.bar:CreateTexture(nil, "OVERLAY")
  popupFrame.petHpRow.magicOverlay:SetTexture("Interface/Buttons/WHITE8x8")
  popupFrame.petHpRow.magicOverlay:SetColorTexture(1.0, 0.82, 0.22, 0.60)
  popupFrame.petHpRow.magicOverlay:SetPoint("TOP", popupFrame.petHpRow.bar, "TOP", 0, 0)
  popupFrame.petHpRow.magicOverlay:SetPoint("BOTTOM", popupFrame.petHpRow.bar, "BOTTOM", 0, 0)
  popupFrame.petHpRow.magicOverlay:Hide()
  popupFrame.petHpRow.holder:Hide()

  popupFrame.petHpMarkers = {
    makeMarker(popupFrame.petHpRow.bar, 0.50, 1.0, 1.0, 1.0, 0.35, 2),
    makeMarker(popupFrame.petHpRow.bar, 0.25, 1.0, 0.65, 0.10, 0.45, 2),
    makeMarker(popupFrame.petHpRow.bar, 0.10, 1.0, 0.15, 0.15, 0.55, 2),
  }
  popupFrame.petHpCapMarker = makeMarker(popupFrame.petHpRow.bar, 1.0, 1.0, 0.9, 0.2, 0.7, 3)

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

  local profile = getResProfile(state)
  local shownRes = 0
  for i = 1, 5 do
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
  local pet = state.pet
  local hasPet = type(pet) == "table" and pet.enabled
  if hasPet then
    local petY = -128 - (shownRes * 34) - 10

    popupFrame.petNameText:ClearAllPoints()
    popupFrame.petNameText:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, petY)
    popupFrame.petHpRow.holder:ClearAllPoints()
    popupFrame.petHpRow.holder:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, petY - 38)

    local petName = type(pet.name) == "string" and pet.name or "Familier"
    local petArmor = tonumber(pet.armor) or 0
    local petTrueArmor = tonumber(pet.trueArmor) or 0
    local petDodge = tonumber(pet.dodge) or 0
    local petMaxHp = tonumber(pet.maxHp) or 1
    local petHp = tonumber(pet.hp) or 0
    if petMaxHp <= 0 then petMaxHp = 1 end

    popupFrame.petNameText:SetText("Familier: " .. petName)
    popupFrame.petArmorText:SetText(string.format("Armure: %d (+%d)", roundNumber(petArmor), roundNumber(petTrueArmor)))
    popupFrame.petDodgeText:SetText(string.format("Esquive: %d", roundNumber(petDodge)))
    setBarValue(popupFrame.petHpRow, "Vie du familier", petHp, petMaxHp, { 0.95, 0.62, 0.18 })
    updateHpShieldOverlays(
      popupFrame.petHpRow,
      petHp,
      petMaxHp,
      0,
      tonumber(pet.tempMagicBlock) or 0
    )

    for i = 1, #popupFrame.petHpMarkers do
      local m = popupFrame.petHpMarkers[i]
      m.pct = m.pct or 0
    end
    positionMarkers(popupFrame.petHpMarkers, popupFrame.petHpRow.bar)

    local petWoundCap = 1.0
    if pet.wounds and pet.wounds.hit10 then
      petWoundCap = 0.25
    elseif pet.wounds and pet.wounds.hit25 then
      petWoundCap = 0.50
    end
    if petWoundCap >= 1.0 then
      popupFrame.petHpCapMarker:Hide()
    else
      popupFrame.petHpCapMarker.pct = petWoundCap
      positionMarkers({ popupFrame.petHpCapMarker }, popupFrame.petHpRow.bar)
    end

    popupFrame.petNameText:Show()
    popupFrame.petArmorIcon:Show()
    popupFrame.petArmorText:Show()
    popupFrame.petDodgeIcon:Show()
    popupFrame.petDodgeText:Show()
    popupFrame.petHpRow.holder:Show()

    dynamicHeight = dynamicHeight + 86
  else
    popupFrame.petNameText:Hide()
    popupFrame.petArmorIcon:Hide()
    popupFrame.petArmorText:Hide()
    popupFrame.petDodgeIcon:Hide()
    popupFrame.petDodgeText:Hide()
    popupFrame.petHpRow.holder:Hide()
    hideMarkers(popupFrame.petHpMarkers)
    if popupFrame.petHpCapMarker then popupFrame.petHpCapMarker:Hide() end
    hideOverlay(popupFrame.petHpRow.blockOverlay)
    hideOverlay(popupFrame.petHpRow.magicOverlay)
  end

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
