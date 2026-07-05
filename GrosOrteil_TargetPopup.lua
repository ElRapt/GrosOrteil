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
local UnitIsUnit = rawget(_G, "UnitIsUnit")
local issecretvalue = rawget(_G, "issecretvalue")
local IsInRaid = rawget(_G, "IsInRaid")
local IsInGroup = rawget(_G, "IsInGroup")
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

-- Lazily build (once per row) and position the class-resource threshold
-- markers; defs come from Shared so all displays agree. `positionFn` differs
-- between the target popup (live bar width) and the hover (fixed width).
local function applyResMarkers(row, classKey, idx, positionFn)
  hideMarkers(row.markers)
  local defs = Shared.GetResMarkerDefs(classKey, idx)
  if #defs == 0 then return end
  if #row.markers == 0 then
    for i, d in ipairs(defs) do
      row.markers[i] = makeMarker(row.bar, d.pct, d.r, d.g, d.b, d.a, d.w)
    end
  end
  positionFn(row.markers, row.bar)
end

local pendingTarget
local pendingTargetIsPet = false
local pendingHoverUnit   -- cache key of the unit we last requested on hover
local pendingHoverTime   = 0
local arrivedCallbacks   = {}
local HOVER_REQUEST_COOLDOWN = 5  -- seconds between requests for the same unit
local popupFrame
local currentShownSender
local currentShownIsPet  = false

-- State cache: normalizedName → { state, t }
-- Allows instant popup display on re-target; fresh data still fetched in background.
local stateCache = {}
local CACHE_TTL  = 60  -- seconds
local CACHE_MAX  = 64  -- entry cap; oldest are dropped when exceeded

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
  -- Enforce a soft cap: drop the oldest entry when the cache grows past CACHE_MAX.
  local count = 0
  for _ in pairs(stateCache) do count = count + 1 end
  if count <= CACHE_MAX then return end
  local oldestKey, oldestT
  for k, v in pairs(stateCache) do
    if not oldestT or (v.t or 0) < oldestT then
      oldestKey, oldestT = k, v.t or 0
    end
  end
  if oldestKey then stateCache[oldestKey] = nil end
end

-- WoW can hand back "secret" values (unit names, GUIDs, tooltip text) when the
-- execution path is tainted by an addon; any compare/concat/string-op on one
-- raises "attempt to compare a secret string value". Treat secrets as absent.
local function isSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

-- nil unless v is a plain, non-empty, non-secret string.
local function usableString(v)
  if isSecret(v) then return nil end
  if type(v) ~= "string" or v == "" then return nil end
  return v
end

local function normalizeName(name)
  name = usableString(name)
  if not name then return nil end
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
    name, realm = usableString(name), usableString(realm)
    if name then
      if realm then
        return name .. "-" .. realm
      end
      return name
    end
  end

  local name, realm = UnitName(unit)
  name, realm = usableString(name), usableString(realm)
  if name then
    if realm then
      return name .. "-" .. realm
    end
    return name
  end

  return nil
end

local ownerScanTooltip

local function stripColorCodes(text)
  -- GetText() can return a secret string under taint; string ops on it raise.
  if isSecret(text) then return nil end
  if type(text) ~= "string" then return nil end
  -- Use string.gsub (global) instead of text:gsub (metatable) because WoW
  -- GetText() can return a 'secret string' that blocks metatable indexing under taint.
  local t = (string.gsub(text, "|c%x%x%x%x%x%x%x%x", ""))
  t = (string.gsub(t, "|r", ""))
  t = (string.gsub(t, "^%s+", ""))
  t = (string.gsub(t, "%s+$", ""))
  if t == "" then return nil end
  return t
end

local function extractOwnerNameFromTooltipText(text)
  local clean = stripColorCodes(text)
  if not clean then return nil end

  -- Common localized patterns for pet ownership.
  local owner = clean:match("^<(.+)'s Pet>$")
    or clean:match("^<Pet de (.+)>$")
    or clean:match("^Familier de (.+)$")
    or clean:match("^Compagnon de (.+)$")
  if not owner then return nil end
  owner = owner:gsub("^%s+", ""):gsub("%s+$", "")
  if owner == "" then return nil end
  return owner
end

local function resolveOwnerNameFromTooltip(unit)
  if not unit or not CreateFrame then return nil end
  if not ownerScanTooltip then
    ownerScanTooltip = CreateFrame("GameTooltip", "GrosOrteilOwnerScanTooltip", nil, "GameTooltipTemplate")
    ownerScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  end

  ownerScanTooltip:ClearLines()
  securecall(ownerScanTooltip.SetUnit, ownerScanTooltip, unit)

  for i = 2, 6 do
    local left = _G["GrosOrteilOwnerScanTooltipTextLeft" .. i]
    if left and left.GetText then
      local owner = extractOwnerNameFromTooltipText(left:GetText())
      if owner then return owner end
    end
  end
  return nil
end

local function resolveOwnerNameFromPetUnit(unit)
  if not unit or not UnitExists then return nil end
  if not UnitExists(unit) then return nil end

  -- Identity check via UnitIsUnit: pet GUIDs can be secret values under taint
  -- and comparing them with == raises. GUID equality is only the offline-test
  -- fallback (the harness has no UnitIsUnit), and skips secret GUIDs.
  local function ownerByUnit(ownerUnit)
    if not ownerUnit then return nil end
    local petUnit = ownerUnit .. "pet"
    if not UnitExists(petUnit) then return nil end
    if UnitIsUnit then
      if UnitIsUnit(petUnit, unit) then
        return unitTargetName(ownerUnit)
      end
      return nil
    end
    local a = UnitGUID and UnitGUID(petUnit)
    local b = UnitGUID and UnitGUID(unit)
    if a and b and not isSecret(a) and not isSecret(b) and a == b then
      return unitTargetName(ownerUnit)
    end
    return nil
  end

  local owner = ownerByUnit("player")
  if owner then return owner end

  if IsInRaid and IsInRaid() then
    for i = 1, 40 do
      owner = ownerByUnit("raid" .. i)
      if owner then return owner end
    end
  elseif IsInGroup and IsInGroup() then
    for i = 1, 4 do
      owner = ownerByUnit("party" .. i)
      if owner then return owner end
    end
  end

  return resolveOwnerNameFromTooltip(unit)
end

local function resolveStateNameForUnit(unit)
  if not unit or not UnitExists or not UnitExists(unit) then return nil end
  if UnitIsPlayer and UnitIsPlayer(unit) then
    return unitTargetName(unit)
  end
  return resolveOwnerNameFromPetUnit(unit)
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
    -- A secret GUID would blow up inside LibRPNames; better to look up by name only.
    if isSecret(guid) then guid = nil end
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
    if popupFrame.fadeOut and popupFrame:IsShown() and not popupFrame.fadeOut:IsPlaying() then
      popupFrame.fadeOut:Play()
    else
      popupFrame:Hide()
    end
  end
  currentShownSender = nil
  currentShownIsPet  = false
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

  local bf = Shared.MakeBarFrame(holder, 304, 20)
  bf.frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -14)

  local sheen = bf.bar:CreateTexture(nil, "OVERLAY")
  sheen:SetTexture("Interface\\Buttons\\WHITE8x8")
  sheen:SetVertexColor(1, 1, 1, 0.10)
  sheen:SetPoint("TOPLEFT", bf.bar, "TOPLEFT", 0, 0)
  sheen:SetPoint("TOPRIGHT", bf.bar, "TOPRIGHT", 0, 0)
  sheen:SetHeight(10)

  return { holder = holder, topText = topText, frame = bf.frame, bar = bf.bar, markers = {} }
end

local function updateHpShieldOverlays(row, hpNow, maxHp, blockValue, magicValue)
  if not row or not row.bar then return end
  Shared.UpdateHpShieldOverlays(
    row.blockOverlay, row.magicOverlay, row.bar,
    hpNow, maxHp, blockValue, magicValue, 304
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
  Shared.SetClassEmblem(popupFrame.classIcon, classKey)
  popupFrame.classIcon:Show()
end

-- Tint the header accent stripe: class color for players, warm orange for pets.
local function applyHeaderAccent(classKey, isPet)
  if not popupFrame or not popupFrame.headerAccent then return end
  local r, g, b = 1.00, 0.675, 0.125
  if isPet then
    r, g, b = 0.95, 0.62, 0.18
  else
    local style = Shared.CLASS_STYLES and Shared.CLASS_STYLES[classKey]
    if style then r, g, b = style.r, style.g, style.b end
  end
  popupFrame.headerAccent:SetVertexColor(r, g, b, 0.90)
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

  -- Dark tooltip-note skin, matching the cards pinned on the boards.
  Shared.ApplyNoteSkin(popupFrame, 0.96)
  popupFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -56, 220)

  -- Header plaque band with a gold underline and a class-colored accent.
  popupFrame.header = popupFrame:CreateTexture(nil, "BORDER")
  popupFrame.header:SetTexture("Interface\\Buttons\\WHITE8x8")
  popupFrame.header:SetVertexColor(0.10, 0.075, 0.05, 0.92)
  popupFrame.header:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 10, -10)
  popupFrame.header:SetPoint("TOPRIGHT", popupFrame, "TOPRIGHT", -10, -10)
  popupFrame.header:SetHeight(46)

  popupFrame.headerLine = popupFrame:CreateTexture(nil, "BORDER", nil, 1)
  popupFrame.headerLine:SetTexture("Interface\\Buttons\\WHITE8x8")
  popupFrame.headerLine:SetVertexColor(1.00, 0.675, 0.125, 0.35)
  popupFrame.headerLine:SetPoint("TOPLEFT",  popupFrame.header, "BOTTOMLEFT",  0, 0)
  popupFrame.headerLine:SetPoint("TOPRIGHT", popupFrame.header, "BOTTOMRIGHT", 0, 0)
  popupFrame.headerLine:SetHeight(1)

  popupFrame.headerAccent = popupFrame:CreateTexture(nil, "BORDER", nil, 1)
  popupFrame.headerAccent:SetTexture("Interface\\Buttons\\WHITE8x8")
  popupFrame.headerAccent:SetVertexColor(1.00, 0.675, 0.125, 0.90)
  popupFrame.headerAccent:SetPoint("TOPLEFT",    popupFrame.header, "TOPLEFT",    0, 0)
  popupFrame.headerAccent:SetPoint("BOTTOMLEFT", popupFrame.header, "BOTTOMLEFT", 0, 0)
  popupFrame.headerAccent:SetWidth(3)

  popupFrame.title = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  popupFrame.title:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 22, -22)
  popupFrame.title:SetJustifyH("LEFT")
  popupFrame.title:SetText("Inconnu")

  popupFrame.classText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  popupFrame.classText:SetPoint("TOPLEFT", popupFrame.title, "BOTTOMLEFT", 0, -3)
  popupFrame.classText:SetJustifyH("LEFT")
  popupFrame.classText:SetText("Classe : Inconnue")

  -- 2x2 stat grid: col1 X=18, col2 X=170; row1 Y=-60, row2 Y=-92
  popupFrame.armorIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.armorIcon:SetSize(14, 14)
  popupFrame.armorIcon:SetTexture("Interface\\Icons\\INV_Shield_06")
  popupFrame.armorIcon:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, -60)

  popupFrame.armorText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.armorText:SetPoint("LEFT", popupFrame.armorIcon, "RIGHT", 4, 0)
  popupFrame.armorText:SetJustifyH("LEFT")
  popupFrame.armorText:SetText("Armure : 0")

  popupFrame.dodgeIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.dodgeIcon:SetSize(14, 14)
  popupFrame.dodgeIcon:SetTexture("Interface\\Icons\\Ability_Rogue_Sprint")
  popupFrame.dodgeIcon:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 170, -60)

  popupFrame.dodgeText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.dodgeText:SetPoint("LEFT", popupFrame.dodgeIcon, "RIGHT", 4, 0)
  popupFrame.dodgeText:SetJustifyH("LEFT")
  popupFrame.dodgeText:SetText("Esquive : 0")

  -- Attaque (row 1: combined or C-C)
  popupFrame.attaqueIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.attaqueIcon:SetSize(14, 14)
  popupFrame.attaqueIcon:SetTexture("Interface\\Icons\\INV_Sword_04")
  popupFrame.attaqueIcon:Hide()

  popupFrame.attaqueText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.attaqueText:SetPoint("LEFT", popupFrame.attaqueIcon, "RIGHT", 4, 0)
  popupFrame.attaqueText:SetJustifyH("LEFT")
  popupFrame.attaqueText:Hide()

  -- Perception (right side of attaque row)
  popupFrame.perceptionIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.perceptionIcon:SetSize(14, 14)
  popupFrame.perceptionIcon:SetTexture("Interface\\Icons\\Spell_Nature_Sleep")
  popupFrame.perceptionIcon:Hide()

  popupFrame.perceptionText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.perceptionText:SetPoint("LEFT", popupFrame.perceptionIcon, "RIGHT", 4, 0)
  popupFrame.perceptionText:SetJustifyH("LEFT")
  popupFrame.perceptionText:Hide()

  -- Points de Chance: distinct compact bar (gold theme, segmented per point) with clover icon.
  -- Built smaller than resource bars to avoid being mistaken for a resource.
  popupFrame.chanceHolder = CreateFrame("Frame", nil, popupFrame)
  popupFrame.chanceHolder:SetSize(304, 18)
  popupFrame.chanceHolder:Hide()

  popupFrame.chanceIcon = popupFrame.chanceHolder:CreateTexture(nil, "ARTWORK")
  popupFrame.chanceIcon:SetSize(16, 16)
  popupFrame.chanceIcon:SetTexture("Interface\\Icons\\inv12_ability_rogue_rollthebones_jackpot")
  popupFrame.chanceIcon:SetPoint("LEFT", popupFrame.chanceHolder, "LEFT", 0, 0)

  local chanceBarFrame = CreateFrame("Frame", nil, popupFrame.chanceHolder, "BackdropTemplate")
  chanceBarFrame:SetPoint("LEFT", popupFrame.chanceIcon, "RIGHT", 6, 0)
  chanceBarFrame:SetPoint("RIGHT", popupFrame.chanceHolder, "RIGHT", 0, 0)
  chanceBarFrame:SetHeight(12)
  chanceBarFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  chanceBarFrame:SetBackdropColor(0.05, 0.04, 0.02, 0.95)
  chanceBarFrame:SetBackdropBorderColor(0.85, 0.65, 0.18, 0.85)
  popupFrame.chanceBarFrame = chanceBarFrame

  local chanceBar = CreateFrame("StatusBar", nil, chanceBarFrame)
  chanceBar:SetPoint("TOPLEFT", chanceBarFrame, "TOPLEFT", 1, -1)
  chanceBar:SetPoint("BOTTOMRIGHT", chanceBarFrame, "BOTTOMRIGHT", -1, 1)
  chanceBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
  chanceBar:SetStatusBarColor(0.95, 0.78, 0.20, 1)
  chanceBar:SetMinMaxValues(0, 1)
  chanceBar:SetValue(0)
  popupFrame.chanceBar = chanceBar

  -- Subtle shimmer overlay to set it apart from flat resource bars.
  local chanceSheen = chanceBar:CreateTexture(nil, "OVERLAY")
  chanceSheen:SetTexture("Interface\\Buttons\\WHITE8x8")
  chanceSheen:SetVertexColor(1, 1, 1, 0.18)
  chanceSheen:SetPoint("TOPLEFT", chanceBar, "TOPLEFT", 0, 0)
  chanceSheen:SetPoint("TOPRIGHT", chanceBar, "TOPRIGHT", 0, 0)
  chanceSheen:SetHeight(5)

  popupFrame.chanceText = popupFrame.chanceHolder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.chanceText:SetPoint("CENTER", chanceBarFrame, "CENTER", 0, 0)
  popupFrame.chanceText:SetTextColor(1, 0.96, 0.82, 1)
  popupFrame.chanceText:SetShadowOffset(1, -1)
  popupFrame.chanceText:SetShadowColor(0, 0, 0, 0.95)

  -- Pre-create up to 20 segment dividers to mark each integer point boundary.
  -- 2px wide and high-contrast so they clearly separate pips.
  popupFrame.chanceSegments = {}
  for i = 1, 20 do
    local seg = chanceBar:CreateTexture(nil, "OVERLAY")
    seg:SetTexture("Interface\\Buttons\\WHITE8x8")
    seg:SetColorTexture(0, 0, 0, 0.90)
    seg:SetWidth(2)
    seg:SetPoint("TOP",    chanceBar, "TOP",    0, 1)
    seg:SetPoint("BOTTOM", chanceBar, "BOTTOM", 0, -1)
    seg:Hide()
    popupFrame.chanceSegments[i] = seg
  end

  -- Discrete pips (round indicator gems): the readable display for the usual
  -- small pools. One gem per point — lit gold when available, grey when spent.
  -- The bar above stays as fallback for pools larger than 12.
  popupFrame.chancePips = {}
  for i = 1, 12 do
    local pip = popupFrame.chanceHolder:CreateTexture(nil, "ARTWORK")
    pip:SetSize(15, 15)
    pip:Hide()
    popupFrame.chancePips[i] = pip
  end

  -- Round class-hall crest (transparent background, crisp at any size).
  popupFrame.classIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.classIcon:SetSize(34, 34)
  popupFrame.classIcon:SetPoint("TOPRIGHT", popupFrame, "TOPRIGHT", -24, -20)

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
  popupFrame.petArmorText:SetText("Armure : 0")
  popupFrame.petArmorText:Hide()

  popupFrame.petDodgeIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.petDodgeIcon:SetSize(14, 14)
  popupFrame.petDodgeIcon:SetTexture("Interface\\Icons\\Ability_Rogue_Sprint")
  popupFrame.petDodgeIcon:SetPoint("LEFT", popupFrame.petArmorText, "RIGHT", 18, 0)
  popupFrame.petDodgeIcon:Hide()

  popupFrame.petDodgeText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.petDodgeText:SetPoint("LEFT", popupFrame.petDodgeIcon, "RIGHT", 4, 0)
  popupFrame.petDodgeText:SetJustifyH("LEFT")
  popupFrame.petDodgeText:SetText("Esquive : 0")
  popupFrame.petDodgeText:Hide()

  popupFrame.petAttaqueIcon = popupFrame:CreateTexture(nil, "ARTWORK")
  popupFrame.petAttaqueIcon:SetSize(14, 14)
  popupFrame.petAttaqueIcon:SetTexture("Interface\\Icons\\INV_Sword_04")
  popupFrame.petAttaqueIcon:Hide()

  popupFrame.petAttaqueText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.petAttaqueText:SetPoint("LEFT", popupFrame.petAttaqueIcon, "RIGHT", 4, 0)
  popupFrame.petAttaqueText:SetJustifyH("LEFT")
  popupFrame.petAttaqueText:SetText("CaC : 0 | Dist : 0")
  popupFrame.petAttaqueText:Hide()

  popupFrame.petHpRow = createStatBar(popupFrame, -316)
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

  popupFrame.petHpMarkers, popupFrame.petHpCapMarker =
    Shared.MakeHpThresholdMarkers(popupFrame.petHpRow.bar)

  popupFrame.petTempArmorText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.petTempArmorText:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, -352)
  popupFrame.petTempArmorText:SetJustifyH("LEFT")
  popupFrame.petTempArmorText:SetText("Arm. temp. : 0")
  popupFrame.petTempArmorText:Hide()

  popupFrame.petMagicShieldText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popupFrame.petMagicShieldText:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, -366)
  popupFrame.petMagicShieldText:SetJustifyH("LEFT")
  popupFrame.petMagicShieldText:SetText("Boucl. : 0/0 (+0 arm.)")
  popupFrame.petMagicShieldText:Hide()

  popupFrame.hpMarkers, popupFrame.hpCapMarker =
    Shared.MakeHpThresholdMarkers(popupFrame.hpRow.bar)

  popupFrame.closeButton = CreateFrame("Button", nil, popupFrame, "UIPanelCloseButton")
  popupFrame.closeButton:SetPoint("TOPRIGHT", popupFrame, "TOPRIGHT", -3, -2)
  popupFrame.closeButton:SetScript("OnClick", hidePopup)

  -- Stabilisé/Agonie banner (shown only when HP == 0); agonie pulses.
  popupFrame.statusBanner = popupFrame:CreateFontString(nil, "OVERLAY")
  popupFrame.statusBanner:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
  popupFrame.statusBanner:SetPoint("TOPRIGHT", popupFrame, "TOPRIGHT", -36, -22)
  popupFrame.statusBanner:SetJustifyH("RIGHT")
  popupFrame.statusBanner:SetShadowOffset(1, -1)
  popupFrame.statusBanner:SetShadowColor(0, 0, 0, 1)
  popupFrame.statusBanner:Hide()
  popupFrame.statusPulse = Shared.MakePulse(popupFrame.statusBanner)

  -- Gentle fade-in when the popup first opens (not on in-place refreshes),
  -- and fade-out when it closes.
  popupFrame.fadeIn  = Shared.MakeFadeIn(popupFrame, 0.15)
  popupFrame.fadeOut = Shared.MakeFadeOut(popupFrame, 0.15)

  -- Resize grip (drag = rescale, right-click = default), persisted in settings.
  if Shared.AttachScaleGrip then
    Shared.AttachScaleGrip(popupFrame, {
      load = function() return getSettings().popupScale end,
      save = function(s) getSettings().popupScale = s end,
    })
  end
end

local function applyPopupTitle(rpName, rpColor)
  if rpColor and type(rpColor) == "string" and rpColor:match("^%x%x%x%x%x%x%x%x$") then
    popupFrame.title:SetText("|c" .. rpColor .. rpName .. "|r")
  else
    popupFrame.title:SetText(rpName)
  end
end

local function showForState(targetName, state, petOnly)
  createPopup()
  -- Cancel a pending close fade (e.g. retarget during the fade).
  if popupFrame.fadeOut and popupFrame.fadeOut:IsPlaying() then
    popupFrame.fadeOut:Stop()
  end
  local wasShown = popupFrame:IsShown()
  currentShownSender = targetName

  -- Resolve petOnly: if the pet unit is disabled, suppress the popup entirely.
  if petOnly then
    local pet = type(state.pet) == "table" and state.pet
    if not pet or not pet.enabled then
      hidePopup()
      return
    end
  end
  currentShownIsPet = petOnly and true or false

  if petOnly then
    local pet = state.pet
    local petName = (type(pet.name) == "string" and pet.name ~= "") and pet.name or "Familier"
    popupFrame.title:SetText(petName)
    popupFrame.classText:SetText("Familier")
    applyClassIcon(nil)
    applyHeaderAccent(nil, true)

    local petArmor     = tonumber(pet.armor)     or 0
    local petTrueArmor = tonumber(pet.trueArmor) or 0
    local petDodge     = tonumber(pet.dodge)     or 0
    local petMaxHp     = math.max(1, tonumber(pet.maxHp) or 1)
    local petHp        = tonumber(pet.hp)        or 0

    popupFrame.armorText:SetText(string.format("Armure : %d (+%d)", roundNumber(petArmor), roundNumber(petTrueArmor)))
    popupFrame.dodgeText:SetText(string.format("Esquive : %d", roundNumber(petDodge)))

    setBarValue(popupFrame.hpRow, "PV", petHp, petMaxHp, { 0.95, 0.62, 0.18 })
    updateHpShieldOverlays(popupFrame.hpRow, petHp, petMaxHp, 0, (pet.magicShield and pet.magicShield.hp or 0))

    local HP_THRESHOLD_PCTS = { 0.50, 0.25, 0.10 }
    for i = 1, #popupFrame.hpMarkers do
      popupFrame.hpMarkers[i].pct = HP_THRESHOLD_PCTS[i]
    end
    positionMarkers(popupFrame.hpMarkers, popupFrame.hpRow.bar)

    local petWoundCap = Shared.WoundCap(pet.wounds)
    if petWoundCap >= 1.0 then
      popupFrame.hpCapMarker:Hide()
    else
      popupFrame.hpCapMarker.pct = petWoundCap
      positionMarkers({ popupFrame.hpCapMarker }, popupFrame.hpRow.bar)
    end

    for i = 1, 5 do
      local row = popupFrame.resRows[i]
      if row then row.holder:Hide(); hideMarkers(row.markers) end
    end

    -- Attaque row (same Y=-92 as owner layout; HP bar shifts down to -114)
    local petAttM = tonumber(pet.attaqueMelee)    or 0
    local petAttD = tonumber(pet.attaqueDistance) or 0
    popupFrame.attaqueIcon:ClearAllPoints()
    popupFrame.attaqueIcon:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, -92)
    popupFrame.attaqueText:SetText(string.format("CaC : %d | Dist : %d", roundNumber(petAttM), roundNumber(petAttD)))
    popupFrame.attaqueIcon:Show()
    popupFrame.attaqueText:Show()
    popupFrame.perceptionIcon:Hide()
    popupFrame.perceptionText:Hide()
    popupFrame.chanceHolder:Hide()

    -- hpRow shifted down 22px to make room for the attaque row.
    popupFrame.hpRow.holder:ClearAllPoints()
    popupFrame.hpRow.holder:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, -114)

    popupFrame.petNameText:Hide()
    popupFrame.petArmorIcon:Hide()
    popupFrame.petArmorText:Hide()
    popupFrame.petDodgeIcon:Hide()
    popupFrame.petDodgeText:Hide()
    if popupFrame.petAttaqueIcon     then popupFrame.petAttaqueIcon:Hide()     end
    if popupFrame.petAttaqueText     then popupFrame.petAttaqueText:Hide()     end
    if popupFrame.petTempArmorText   then popupFrame.petTempArmorText:Hide()   end
    if popupFrame.petMagicShieldText then popupFrame.petMagicShieldText:Hide() end
    popupFrame.petHpRow.holder:Hide()
    hideMarkers(popupFrame.petHpMarkers)
    if popupFrame.petHpCapMarker then popupFrame.petHpCapMarker:Hide() end
    hideOverlay(popupFrame.petHpRow.blockOverlay)
    hideOverlay(popupFrame.petHpRow.magicOverlay)
    if popupFrame.statusBanner then
      if popupFrame.statusPulse then popupFrame.statusPulse:Stop() end
      popupFrame.statusBanner:Hide()
    end

    local dynamicHeight = 162
    if dynamicHeight < 180 then dynamicHeight = 180 end
    popupFrame:SetHeight(dynamicHeight)
    popupFrame:Show()
    if not wasShown and popupFrame.fadeIn then popupFrame.fadeIn:Play() end
    return
  end

  -- Owner-only view: RP name + owner stats, pet section always suppressed.

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
  popupFrame.classText:SetText("Classe : " .. className)
  applyClassIcon(state.classKey)
  applyHeaderAccent(state.classKey, false)

  local armor = tonumber(state.armor) or 0
  local trueArmor = tonumber(state.trueArmor) or 0
  local dodge = tonumber(state.dodge) or 0
  popupFrame.armorText:SetText(string.format("Armure : %d (+%d)", roundNumber(armor), roundNumber(trueArmor)))
  popupFrame.dodgeText:SetText(string.format("Esquive : %d", roundNumber(dodge)))

  -- Attaque / Perception / Chance
  local attM  = tonumber(state.attaqueMelee)    or 0
  local attD  = tonumber(state.attaqueDistance) or 0
  local perc  = tonumber(state.perception)      or 0
  local chCur = tonumber(state.chance)          or 0
  local chMax = tonumber(state.maxChance)       or 0

  -- Attaque row at Y=-92: C-C and Dist on one line; Perception on right side
  popupFrame.attaqueIcon:ClearAllPoints()
  popupFrame.attaqueIcon:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, -92)
  popupFrame.attaqueText:SetText(string.format("CaC : %d | Dist : %d", roundNumber(attM), roundNumber(attD)))
  popupFrame.attaqueIcon:Show()
  popupFrame.attaqueText:Show()

  popupFrame.perceptionIcon:ClearAllPoints()
  popupFrame.perceptionIcon:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 170, -92)
  popupFrame.perceptionText:SetText(string.format("Perception : %d", roundNumber(perc)))
  popupFrame.perceptionIcon:Show()
  popupFrame.perceptionText:Show()

  -- HP bar shifted down 22px to make room for attaque/perception row
  popupFrame.hpRow.holder:ClearAllPoints()
  popupFrame.hpRow.holder:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, -114)

  -- Chance bar below HP bar (hp holder 34px, bottom at -148, 4px gap)
  popupFrame.chanceHolder:ClearAllPoints()
  popupFrame.chanceHolder:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, -152)
  do
    local maxv = chMax > 0 and chMax or 1
    local cur  = chCur < 0 and 0 or chCur
    if cur > maxv then cur = maxv end

    -- Small pools (the usual case) render as one gem per point; bigger pools
    -- fall back to the segmented bar.
    local usePips = chMax >= 1 and chMax <= 12
    if usePips then
      popupFrame.chanceBarFrame:Hide()
      for i = 1, #popupFrame.chancePips do
        local pip = popupFrame.chancePips[i]
        if i <= chMax then
          pip:SetTexture(i <= cur
            and "Interface\\COMMON\\Indicator-Yellow"
            or  "Interface\\COMMON\\Indicator-Gray")
          pip:ClearAllPoints()
          pip:SetPoint("LEFT", popupFrame.chanceIcon, "RIGHT", 8 + (i - 1) * 17, 0)
          pip:Show()
        else
          pip:Hide()
        end
      end
      popupFrame.chanceText:ClearAllPoints()
      popupFrame.chanceText:SetPoint("RIGHT", popupFrame.chanceHolder, "RIGHT", 0, 0)
      popupFrame.chanceText:SetText(string.format("%d / %d", roundNumber(cur), roundNumber(chMax)))
    else
      for i = 1, #popupFrame.chancePips do popupFrame.chancePips[i]:Hide() end
      popupFrame.chanceBarFrame:Show()
      popupFrame.chanceBar:SetMinMaxValues(0, maxv)
      popupFrame.chanceBar:SetValue(cur)
      popupFrame.chanceText:ClearAllPoints()
      popupFrame.chanceText:SetPoint("CENTER", popupFrame.chanceBarFrame, "CENTER", 0, 0)
      popupFrame.chanceText:SetText(string.format("PC : %d / %d", roundNumber(chCur), roundNumber(chMax)))

      -- Position segment dividers at integer boundaries when 2..20 points.
      local segCount = math.min(20, math.max(0, maxv - 1))
      local barWidth = popupFrame.chanceBar:GetWidth() or 0
      if barWidth <= 0 then barWidth = 280 end
      for i = 1, #popupFrame.chanceSegments do
        local seg = popupFrame.chanceSegments[i]
        if i <= segCount and maxv > 1 then
          seg:ClearAllPoints()
          seg:SetPoint("TOP", popupFrame.chanceBar, "TOPLEFT", math.floor(barWidth * (i / maxv)), 0)
          seg:SetPoint("BOTTOM", popupFrame.chanceBar, "BOTTOMLEFT", math.floor(barWidth * (i / maxv)), 0)
          seg:Show()
        else
          seg:Hide()
        end
      end
    end
  end
  popupFrame.chanceHolder:Show()

  -- Reposition resource rows (chance holder 18px + 4px gap = 22px: -152-22=-174)
  for i = 1, 5 do
    local row = popupFrame.resRows[i]
    if row then
      row.holder:ClearAllPoints()
      row.holder:SetPoint("TOPLEFT", popupFrame, "TOPLEFT", 18, -174 - (i - 1) * 34)
    end
  end

  local effMaxHp = tonumber(state.maxHp) or 0
  if effMaxHp <= 0 then effMaxHp = 1 end

  -- Stabilisé/Agonie banner ("EN AGONIE" pulses softly)
  if popupFrame.statusBanner then
    local isDead = (tonumber(state.hp) or 0) == 0
    if isDead then
      if state.stabilise then
        popupFrame.statusBanner:SetText("|cff44ee44** STABILISE **|r")
        if popupFrame.statusPulse then popupFrame.statusPulse:Stop() end
      else
        popupFrame.statusBanner:SetText("|cffee2222** EN AGONIE **|r")
        if popupFrame.statusPulse and not popupFrame.statusPulse:IsPlaying() then
          popupFrame.statusPulse:Play()
        end
      end
      popupFrame.statusBanner:Show()
    else
      if popupFrame.statusPulse then popupFrame.statusPulse:Stop() end
      popupFrame.statusBanner:Hide()
    end
  end

  setBarValue(popupFrame.hpRow, "PV", state.hp, effMaxHp, { 0.85, 0.16, 0.18 })
  updateHpShieldOverlays(
    popupFrame.hpRow,
    tonumber(state.hp) or 0,
    effMaxHp,
    tonumber(state.tempBlock) or 0,
    (state.magicShield and state.magicShield.hp or 0)
  )

  local HP_THRESHOLD_PCTS = { 0.50, 0.25, 0.10 }
  for i = 1, #popupFrame.hpMarkers do
    local m = popupFrame.hpMarkers[i]
    m.pct = (HP_THRESHOLD_PCTS[i] or 0)
  end
  positionMarkers(popupFrame.hpMarkers, popupFrame.hpRow.bar)

  local woundCap = Shared.WoundCap(state.wounds)
  if woundCap >= 1.0 then
    popupFrame.hpCapMarker:Hide()
  else
    popupFrame.hpCapMarker.pct = woundCap
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
      local displayMax = Shared.GetResDisplayMax(state.classKey, p.idx) or maxv

      setBarValue(row, p.label or "Ressource", cur, displayMax, { p.r, p.g, p.b })
      applyResMarkers(row, state.classKey, p.idx, positionMarkers)

      row.holder:Show()
      shownRes = shownRes + 1
    elseif row then
      row.holder:Hide()
      hideMarkers(row.markers)
    end
  end

  local dynamicHeight = 188 + (shownRes * 34)

  -- Pet section is only shown when targeting the pet unit directly (petOnly path above).
  popupFrame.petNameText:Hide()
  popupFrame.petArmorIcon:Hide()
  popupFrame.petArmorText:Hide()
  popupFrame.petDodgeIcon:Hide()
  popupFrame.petDodgeText:Hide()
  if popupFrame.petAttaqueIcon    then popupFrame.petAttaqueIcon:Hide()    end
  if popupFrame.petAttaqueText    then popupFrame.petAttaqueText:Hide()    end
  popupFrame.petHpRow.holder:Hide()
  hideMarkers(popupFrame.petHpMarkers)
  if popupFrame.petHpCapMarker then popupFrame.petHpCapMarker:Hide() end
  hideOverlay(popupFrame.petHpRow.blockOverlay)
  hideOverlay(popupFrame.petHpRow.magicOverlay)
  if popupFrame.petTempArmorText   then popupFrame.petTempArmorText:Hide()   end
  if popupFrame.petMagicShieldText then popupFrame.petMagicShieldText:Hide() end

  if dynamicHeight < 188 then dynamicHeight = 188 end
  popupFrame:SetHeight(dynamicHeight)

  popupFrame:Show()
  if not wasShown and popupFrame.fadeIn then popupFrame.fadeIn:Play() end
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

  for _, cb in ipairs(arrivedCallbacks) do
    xpcall(cb, geterrorhandler(), sender, state)
  end

  -- Refresh hover popup if it is showing for this sender, or try to show it
  -- if the user is currently hovering this unit (state just became available).
  if tryShowHover then tryShowHover() end

  -- If popup is already showing for this sender, refresh it in-place.
  local shownKey = normalizeName(currentShownSender)
  if popupFrame and popupFrame:IsShown() and shownKey and namesMatch(senderKey, shownKey) then
    showForState(sender, state, currentShownIsPet)
    pendingTarget = nil
    return
  end

  local targetKey = normalizeName(unitTargetName("target"))
  local pendingKey = normalizeName(pendingTarget)

  if targetKey and namesMatch(senderKey, targetKey) then
    local settings = getSettings()
    if settings.popupOnTarget ~= false then
      showForState(sender, state, pendingTargetIsPet)
    end
    pendingTarget = nil
    pendingTargetIsPet = false
    return
  end

  if pendingKey and namesMatch(senderKey, pendingKey) then
    local settings = getSettings()
    if settings.popupOnTarget ~= false then
      showForState(sender, state, pendingTargetIsPet)
    end
    pendingTarget = nil
    pendingTargetIsPet = false
  end
end

function Popup:OnTargetChanged()
  local _ = self
  if popupFrame and popupFrame:IsShown() then
    hidePopup()
  end
  pendingTarget = nil
  pendingTargetIsPet = false

  local settings = getSettings()
  if settings.popupOnTarget == false then
    return
  end

  if not UnitExists("target") then
    return
  end

  local isPet = not (UnitIsPlayer and UnitIsPlayer("target"))
  local targetName = resolveStateNameForUnit("target")
  if not targetName then
    return
  end

  pendingTargetIsPet = isPet

  -- Show cached state instantly; fresh data will arrive and refresh via OnStateReceived.
  local cached = getCached(toCacheKey(targetName))
  if cached then
    showForState(targetName, cached, isPet)
  else
    -- No cache: wait for the network response before showing.
    pendingTarget = targetName
    if C_Timer and C_Timer.After then
      C_Timer.After(5, function()
        if pendingTarget and normalizeName(pendingTarget) == normalizeName(targetName) then
          pendingTarget = nil
          pendingTargetIsPet = false
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
    local hoverPending = false
    hooksecurefunc(gt, "SetUnit", function()
      if hoverPending then return end
      hoverPending = true
      if C_Timer then
        C_Timer.After(0, function()
          hoverPending = false
          if tryShowHover then tryShowHover() end
        end)
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

  -- Refresh the popup title the moment TRP3 receives a profile update for
  -- anyone, instead of relying only on the 2s deferred retry. Cheap: a single
  -- name lookup, only while the popup is visible.
  local function hookTRP3Register()
    local api = rawget(_G, "TRP3_API")
    local addon = rawget(_G, "TRP3_Addon")
    if type(api) ~= "table" or type(api.RegisterCallback) ~= "function" then return false end
    if type(addon) ~= "table" then return false end
    pcall(api.RegisterCallback, addon, "REGISTER_DATA_UPDATED", function()
      if popupFrame and popupFrame:IsShown() and currentShownSender and not currentShownIsPet then
        local lrn = rawget(_G, "LibRPNames")
        if lrn and lrn.ClearCache then lrn.ClearCache() end
        local newName, newColor = getRPDisplayName(currentShownSender)
        applyPopupTitle(newName, newColor)
      end
    end)
    return true
  end
  if not hookTRP3Register() and C_Timer and C_Timer.After then
    C_Timer.After(2, hookTRP3Register)  -- TRP3 may finish loading after us
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
  local bf = Shared.MakeBarFrame(parent, HOVER_BAR_W, HOVER_BAR_H)

  local label = bf.bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetAllPoints(bf.bar)
  label:SetJustifyH("CENTER")
  label:SetJustifyV("MIDDLE")
  label:SetText("")

  return { frame = bf.frame, bar = bf.bar, label = label, markers = {} }
end

local function createHoverPopup()
  if hoverFrame then return end

  hoverFrame = CreateFrame("Frame", "GrosOrteilHoverPopup", UIParent, "BackdropTemplate")
  hoverFrame:SetFrameStrata("TOOLTIP")
  hoverFrame:SetFrameLevel(10)
  hoverFrame:SetWidth(HOVER_BAR_W + HOVER_PAD * 2)
  hoverFrame:SetHeight(HOVER_PAD * 2 + HOVER_BAR_H)
  -- Same dark tooltip-note skin as the rest of the addon.
  Shared.ApplyNoteSkin(hoverFrame, 0.94)

  -- Quick fade-in when the hover first appears (not on refreshes), and
  -- fade-out when the mouse leaves.
  hoverFrame.fadeIn  = Shared.MakeFadeIn(hoverFrame, 0.12)
  hoverFrame.fadeOut = Shared.MakeFadeOut(hoverFrame, 0.12)

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

  hoverFrame.hpMarkers, hoverFrame.hpCapMarker =
    Shared.MakeHpThresholdMarkers(hoverFrame.hpBar.bar)

  -- Resource bars (up to 5, shown/hidden dynamically)
  hoverFrame.resBars = {}
  for i = 1, 5 do
    local rb = createHoverBar(hoverFrame)
    rb.frame:Hide()
    hoverFrame.resBars[i] = rb
  end

  -- PC bar (gold, shown only when maxChance > 0)
  hoverFrame.chanceBar = createHoverBar(hoverFrame)
  hoverFrame.chanceBar.frame:Hide()

  -- Stabilisé/Agonie status label (shown below HP bar when HP == 0)
  hoverFrame.statusLabel = hoverFrame:CreateFontString(nil, "OVERLAY")
  hoverFrame.statusLabel:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
  hoverFrame.statusLabel:SetShadowOffset(1, -1)
  hoverFrame.statusLabel:SetShadowColor(0, 0, 0, 1)
  hoverFrame.statusLabel:SetJustifyH("CENTER")
  hoverFrame.statusLabel:Hide()
  hoverFrame.statusPulse = Shared.MakePulse(hoverFrame.statusLabel)

  hoverFrame:Hide()
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
  if not hoverFrame then return end
  if hoverFrame.fadeOut and hoverFrame:IsShown() and not hoverFrame.fadeOut:IsPlaying() then
    hoverFrame.fadeOut:Play()
  else
    hoverFrame:Hide()
  end
end

-- Public: subscribe to incoming states. Returns an unsubscribe function.
function Popup.OnStateArrived(fn)
  table.insert(arrivedCallbacks, fn)
  return function()
    for i, cb in ipairs(arrivedCallbacks) do
      if cb == fn then table.remove(arrivedCallbacks, i); break end
    end
  end
end

-- Public: read cache by display name (for RaidPanel.Refresh).
function Popup.GetCachedState(name)
  return getCached(toCacheKey(name))
end

-- Public: write cache by display name (cache-priming primitive; used by tests).
function Popup.InjectState(name, state)
  setCached(toCacheKey(name), state)
end

-- Public: best available display name (TRP3/RP name if known, else the
-- character name). Guarded so a missing/erroring RP lib never breaks callers.
function Popup.GetRPDisplayName(name)
  if type(name) ~= "string" or name == "" then return name end
  local ok, rp = pcall(getRPDisplayName, name)
  if ok and type(rp) == "string" and rp ~= "" then return rp end
  return name
end

local function showHoverForState(state, petOnly)
  if petOnly then
    local pet = type(state.pet) == "table" and state.pet
    if not pet or not pet.enabled then
      hideHoverPopup()
      return
    end
  end
  createHoverPopup()
  -- Cancel a pending fade so a quick re-hover lands at full opacity.
  if hoverFrame.fadeOut and hoverFrame.fadeOut:IsPlaying() then
    hoverFrame.fadeOut:Stop()
  end
  local wasShown = hoverFrame:IsShown()

  if petOnly then
    local pet = state.pet
    local petMaxHp = math.max(1, tonumber(pet.maxHp) or 1)
    local petHp    = tonumber(pet.hp) or 0
    local hpClamp  = math.max(0, math.min(petHp, petMaxHp))

    hoverFrame.hpBar.bar:SetMinMaxValues(0, petMaxHp)
    hoverFrame.hpBar.bar:SetValue(hpClamp)
    hoverFrame.hpBar.bar:SetStatusBarColor(0.95, 0.62, 0.18, 1)
    hoverFrame.hpBar.label:SetText(string.format("PV : %d / %d", roundNumber(petHp), roundNumber(petMaxHp)))

    local petMs = type(pet.magicShield) == "table" and pet.magicShield or {}
    Shared.UpdateHpShieldOverlays(
      hoverFrame.hpBar.blockOverlay, hoverFrame.hpBar.magicOverlay,
      hoverFrame.hpBar.bar, petHp, petMaxHp, 0, tonumber(petMs.hp) or 0, HOVER_BAR_W
    )

    local HP_THRESHOLD_PCTS = { 0.50, 0.25, 0.10 }
    for i = 1, #hoverFrame.hpMarkers do
      hoverFrame.hpMarkers[i].pct = HP_THRESHOLD_PCTS[i]
    end
    positionHoverMarkers(hoverFrame.hpMarkers, hoverFrame.hpBar.bar)

    local petWoundCap = Shared.WoundCap(pet.wounds)
    if petWoundCap >= 1.0 then
      hoverFrame.hpCapMarker:Hide()
    else
      hoverFrame.hpCapMarker.pct = petWoundCap
      positionHoverMarkers({ hoverFrame.hpCapMarker }, hoverFrame.hpBar.bar)
    end

    for i = 1, 5 do
      local rb = hoverFrame.resBars[i]
      if rb then rb.frame:Hide(); hideMarkers(rb.markers) end
    end
    if hoverFrame.chanceBar then hoverFrame.chanceBar.frame:Hide() end
    if hoverFrame.statusLabel then
      if hoverFrame.statusPulse then hoverFrame.statusPulse:Stop() end
      hoverFrame.statusLabel:Hide()
    end

    hoverFrame.hpBar.frame:ClearAllPoints()
    hoverFrame.hpBar.frame:SetPoint("TOPLEFT", hoverFrame, "TOPLEFT", HOVER_PAD, -HOVER_PAD)
    hoverFrame:SetHeight(HOVER_PAD * 2 + HOVER_BAR_H)
    reanchorHover()
    hoverFrame:Show()
    if not wasShown and hoverFrame.fadeIn then hoverFrame.fadeIn:Play() end
    return
  end

  -- Owner-only hover: HP bar + resources, no pet section.

  -- HP bar
  local effMax  = tonumber(state.maxHp) or 0
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
    tonumber(state.tempBlock) or 0, (state.magicShield and state.magicShield.hp or 0), HOVER_BAR_W
  )

  local HP_THRESHOLD_PCTS = { 0.50, 0.25, 0.10 }
  for i = 1, #hoverFrame.hpMarkers do
    local m = hoverFrame.hpMarkers[i]
    m.pct = HP_THRESHOLD_PCTS[i] or 0
  end
  positionHoverMarkers(hoverFrame.hpMarkers, hoverFrame.hpBar.bar)

  local woundCap = Shared.WoundCap(state.wounds)
  if woundCap >= 1.0 then
    hoverFrame.hpCapMarker:Hide()
  else
    hoverFrame.hpCapMarker.pct = woundCap
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
      local dispMax = Shared.GetResDisplayMax(state.classKey, p.idx) or maxv
      if dispMax <= 0 then dispMax = 1 end

      local clamped = math.max(0, math.min(cur, dispMax))

      row.bar:SetMinMaxValues(0, dispMax)
      row.bar:SetValue(clamped)
      row.bar:SetStatusBarColor(p.r, p.g, p.b, 1)
      local lbl = p.label or "Ressource"
      row.label:SetText(string.format("%s : %d / %d", lbl, roundNumber(clamped), roundNumber(dispMax)))

      applyResMarkers(row, state.classKey, p.idx, positionHoverMarkers)

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

  -- PC bar (gold, below resources, only when maxChance > 0)
  local chCur = tonumber(state.chance) or 0
  local chMax = tonumber(state.maxChance) or 0
  local showChance = chMax > 0
  if showChance and hoverFrame.chanceBar then
    local cb = hoverFrame.chanceBar
    cb.bar:SetMinMaxValues(0, chMax)
    cb.bar:SetValue(math.min(chCur, chMax))
    cb.bar:SetStatusBarColor(0.95, 0.78, 0.20, 1)
    cb.label:SetText(string.format("PC : %d / %d", roundNumber(chCur), roundNumber(chMax)))
    local yOff = -(HOVER_PAD + HOVER_BAR_H + HOVER_GAP + shownRes * (HOVER_BAR_H + HOVER_GAP) + HOVER_GAP)
    cb.frame:ClearAllPoints()
    cb.frame:SetPoint("TOPLEFT", hoverFrame, "TOPLEFT", HOVER_PAD, yOff)
    cb.frame:Show()
  elseif hoverFrame.chanceBar then
    hoverFrame.chanceBar.frame:Hide()
  end

  local extraRows = showChance and 1 or 0

  -- Stabilisé/Agonie status label when HP == 0
  local showStatus = (tonumber(state.hp) or 0) == 0
  local STATUS_H = 16
  if showStatus and hoverFrame.statusLabel then
    local yOff = -(HOVER_PAD + HOVER_BAR_H + HOVER_GAP
      + shownRes * (HOVER_BAR_H + HOVER_GAP)
      + (showChance and (HOVER_BAR_H + HOVER_GAP + HOVER_GAP) or 0)
      + HOVER_GAP)
    hoverFrame.statusLabel:ClearAllPoints()
    hoverFrame.statusLabel:SetPoint("TOPLEFT",  hoverFrame, "TOPLEFT",  HOVER_PAD, yOff)
    hoverFrame.statusLabel:SetPoint("TOPRIGHT", hoverFrame, "TOPRIGHT", -HOVER_PAD, yOff)
    if state.stabilise then
      hoverFrame.statusLabel:SetText("|cff44ee44** STABILISE **|r")
      if hoverFrame.statusPulse then hoverFrame.statusPulse:Stop() end
    else
      hoverFrame.statusLabel:SetText("|cffee2222** EN AGONIE **|r")
      if hoverFrame.statusPulse and not hoverFrame.statusPulse:IsPlaying() then
        hoverFrame.statusPulse:Play()
      end
    end
    hoverFrame.statusLabel:Show()
  elseif hoverFrame.statusLabel then
    if hoverFrame.statusPulse then hoverFrame.statusPulse:Stop() end
    hoverFrame.statusLabel:Hide()
  end

  local totalH = HOVER_PAD * 2 + HOVER_BAR_H
    + shownRes * (HOVER_BAR_H + HOVER_GAP)
    + extraRows * (HOVER_BAR_H + HOVER_GAP)
    + (showStatus and (STATUS_H + HOVER_GAP * 2) or 0)
  hoverFrame:SetHeight(totalH)

  reanchorHover()
  hoverFrame:Show()
  if not wasShown and hoverFrame.fadeIn then hoverFrame.fadeIn:Play() end
end

tryShowHover = function()
  local settings = getSettings()
  if settings.popupOnTarget == false then return end

  -- Resolve hovered unit name and detect whether it is a pet.
  local unitName, isPet
  if UnitExists("mouseover") then
    unitName = resolveStateNameForUnit("mouseover")
    if unitName then
      isPet = not (UnitIsPlayer and UnitIsPlayer("mouseover"))
    end
  end
  if not unitName then
    local gt = rawget(_G, "GameTooltip")
    if gt and gt.GetUnit then
      -- GetUnit returns (name, unitToken); either can be a secret value under
      -- taint. Prefer the token, fall back to the name, drop secrets.
      local tipName, tipUnit = gt:GetUnit()
      local unit = usableString(tipUnit) or usableString(tipName)
      if unit and UnitExists(unit) then
        unitName = resolveStateNameForUnit(unit)
        if unitName then
          isPet = not (UnitIsPlayer and UnitIsPlayer(unit))
        end
      end
    end
  end

  if not unitName then
    hideHoverPopup()
    return
  end

  local cacheKey = toCacheKey(unitName)
  local state = getCached(cacheKey)

  -- Fallback for the local player: use ns.Core.state directly (never cached).
  if not state and UnitName then
    local playerName = UnitName("player")
    if playerName and namesMatch(unitName, playerName) then
      state = ns.Core and ns.Core.state
    end
  end

  -- Always fire a background refresh (rate-limited), whether or not we have
  -- a cached state. This keeps the hover up to date when hovering for more
  -- than HOVER_REQUEST_COOLDOWN seconds, or when cached data is stale.
  local now = GetTime and GetTime() or 0
  if cacheKey and not (pendingHoverUnit == cacheKey and (now - pendingHoverTime) < HOVER_REQUEST_COOLDOWN) then
    pendingHoverUnit = cacheKey
    pendingHoverTime = now
    if ns.Comm and ns.Comm.RequestState then
      ns.Comm:RequestState(unitName)
    end
  end

  if not state then
    hideHoverPopup()
    return
  end

  showHoverForState(state, isPet)
end

-- ============================================================

-- Test-only handles: lets the offline test runner reach pure helpers
-- (name normalization, owner-tooltip parsing, cache primitives) without
-- relying on real WoW API surface. NOT for production use.
Popup._test = {
  normalizeName                  = normalizeName,
  splitNameRealm                 = splitNameRealm,
  toCacheKey                     = toCacheKey,
  namesMatch                     = namesMatch,
  stripColorCodes                = stripColorCodes,
  extractOwnerNameFromTooltipText = extractOwnerNameFromTooltipText,
  baseCharacterName              = baseCharacterName,
  senderToUnitID                 = senderToUnitID,
  getCached                      = getCached,
  setCached                      = setCached,
  cache                          = stateCache,
  CACHE_TTL                      = CACHE_TTL,
  CACHE_MAX                      = CACHE_MAX,
  arrivedCallbacks               = arrivedCallbacks,
}

function ns.TargetPopup_Init()
  Popup:Initialize()
end
