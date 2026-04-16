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
local GetTime = rawget(_G, "GetTime")
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
local pendingHoverUnit   -- cache key of the unit we last requested on hover
local pendingHoverTime   = 0
local HOVER_REQUEST_COOLDOWN = 5  -- seconds between requests for the same unit
local popupFrame
local currentShownSender

-- State cache: normalizedName → { state, t }
-- Allows instant popup display on re-target; fresh data still fetched in background.
local stateCache = {}
local CACHE_TTL  = 60  -- seconds

-- Hover popup forward declarations (functions defined at end of file)
local hoverFrame
local tryShowHover
local hideHoverPopup
local reanchorHover

local function getCached(key)
  local e = stateCache[key]
  if not e then return nil end
  if GetTime and (GetTime() - e.t) > CACHE_TTL then
    stateCache[key] = nil
    return nil
  end
  return e.state
end

local function setCached(key, state)
  stateCache[key] = { state = state, t = GetTime and GetTime() or 0 }
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

-- Cache key uses short name only so "Foo" and "Foo-Realm" share the same entry.
local function toCacheKey(name)
  local short = splitNameRealm(name)
  return short
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





-- Resolve the TRP3 unit ID for a sender name (e.g. "Foo" → "Foo-RealmName").
local function senderToUnitID(playerName)
  if playerName:find("-") then
    return playerName
  end
  local api = rawget(_G, "TRP3_API")
  local realm = api and api.globals and api.globals.player_realm_id
  if type(realm) == "string" and realm ~= "" then
    return playerName .. "-" .. realm
  end
  return playerName
end

local function getRPDisplayName(playerName)
  local guid
  local targetName = unitTargetName("target")
  if targetName and namesMatch(targetName, playerName) and UnitGUID then
    guid = UnitGUID("target")
  end

  -- Lazy lookup: LibRPNames may not be in _G at addon load time.
  -- LibRPNames.Get() always returns a non-empty string (falls back to the
  -- character name when TRP3 has no profile), so we only trust its result
  -- when it actually found RP data – i.e. when the returned name differs
  -- from the bare character name.
  local lrn = rawget(_G, "LibRPNames")
  if lrn and lrn.Get then
    local fullName, _, _, color = lrn.Get(playerName, guid)
    if type(fullName) == "string" and fullName ~= "" and fullName ~= baseCharacterName(playerName) then
      return fullName, color
    end
  end

  -- Fallback: query TRP3 registry directly using the correct unit ID and API.
  -- TRP3_API.register.getProfile() takes a profileID (UUID), not a player
  -- name. The correct call is getUnitIDCurrentProfile(unitID).
  local api = rawget(_G, "TRP3_API")
  if type(api) == "table" then
    local reg = api.register
    if type(reg) == "table" and type(reg.isUnitIDKnown) == "function" then
      local unitID = senderToUnitID(playerName)
      if reg.isUnitIDKnown(unitID) and type(reg.getUnitIDCurrentProfile) == "function" then
        local ok, profile = pcall(reg.getUnitIDCurrentProfile, unitID)
        if ok and type(profile) == "table" then
          local char = profile.characteristics
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
  end

  return baseCharacterName(playerName), nil
end

local function hidePopup()
  if popupFrame then
    popupFrame:Hide()
  end
  currentShownSender = nil
end

local function getSettings()
  local db = ns.GetDB and ns.GetDB() or {}
  db.settings = db.settings or {}
  return db.settings
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

local function applyPopupTitle(rpName, rpColor)
  if rpColor and type(rpColor) == "string" and rpColor:match("^%x%x%x%x%x%x%x%x$") then
    popupFrame.title:SetText("|c" .. rpColor .. rpName .. "|r")
  else
    popupFrame.title:SetText(rpName)
  end
end

local function showForState(targetName, state)
  createPopup()
  currentShownSender = targetName

  -- Clear LibRPNames cache so we always get a fresh TRP3 lookup rather than
  -- a stale "character name" result from a previous failed attempt.
  local lrn = rawget(_G, "LibRPNames")
  if lrn and lrn.ClearCache then lrn.ClearCache() end

  local rpName, rpColor = getRPDisplayName(targetName)
  applyPopupTitle(rpName, rpColor)

  -- TRP3 may not have the target's profile yet (it's fetched asynchronously).
  -- Schedule a deferred refresh so the title updates once TRP3 receives it.
  if C_Timer and C_Timer.After then
    local capturedSender = targetName
    C_Timer.After(2, function()
      if popupFrame and popupFrame:IsShown() and currentShownSender == capturedSender then
        if lrn and lrn.ClearCache then lrn.ClearCache() end
        local newName, newColor = getRPDisplayName(capturedSender)
        applyPopupTitle(newName, newColor)
      end
    end)
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

  setBarValue(popupFrame.hpRow, "PV", state.hp, effMaxHp, { 0.85, 0.16, 0.18 })
  updateHpShieldOverlays(
    popupFrame.hpRow,
    tonumber(state.hp) or 0,
    effMaxHp,
    tonumber(state.tempBlock) or 0,
    tonumber(state.tempMagicBlock) or 0
  )

  local HP_THRESHOLD_PCTS = { 0.50, 0.25, 0.10 }
  for i = 1, #popupFrame.hpMarkers do
    local m = popupFrame.hpMarkers[i]
    local thresholdHp = baseHp * (HP_THRESHOLD_PCTS[i] or 0)
    m.pct = (effMaxHp > 0) and (thresholdHp / effMaxHp) or 0
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

      local isWarlockCorruption = (state.classKey == "WARLOCK"      and p.idx == 2)
      local isShadowInsanity    = (state.classKey == "SHADOWPRIEST" and p.idx == 2)
      local isMageArcaneCharge  = (state.classKey == "MAGE"         and p.idx == 2)

      if isWarlockCorruption then
        displayMax = 60
      elseif isShadowInsanity then
        displayMax = 25
      elseif isMageArcaneCharge then
        displayMax = 8
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
      elseif isMageArcaneCharge then
        if #row.markers == 0 then
          row.markers[1] = makeMarker(row.bar, 4 / 8, 1.00, 0.82, 0.22, 0.65, 2)
          row.markers[2] = makeMarker(row.bar, 8 / 8, 0.75, 0.30, 1.00, 0.80, 3)
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
    setBarValue(popupFrame.petHpRow, "PV familier", petHp, petMaxHp, { 0.95, 0.62, 0.18 })
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

  -- Always refresh cache with latest data.
  setCached(toCacheKey(sender), state)

  -- Refresh hover popup if it is showing for this sender, or try to show it
  -- if the user is currently hovering this unit (state just became available).
  if tryShowHover then tryShowHover() end

  -- If popup is already showing for this sender, refresh it in-place.
  local shownKey = normalizeName(currentShownSender)
  if popupFrame and popupFrame:IsShown() and shownKey and namesMatch(senderKey, shownKey) then
    showForState(sender, state)
    pendingTarget = nil
    return
  end

  local targetKey = normalizeName(unitTargetName("target"))
  local pendingKey = normalizeName(pendingTarget)

  if targetKey and namesMatch(senderKey, targetKey) then
    local settings = getSettings()
    if settings.popupOnTarget ~= false then
      showForState(sender, state)
    end
    pendingTarget = nil
    return
  end

  if pendingKey and namesMatch(senderKey, pendingKey) then
    local settings = getSettings()
    if settings.popupOnTarget ~= false then
      showForState(sender, state)
    end
    pendingTarget = nil
  end
end

function Popup:OnTargetChanged()
  local _ = self
  if popupFrame and popupFrame:IsShown() then
    hidePopup()
  end
  pendingTarget = nil

  local settings = getSettings()
  if settings.popupOnTarget == false then
    return
  end

  if not UnitExists("target") or not UnitIsPlayer("target") then
    return
  end

  local targetName = unitTargetName("target")
  if not targetName then
    return
  end

  -- Show cached state instantly; fresh data will arrive and refresh via OnStateReceived.
  local cached = getCached(toCacheKey(targetName))
  if cached then
    showForState(targetName, cached)
  else
    -- No cache: wait for the network response before showing.
    pendingTarget = targetName
    if C_Timer and C_Timer.After then
      C_Timer.After(5, function()
        if pendingTarget and normalizeName(pendingTarget) == normalizeName(targetName) then
          pendingTarget = nil
        end
      end)
    end
  end

  -- Always request fresh state (updates cache + refreshes popup if shown).
  if ns.Comm and ns.Comm.RequestState then
    ns.Comm:RequestState(targetName)
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

  -- Hover popup: hook GameTooltip to detect player mouseover
  local gt = GameTooltip
  if gt then
    hooksecurefunc(gt, "SetUnit", function()
      if tryShowHover and C_Timer then
        C_Timer.After(0, tryShowHover)
      end
    end)
    gt:HookScript("OnHide", function()
      -- TRP3 may hide GameTooltip while still showing TRP3_CharacterTooltip;
      -- in that case the hover popup should stay up (anchored to TRP3).
      if hideHoverPopup then
        local trpTip = rawget(_G, "TRP3_CharacterTooltip")
        if not trpTip or not trpTip:IsShown() then
          hideHoverPopup()
        end
      end
    end)
  end

  -- Hook TRP3_CharacterTooltip; retry via ADDON_LOADED if not ready yet
  local function hookTRP3Tooltip()
    local trpTip = rawget(_G, "TRP3_CharacterTooltip")
    if not trpTip then return false end
    trpTip:HookScript("OnShow", function()
      if C_Timer then
        C_Timer.After(0, function()
          if tryShowHover then tryShowHover() end
          if reanchorHover then reanchorHover() end
        end)
      end
    end)
    trpTip:HookScript("OnHide", function()
      if not gt or not gt:IsShown() then
        if hideHoverPopup then hideHoverPopup() end
      end
    end)
    return true
  end

  if not hookTRP3Tooltip() then
    local trpWaitFrame = CreateFrame("Frame")
    trpWaitFrame:RegisterEvent("ADDON_LOADED")
    trpWaitFrame:SetScript("OnEvent", function(_, _, addonName)
      if addonName == "totalRP3" then
        hookTRP3Tooltip()
        trpWaitFrame:UnregisterAllEvents()
      end
    end)
  end
end

-- ============================================================
-- Hover Popup — minimalist bars (% only), glued to TRP3 tooltip
-- ============================================================

local HOVER_BAR_W = 200
local HOVER_BAR_H = 16
local HOVER_PAD   = 8
local HOVER_GAP   = 4

-- positionMarkers uses bar:GetWidth() which returns 0 before first layout.
-- Use the known constant width instead.
local function positionHoverMarkers(markers, bar)
  for i = 1, #markers do
    local m = markers[i]
    if m then
      local x = HOVER_BAR_W * (m.pct or 0)
      if x < 0 then x = 0 elseif x > HOVER_BAR_W then x = HOVER_BAR_W end
      m:SetHeight(HOVER_BAR_H)
      m:Show()
      m:ClearAllPoints()
      m:SetPoint("LEFT", bar, "LEFT", x, 0)
    end
  end
end

local function createHoverBar(parent)
  local barFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  barFrame:SetSize(HOVER_BAR_W, HOVER_BAR_H)
  barFrame:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
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

  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetAllPoints(bar)
  label:SetJustifyH("CENTER")
  label:SetJustifyV("MIDDLE")
  label:SetText("")

  return { frame = barFrame, bar = bar, label = label, markers = {} }
end

local function createHoverPopup()
  if hoverFrame then return end

  hoverFrame = CreateFrame("Frame", "GrosOrteilHoverPopup", UIParent, "BackdropTemplate")
  hoverFrame:SetFrameStrata("TOOLTIP")
  hoverFrame:SetFrameLevel(10)
  hoverFrame:SetWidth(HOVER_BAR_W + HOVER_PAD * 2)
  hoverFrame:SetHeight(HOVER_PAD * 2 + HOVER_BAR_H)
  hoverFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile     = true,
    tileSize = 24,
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  hoverFrame:SetBackdropColor(0.03, 0.03, 0.03, 0.92)

  -- HP bar + overlays + markers
  hoverFrame.hpBar = createHoverBar(hoverFrame)

  hoverFrame.hpBar.blockOverlay = hoverFrame.hpBar.bar:CreateTexture(nil, "OVERLAY")
  hoverFrame.hpBar.blockOverlay:SetTexture("Interface/Buttons/WHITE8x8")
  hoverFrame.hpBar.blockOverlay:SetColorTexture(0.65, 0.65, 0.65, 0.55)
  hoverFrame.hpBar.blockOverlay:SetPoint("TOP",    hoverFrame.hpBar.bar, "TOP",    0, 0)
  hoverFrame.hpBar.blockOverlay:SetPoint("BOTTOM", hoverFrame.hpBar.bar, "BOTTOM", 0, 0)
  hoverFrame.hpBar.blockOverlay:Hide()

  hoverFrame.hpBar.magicOverlay = hoverFrame.hpBar.bar:CreateTexture(nil, "OVERLAY")
  hoverFrame.hpBar.magicOverlay:SetTexture("Interface/Buttons/WHITE8x8")
  hoverFrame.hpBar.magicOverlay:SetColorTexture(1.0, 0.82, 0.22, 0.60)
  hoverFrame.hpBar.magicOverlay:SetPoint("TOP",    hoverFrame.hpBar.bar, "TOP",    0, 0)
  hoverFrame.hpBar.magicOverlay:SetPoint("BOTTOM", hoverFrame.hpBar.bar, "BOTTOM", 0, 0)
  hoverFrame.hpBar.magicOverlay:Hide()

  hoverFrame.hpMarkers = {
    makeMarker(hoverFrame.hpBar.bar, 0.50, 1.0, 1.0, 1.0, 0.35, 2),
    makeMarker(hoverFrame.hpBar.bar, 0.25, 1.0, 0.65, 0.10, 0.45, 2),
    makeMarker(hoverFrame.hpBar.bar, 0.10, 1.0, 0.15, 0.15, 0.55, 2),
  }
  hoverFrame.hpCapMarker = makeMarker(hoverFrame.hpBar.bar, 1.0, 1.0, 0.9, 0.2, 0.7, 3)

  -- Resource bars (up to 5, shown/hidden dynamically)
  hoverFrame.resBars = {}
  for i = 1, 5 do
    local rb = createHoverBar(hoverFrame)
    rb.frame:Hide()
    hoverFrame.resBars[i] = rb
  end

  hoverFrame:Hide()
end

local function getHoverUnitName()
  if UnitExists("mouseover") and UnitIsPlayer("mouseover") then
    return unitTargetName("mouseover")
  end
  local gt = rawget(_G, "GameTooltip")
  if gt then
    local unit = gt.GetUnit and gt:GetUnit()
    if unit and UnitExists(unit) and UnitIsPlayer(unit) then
      return unitTargetName(unit)
    end
  end
  return nil
end

reanchorHover = function()
  if not hoverFrame then return end
  local trpTip = rawget(_G, "TRP3_CharacterTooltip")
  if trpTip and trpTip:IsShown() then
    hoverFrame:ClearAllPoints()
    hoverFrame:SetPoint("BOTTOMLEFT", trpTip, "TOPLEFT", 0, 2)
    return
  end
  local gt = rawget(_G, "GameTooltip")
  if gt and gt:IsShown() then
    hoverFrame:ClearAllPoints()
    hoverFrame:SetPoint("BOTTOMLEFT", gt, "TOPLEFT", 0, 2)
    return
  end
  hoverFrame:Hide()
end

hideHoverPopup = function()
  if hoverFrame then hoverFrame:Hide() end
end

local function showHoverForState(state)
  createHoverPopup()

  -- HP bar
  local baseHp  = tonumber(state.maxHp)  or 0
  local bonusHp = tonumber(state.bonusHp) or 0
  if bonusHp < 0 then bonusHp = 0 end
  local effMax  = baseHp + bonusHp
  if effMax <= 0 then effMax = 1 end
  local hp      = tonumber(state.hp) or 0
  local hpClamp = math.max(0, math.min(hp, effMax))
  hoverFrame.hpBar.bar:SetMinMaxValues(0, effMax)
  hoverFrame.hpBar.bar:SetValue(hpClamp)
  hoverFrame.hpBar.bar:SetStatusBarColor(0.85, 0.16, 0.18, 1)
  hoverFrame.hpBar.label:SetText(string.format("PV : %d / %d", roundNumber(hp), roundNumber(effMax)))

  Shared.UpdateHpShieldOverlays(
    hoverFrame.hpBar.blockOverlay, hoverFrame.hpBar.magicOverlay,
    hoverFrame.hpBar.bar, hp, effMax,
    tonumber(state.tempBlock) or 0, (state.magicShield and state.magicShield.hp or 0)
  )

  local HP_THRESHOLD_PCTS = { 0.50, 0.25, 0.10 }
  for i = 1, #hoverFrame.hpMarkers do
    local m = hoverFrame.hpMarkers[i]
    m.pct = effMax > 0 and (baseHp * HP_THRESHOLD_PCTS[i]) / effMax or 0
  end
  positionHoverMarkers(hoverFrame.hpMarkers, hoverFrame.hpBar.bar)

  local woundCap = 1.0
  if state.wounds and state.wounds.hit10 then woundCap = 0.25
  elseif state.wounds and state.wounds.hit25 then woundCap = 0.50 end
  if woundCap >= 1.0 then
    hoverFrame.hpCapMarker:Hide()
  else
    hoverFrame.hpCapMarker.pct = (baseHp * woundCap) / effMax
    positionHoverMarkers({ hoverFrame.hpCapMarker }, hoverFrame.hpBar.bar)
  end

  hoverFrame.hpBar.frame:ClearAllPoints()
  hoverFrame.hpBar.frame:SetPoint("TOPLEFT", hoverFrame, "TOPLEFT", HOVER_PAD, -HOVER_PAD)

  -- Resource bars
  local profile  = getResProfile(state)
  local shownRes = 0

  for i = 1, 5 do
    local row = hoverFrame.resBars[i]
    local p   = profile[i]
    if row and p then
      local resKey, maxKey = getKeysForIdx(p.idx)
      local cur     = state[resKey] or 0
      local maxv    = state[maxKey] or 0
      local dispMax = maxv

      local isWarlockCorr = (state.classKey == "WARLOCK"      and p.idx == 2)
      local isShadowIns   = (state.classKey == "SHADOWPRIEST" and p.idx == 2)
      local isMageArcane  = (state.classKey == "MAGE"         and p.idx == 2)

      if isWarlockCorr then dispMax = 60
      elseif isShadowIns then dispMax = 25
      elseif isMageArcane then dispMax = 8 end
      if dispMax <= 0 then dispMax = 1 end

      local clamped = math.max(0, math.min(cur, dispMax))

      row.bar:SetMinMaxValues(0, dispMax)
      row.bar:SetValue(clamped)
      row.bar:SetStatusBarColor(p.r, p.g, p.b, 1)
      local lbl = p.label or "Ressource"
      row.label:SetText(string.format("%s : %d / %d", lbl, roundNumber(clamped), roundNumber(dispMax)))

      hideMarkers(row.markers)
      if isWarlockCorr then
        if #row.markers == 0 then
          row.markers[1] = makeMarker(row.bar, 10/60, 0.65, 0.95, 0.65, 0.55, 2)
          row.markers[2] = makeMarker(row.bar, 25/60, 1.00, 0.82, 0.22, 0.55, 2)
          row.markers[3] = makeMarker(row.bar, 45/60, 1.00, 0.25, 0.25, 0.65, 3)
        end
        positionHoverMarkers(row.markers, row.bar)
      elseif isShadowIns then
        if #row.markers == 0 then
          row.markers[1] = makeMarker(row.bar, 4/25,  0.65, 0.95, 0.65, 0.45, 2)
          row.markers[2] = makeMarker(row.bar, 12/25, 1.00, 0.82, 0.22, 0.55, 2)
          row.markers[3] = makeMarker(row.bar, 20/25, 1.00, 0.55, 0.10, 0.60, 2)
          row.markers[4] = makeMarker(row.bar, 25/25, 1.00, 0.25, 0.25, 0.70, 3)
        end
        positionHoverMarkers(row.markers, row.bar)
      elseif isMageArcane then
        if #row.markers == 0 then
          row.markers[1] = makeMarker(row.bar, 4/8, 1.00, 0.82, 0.22, 0.65, 2)
          row.markers[2] = makeMarker(row.bar, 8/8, 0.75, 0.30, 1.00, 0.80, 3)
        end
        positionHoverMarkers(row.markers, row.bar)
      end

      local yOff = -(HOVER_PAD + HOVER_BAR_H + HOVER_GAP + shownRes * (HOVER_BAR_H + HOVER_GAP))
      row.frame:ClearAllPoints()
      row.frame:SetPoint("TOPLEFT", hoverFrame, "TOPLEFT", HOVER_PAD, yOff)
      row.frame:Show()
      shownRes = shownRes + 1
    elseif row then
      row.frame:Hide()
      hideMarkers(row.markers)
    end
  end

  local totalH = HOVER_PAD * 2 + HOVER_BAR_H + shownRes * (HOVER_BAR_H + HOVER_GAP)
  hoverFrame:SetHeight(totalH)

  reanchorHover()
  hoverFrame:Show()
end

tryShowHover = function()
  local settings = getSettings()
  if settings.popupOnTarget == false then return end

  local unitName = getHoverUnitName()
  if not unitName then
    hideHoverPopup()
    return
  end

  local state = getCached(toCacheKey(unitName))

  -- Fallback for the local player: use ns.Core.state directly (never cached).
  if not state and UnitName then
    local playerName = UnitName("player")
    if playerName and namesMatch(unitName, playerName) then
      state = ns.Core and ns.Core.state
    end
  end

  if not state then
    -- Request state from the hovered player (mirrors OnTargetChanged), rate-limited.
    local key = toCacheKey(unitName)
    local now = GetTime and GetTime() or 0
    if key and not (pendingHoverUnit == key and (now - pendingHoverTime) < HOVER_REQUEST_COOLDOWN) then
      pendingHoverUnit = key
      pendingHoverTime = now
      if ns.Comm and ns.Comm.RequestState then
        ns.Comm:RequestState(unitName)
      end
    end
    hideHoverPopup()
    return
  end

  showHoverForState(state)
end

-- ============================================================

function ns.TargetPopup_Init()
  Popup:Initialize()
end
