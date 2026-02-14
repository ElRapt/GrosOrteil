local _, ns = ...
local Core = ns.Core

local UI = {}
ns.UI = UI

local CLASS_STYLES = {
  MEDIC = { label = "Fournitures", r = 0.85, g = 0.12, b = 0.12 }, -- red
  PALADIN = { label = "Puissance sacrée", r = 1.0, g = 0.82, b = 0.22 }, -- gold
  PRIEST = { label = "Points de foi", r = 1.0, g = 1.0, b = 1.0 }, -- white
  SHADOWPRIEST = { label = "Points de foi et insanité", r = 0.60, g = 0.20, b = 0.85 }, -- violet
  MAGE = { label = "Mana", r = 0.20, g = 0.55, b = 1.00 }, -- blue
  ROGUE = { label = "Énergie", r = 1.00, g = 0.90, b = 0.10 }, -- yellow
  WARLOCK = { label = "Energie gangrénée et Corruption", r = 0.20, g = 0.85, b = 0.25 },
  DRUID = { label = "Esprit", r = 1.00, g = 0.55, b = 0.10 }, -- orange
  MONK = { label = "Chi", r = 0.55, g = 1.00, b = 0.55 }, -- light green
  SHAMAN = { label = "Points élémentaires", r = 0.00, g = 0.44, b = 0.87 },
}

local function getResProfile(classKey)
  -- Returns an array of { idx=1..4, label=string, r/g/b }
  if classKey == "WARRIOR" then
    return {}
  end
  if classKey == "MEDIC" then
    return {
      { idx = 1, label = "Fournitures", r = 0.85, g = 0.12, b = 0.12 },
    }
  end
  if classKey == "WARLOCK" then
    return {
      { idx = 1, label = "Energie gangrénée", r = 0.20, g = 0.85, b = 0.25 },
      { idx = 2, label = "Corruption", r = 0.55, g = 0.20, b = 0.85 },
    }
  elseif classKey == "SHADOWPRIEST" then
    return {
      { idx = 1, label = "Points de foi", r = 1.0, g = 1.0, b = 1.0 },
      { idx = 2, label = "Insanité", r = 0.60, g = 0.20, b = 0.85 },
    }
  elseif classKey == "SHAMAN" then
    return {
      { idx = 1, label = "Terre", r = 0.55, g = 0.35, b = 0.15 },
      { idx = 2, label = "Air", r = 0.60, g = 0.95, b = 0.95 },
      { idx = 3, label = "Eau", r = 0.20, g = 0.55, b = 1.00 },
      { idx = 4, label = "Feu", r = 1.00, g = 0.35, b = 0.10 },
    }
  end

  local s = (type(classKey) == "string" and CLASS_STYLES[classKey]) or nil
  if s then
    return { { idx = 1, label = s.label or "Ressource", r = s.r or 0.2, g = s.g or 0.55, b = s.b or 1.0 } }
  end
  return { { idx = 1, label = "Ressource", r = 0.20, g = 0.55, b = 1.00 } }
end

local function setClassIconTexCoords(tex, classKey)
  if not tex or not tex.SetTexCoord then return end

  -- Standard class icon sheet.
  -- https://wowpedia.fandom.com/wiki/CLASS_BUTTONS
  local coords = {
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

  local c = coords[classKey]
  if not c then
    tex:SetTexCoord(0, 1, 0, 1)
    return
  end
  tex:SetTexCoord(c[1], c[2], c[3], c[4])
end

local function roundPct(x)
  return math.floor(x * 100 + 0.5)
end

local function mkLabel(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function mkLabelCenter(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOP", x, y)
  fs:SetJustifyH("CENTER")
  fs:SetText(text)
  return fs
end

local function mkEdit(parent, w, h, x, y, onEnter)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(w, h)
  eb:SetPoint("TOPLEFT", x, y)
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onEnter then onEnter() end
  end)
  return eb
end

local function mkButton(parent, text, w, h, x, y, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
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
  bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  bar:SetStatusBarColor(r, g, b, 1)

  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  bg:SetTexture("Interface/Buttons/WHITE8x8")
  bg:SetColorTexture(0.08, 0.08, 0.08, 0.85)
  bar._bg = bg

  local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
  border:SetAllPoints(bar)
  border:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
  border:SetBackdropBorderColor(0, 0, 0, 0.9)
  bar._border = border
end

function ns.UI_Init()
  local db = GrosOrteilDB
  db.ui = db.ui or { point = "CENTER", x = 0, y = 0, shown = true }

  -- One-time UI migration: after widening the frame, recenter once.
  if not db.ui._migrated_20260214 then
    db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0
    db.ui._migrated_20260214 = true
  end

  if not db.ui._migrated_20260214_wide then
    db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0
    db.ui._migrated_20260214_wide = true
  end

  local FRAME_W, FRAME_H = 600, 340
  local BASE_FRAME_H = FRAME_H
  local PAD_X = 14
  local CONTENT_W = FRAME_W - (PAD_X * 2)

  local function centerX(rowWidth)
    return math.floor((CONTENT_W - rowWidth) / 2)
  end

  local frame = CreateFrame("Frame", "GrosOrteilFrame", UIParent, "BackdropTemplate")
  UI.frame = frame
  frame:SetSize(FRAME_W, FRAME_H)
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

  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.92)

  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 6, -6)
  bg:SetPoint("BOTTOMRIGHT", -6, 6)
  bg:SetTexture("Interface/Buttons/WHITE8x8")
  local setGrad = bg["SetGradientAlpha"]
  if type(setGrad) == "function" then
    setGrad(bg, "VERTICAL", 0.10, 0.10, 0.12, 0.90, 0.03, 0.03, 0.04, 0.92)
  else
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
  end
  frame._bg = bg

  local header = frame:CreateTexture(nil, "BACKGROUND")
  header:SetPoint("TOPLEFT", 6, -6)
  header:SetPoint("TOPRIGHT", -6, -6)
  header:SetHeight(26)
  header:SetTexture("Interface/Buttons/WHITE8x8")
  header:SetColorTexture(0.12, 0.12, 0.14, 0.70)
  frame._header = header

  local headerLine = frame:CreateTexture(nil, "ARTWORK")
  headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  headerLine:SetHeight(1)
  headerLine:SetTexture("Interface/Buttons/WHITE8x8")
  headerLine:SetColorTexture(0, 0, 0, 0.6)
  frame._headerLine = headerLine

  frame:SetPoint(db.ui.point, UIParent, db.ui.point, db.ui.x, db.ui.y)
  if db.ui.shown then frame:Show() else frame:Hide() end

  -- Titre
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -12)
  title:SetText("GrosOrteil — Treize du Treize")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  -- Barres
  local hpBar = CreateFrame("StatusBar", nil, frame)
  UI.hpBar = hpBar
  hpBar:SetSize(CONTENT_W, 20)
  hpBar:SetPoint("TOPLEFT", PAD_X, -34)
  hpBar:SetMinMaxValues(0, 1)
  hpBar:SetValue(1)
  skinBar(hpBar, 0.85, 0.12, 0.12) -- rouge

  local hpText = hpBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  UI.hpText = hpText
  hpText:SetPoint("CENTER")


  local blockOverlay = hpBar:CreateTexture(nil, "OVERLAY")
  UI.hpBlockOverlay = blockOverlay
  blockOverlay:SetTexture("Interface/Buttons/WHITE8x8")
  blockOverlay:SetColorTexture(0.65, 0.65, 0.65, 0.55)
  blockOverlay:SetPoint("TOP", hpBar, "TOP", 0, 0)
  blockOverlay:SetPoint("BOTTOM", hpBar, "BOTTOM", 0, 0)
  blockOverlay:Hide()

  local magicOverlay = hpBar:CreateTexture(nil, "OVERLAY")
  UI.hpMagicBlockOverlay = magicOverlay
  magicOverlay:SetTexture("Interface/Buttons/WHITE8x8")
  magicOverlay:SetColorTexture(1.0, 0.82, 0.22, 0.60) -- doré
  magicOverlay:SetPoint("TOP", hpBar, "TOP", 0, 0)
  magicOverlay:SetPoint("BOTTOM", hpBar, "BOTTOM", 0, 0)
  magicOverlay:Hide()

  -- Marqueurs 50/25/10%
  UI.hpMarkers = {}
  local function makeMarker(parent, pct)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface/Buttons/WHITE8x8")
    t:SetWidth(2)
    t:SetHeight(parent:GetHeight() or 20)
    t:SetColorTexture(1, 1, 1, 0.35)
    t.pct = pct
    return t
  end
  UI.hpMarkers[1] = makeMarker(hpBar, 0.50)
  UI.hpMarkers[2] = makeMarker(hpBar, 0.25)
  UI.hpMarkers[3] = makeMarker(hpBar, 0.10)
  UI.hpMarkers[2]:SetColorTexture(1.0, 0.65, 0.1, 0.45) -- 25% (orange)
  UI.hpMarkers[3]:SetColorTexture(1.0, 0.15, 0.15, 0.55) -- 10% (rouge)

  local capMarker = makeMarker(hpBar, 1.0)
  capMarker:SetWidth(3)
  capMarker:SetColorTexture(1.0, 0.9, 0.2, 0.7)
  capMarker:Hide()
  UI.hpCapMarker = capMarker

  local capText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  UI.capText = capText
  capText:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, -6)
  capText:SetText("")

  -- Ressource bars (up to 4, depending on selected class)
  UI.resBars = {}
  UI.resTexts = {}
  local RES_BAR_H = 14
  local RES_GAP = 4
  local RES_EXTRA_H = (RES_BAR_H + RES_GAP)

  local function mkResBar(idx)
    local bar = CreateFrame("StatusBar", nil, frame)
    UI.resBars[idx] = bar
    bar:SetSize(CONTENT_W, RES_BAR_H)
    if idx == 1 then
      bar:SetPoint("TOPLEFT", capText, "BOTTOMLEFT", 0, -8)
    else
      bar:SetPoint("TOPLEFT", UI.resBars[idx - 1], "BOTTOMLEFT", 0, -RES_GAP)
    end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    skinBar(bar, 0.2, 0.55, 1.0)
    bar:Hide()

    -- Optional stacked segments (used for Shaman: 4 elements in 1 bar)
    if idx == 1 then
      bar._stackSegs = {}
      for j = 1, 4 do
        local seg = bar:CreateTexture(nil, "OVERLAY")
        seg:SetTexture("Interface\\Buttons\\WHITE8x8")
        seg:SetVertexColor(1, 1, 1, 1)
        seg:Hide()
        bar._stackSegs[j] = seg
      end
    end

    local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.resTexts[idx] = txt
    txt:SetPoint("CENTER")
    return bar
  end

  for i = 1, 4 do
    mkResBar(i)
  end

  -- Warlock Corruption thresholds (max always 60)
  UI.corruptionMarkers = {}
  do
    local bar = UI.resBars[2]
    if bar then
      local function makeCorruptionMarker(val, r, g, b, a, w)
        local t = bar:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface/Buttons/WHITE8x8")
        t:SetWidth(w or 2)
        t:SetHeight(bar:GetHeight() or 14)
        t:SetColorTexture(r or 1, g or 1, b or 1, a or 0.45)
        t.pct = (val or 0) / 60
        t:Hide()
        return t
      end

      UI.corruptionMarkers[1] = makeCorruptionMarker(10, 0.65, 0.95, 0.65, 0.55, 2) -- passive
      UI.corruptionMarkers[2] = makeCorruptionMarker(25, 1.00, 0.82, 0.22, 0.55, 2) -- moyenne
      UI.corruptionMarkers[3] = makeCorruptionMarker(45, 1.00, 0.25, 0.25, 0.65, 3) -- strong
    end
  end

  -- Bars are driven by Core.OnChange; keep them hidden until then.

  -- Onglets
  local tabStrip = CreateFrame("Frame", nil, frame)
  tabStrip:SetPoint("TOPLEFT", UI.resBars[1], "BOTTOMLEFT", 0, -10)
  tabStrip:SetPoint("TOPRIGHT", UI.resBars[1], "BOTTOMRIGHT", 0, -10)
  tabStrip:SetHeight(24)
  UI.tabStrip = tabStrip

  local contentHost = CreateFrame("Frame", nil, frame)
  contentHost:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -10)

  -- Class selector strip at bottom
  local classStrip = CreateFrame("Frame", nil, frame)
  classStrip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD_X, 12)
  classStrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD_X, 12)
  classStrip:SetHeight(30)
  UI.classStrip = classStrip

  contentHost:SetPoint("BOTTOMRIGHT", classStrip, "TOPRIGHT", 0, 8)

  UI.tabs = {}
  UI.pages = {}

  local function setTab(active)
    for i = 1, #UI.pages do
      if i == active then UI.pages[i]:Show() else UI.pages[i]:Hide() end
    end
    for i = 1, #UI.tabs do
      local b = UI.tabs[i]
      if i == active then
        b:Disable()
        b:SetAlpha(1)
      else
        b:Enable()
        b:SetAlpha(0.85)
      end
    end
  end

  local TAB_GAP = 6

  local TAB_TEXTS = {
    "PV",
    "Ressource",
    "Armure/Bloc.",
    "Dégâts",
    "Soins",
  }

  local TAB_COUNT = #TAB_TEXTS
  local TAB_W = math.floor((CONTENT_W - (TAB_GAP * (TAB_COUNT - 1))) / TAB_COUNT)

  local function mkTab(text, idx)
    local tab = CreateFrame("Button", nil, tabStrip, "UIPanelButtonTemplate")
    tab:SetText(text)
    tab:SetScript("OnClick", function() setTab(idx) end)
    tab:SetHeight(22)
    tab:SetWidth(TAB_W)

    if idx == 1 then
      tab:SetPoint("TOPLEFT", tabStrip, "TOPLEFT", 0, 0)
    else
      tab:SetPoint("LEFT", UI.tabs[idx - 1], "RIGHT", TAB_GAP, 0)
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

  for i = 1, TAB_COUNT do
    mkTab(TAB_TEXTS[i], i)
  end

  local pageHP = mkPage()
  local pageRes = mkPage()
  local pageArmor = mkPage()
  local pageDmg = mkPage()
  local pageHeal = mkPage()

  -- Onglet 1 : PV
  local xHP = centerX(360)
  mkLabel(pageHP, "PV", xHP + 0, -6)
  local hpCur, hpMax
  mkLabel(pageHP, "/", xHP + 112, -6)
  local function applyHP()
    Core.SetHP(getNumber(hpCur), getNumber(hpMax))
  end
  hpCur = mkEdit(pageHP, 70, 20, xHP + 36, -4, applyHP)
  hpMax = mkEdit(pageHP, 70, 20, xHP + 126, -4, applyHP)
  mkButton(pageHP, "Appliquer", 90, 20, xHP + 210, -4, applyHP)

  local xTempHP = centerX(362)
  mkLabel(pageHP, "PV bonus", xTempHP + 0, -38)
  local tempHpEB
  local function applyTempHP()
    Core.SetBonusHP(getNumber(tempHpEB))
  end
  tempHpEB = mkEdit(pageHP, 70, 20, xTempHP + 120, -36, applyTempHP)
  mkButton(pageHP, "Appliquer", 90, 20, xTempHP + 206, -36, applyTempHP)

  -- Onglet 2 : Ressource
  local xRes = centerX(420)
  UI.resPageLabel = mkLabel(pageRes, "Ressource", xRes + 0, -6)

  UI.resDeltaLabel = mkLabel(pageRes, "Valeur (±)", xRes + 0, -34)
  local resDeltaEB = mkEdit(pageRes, 70, 20, xRes + 96, -32)
  UI.resDeltaEB = resDeltaEB

  UI.resRow = UI.resRow or {}
  UI.resRowLabel = UI.resRowLabel or {}
  UI.resRowCur = UI.resRowCur or {}
  UI.resRowMax = UI.resRowMax or {}

  local function mkResRow(idx, y)
    local row = CreateFrame("Frame", nil, pageRes)
    row:SetSize(540, 24)
    row:SetPoint("TOPLEFT", xRes, y)
    UI.resRow[idx] = row
    row:Hide()

    local label = mkLabel(row, "Ressource", 0, 0)
    UI.resRowLabel[idx] = label

    local curEB, maxEB
    mkLabel(row, "/", 172, 0)

    local function apply()
      if Core and Core.SetResIndex then
        Core.SetResIndex(idx, getNumber(curEB), getNumber(maxEB))
      else
        -- Backward compatibility (should not happen in this build)
        if idx == 1 and Core and Core.SetRes then
          Core.SetRes(getNumber(curEB), getNumber(maxEB))
        end
      end
    end

    curEB = mkEdit(row, 70, 20, 96, 2, apply)
    maxEB = mkEdit(row, 70, 20, 186, 2, apply)
    UI.resRowCur[idx] = curEB
    UI.resRowMax[idx] = maxEB

    mkButton(row, "Appliquer", 90, 20, 270, 2, apply)
    mkButton(row, "+", 28, 20, 368, 2, function()
      if Core and Core.AddResIndex then
        Core.AddResIndex(idx, getNumber(resDeltaEB) or 0)
      elseif idx == 1 and Core and Core.AddRes then
        Core.AddRes(getNumber(resDeltaEB) or 0)
      end
    end)
    mkButton(row, "-", 28, 20, 400, 2, function()
      if Core and Core.AddResIndex then
        Core.AddResIndex(idx, -(getNumber(resDeltaEB) or 0))
      elseif idx == 1 and Core and Core.AddRes then
        Core.AddRes(-(getNumber(resDeltaEB) or 0))
      end
    end)

    return row
  end

  -- Rows are shown/hidden based on selected class.
  mkResRow(1, -60)
  mkResRow(2, -88)
  mkResRow(3, -116)
  mkResRow(4, -144)

  UI.noResHint = mkLabelCenter(pageRes, "Aucune ressource pour cette classe.", 0, -110)
  UI.noResHint:Hide()

  -- Resource is always active (no enable/disable toggle)

  -- Onglet 2 : Armure & Blocage
  local xArmor = centerX(554)
  mkLabel(pageArmor, "Armure", xArmor + 0, -6)
  local armorEB, trueArmorEB, dodgeEB
  mkLabel(pageArmor, "Armure invul", xArmor + 150, -6)
  mkLabel(pageArmor, "Esquive", xArmor + 330, -6)
  local function applyArmor()
    -- IMPORTANT: on lit les valeurs AVANT d'appeler des setters,
    -- sinon le 1er setter déclenche un refresh UI qui peut écraser les EditBox.
    local armorVal = getNumber(armorEB)
    local trueArmorVal = getNumber(trueArmorEB)
    local dodgeVal = getNumber(dodgeEB)

    Core.SetArmor(armorVal, trueArmorVal)
    Core.SetDodge(dodgeVal)
  end
  armorEB = mkEdit(pageArmor, 70, 20, xArmor + 56, -4, applyArmor)
  trueArmorEB = mkEdit(pageArmor, 70, 20, xArmor + 238, -4, applyArmor)
  dodgeEB = mkEdit(pageArmor, 70, 20, xArmor + 386, -4, applyArmor)
  mkButton(pageArmor, "Appliquer", 90, 20, xArmor + 464, -4, applyArmor)

  local xBlock = centerX(362)
  mkLabel(pageArmor, "Blocage (temp.)", xBlock + 0, -70)
  local blockEB, magicBlockEB
  mkLabel(pageArmor, "Blocage magique (temp.)", xBlock + 0, -102)
  local function applyBlocks()
    -- Même problème que l'armure : on lit avant d'appeler les setters.
    local blockVal = getNumber(blockEB)
    local magicVal = getNumber(magicBlockEB)
    Core.SetTempBlock(blockVal)
    Core.SetTempMagicBlock(magicVal)
  end
  blockEB = mkEdit(pageArmor, 70, 20, xBlock + 120, -68, applyBlocks)
  magicBlockEB = mkEdit(pageArmor, 70, 20, xBlock + 180, -100, applyBlocks)
  mkButton(pageArmor, "Appliquer", 90, 20, xBlock + 206, -68, applyBlocks)
  mkButton(pageArmor, "Réinit.", 70, 20, xBlock + 302, -68, function() Core.ResetTempBlock() end)
  mkButton(pageArmor, "Réinit.", 70, 20, xBlock + 302, -100, function() Core.ResetTempMagicBlock() end)

  -- Onglet 3 : Dégâts
  local xValD = centerX(180)
  mkLabel(pageDmg, "Valeur", xValD + 0, -6)
  local dmgValEB

  local xDmgBtns = centerX(392)
  local function doDmgArmor()
    Core.DamageWithArmor(getNumber(dmgValEB) or 0)
  end
  local function doDmgTrue()
    Core.DamageTrue(getNumber(dmgValEB) or 0)
  end
  dmgValEB = mkEdit(pageDmg, 80, 20, xValD + 56, -4, doDmgArmor)
  mkButton(pageDmg, "Dégâts (armure)", 190, 22, xDmgBtns + 0, -36, doDmgArmor)
  mkButton(pageDmg, "Dégâts (bruts)", 190, 22, xDmgBtns + 202, -36, doDmgTrue)

  -- Onglet 4 : Soins
  local xValH = centerX(180)
  mkLabel(pageHeal, "Valeur", xValH + 0, -6)
  local healValEB

  local xHealBtns = centerX(392)
  local function doHeal()
    Core.Heal(getNumber(healValEB) or 0)
  end
  healValEB = mkEdit(pageHeal, 80, 20, xValH + 56, -4, doHeal)
  mkButton(pageHeal, "Soins", 190, 22, xHealBtns + 0, -36, doHeal)
  mkButton(pageHeal, "Soins divins (75%)", 190, 22, xHealBtns + 202, -36, function()
    Core.DivineHeal()
  end)

  UI.inputs = {
    hpCur = hpCur, hpMax = hpMax,
    tempHp = tempHpEB,
    resCur = UI.resRowCur[1], resMax = UI.resRowMax[1],
    armor = armorEB, trueArmor = trueArmorEB,
    dodge = dodgeEB,
    block = blockEB,
    magicBlock = magicBlockEB,
  }

  setTab(1)

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

  local function mkClassButton(idx, classKey)
    local b = CreateFrame("Button", nil, classStrip, "BackdropTemplate")
    b:SetSize(26, 26)
    b.classKey = classKey
    b:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
    b:SetBackdropBorderColor(0, 0, 0, 0.85)

    local GAP = 6
    local rowW = (#CLASS_KEYS * 26) + ((#CLASS_KEYS - 1) * GAP)
    local startX = math.floor((CONTENT_W - rowW) / 2)
    if idx == 1 then
      b:SetPoint("LEFT", classStrip, "LEFT", startX, 0)
    else
      b:SetPoint("LEFT", (UI.classButtons[idx - 1] --[[@as Frame]]), "RIGHT", GAP, 0)
    end

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.tex = tex

    if classKey == "MEDIC" then
      -- First aid / medical supplies icon
      tex:SetTexture("Interface\\Icons\\INV_Misc_Bandage_15")
      tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    elseif classKey == "SHADOWPRIEST" then
      tex:SetTexture("Interface\\Icons\\Spell_Shadow_Shadowform")
      tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    else
      tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
      setClassIconTexCoords(tex, classKey)
    end

    b:SetScript("OnClick", function()
      if Core and Core.SetClassKey then
        Core.SetClassKey(classKey)
      end
      setTab(2)
    end)

    UI.classButtons[idx] = b
    return b
  end

  for i = 1, #CLASS_KEYS do
    mkClassButton(i, CLASS_KEYS[i])
  end

  Core.OnChange(function(s)
    local baseMaxHp = (s.maxHp or 0)
    local bonusHp = math.max(0, s.bonusHp or 0)
    local effMaxHp = baseMaxHp + bonusHp
    local hpNow = (s.hp or 0)

    local hpPct = (effMaxHp > 0) and (hpNow / effMaxHp) or 0
    hpBar:SetValue(math.max(0, math.min(1, hpPct)))

    if bonusHp > 0 then
      hpText:SetText(string.format("PV : %d / %d (+%d bonus, %d%%)", hpNow, effMaxHp, bonusHp, roundPct(hpPct)))
    else
      hpText:SetText(string.format("PV : %d / %d (%d%%)", s.hp or 0, baseMaxHp, roundPct(hpPct)))
    end

    -- Overlays Blocage (gris) + Blocage magique (doré)
    do
      local maxHp = effMaxHp
      local wBar = hpBar:GetWidth() or 0
      local hpForOverlay = math.max(0, hpNow)

      local block = math.max(0, s.tempBlock or 0)
      local magic = math.max(0, s.tempMagicBlock or 0)
      local total = math.min(hpForOverlay, block + magic)

      local function hideOverlay(tex)
        if not tex then return end
        tex:Hide()
        tex:SetAlpha(0)
        tex:SetWidth(0.001)
      end

      if maxHp <= 0 or wBar <= 0 or total <= 0 then
        hideOverlay(UI.hpBlockOverlay)
        hideOverlay(UI.hpMagicBlockOverlay)
      else
        local hpFrac = hpForOverlay / maxHp
        if hpFrac < 0 then hpFrac = 0 elseif hpFrac > 1 then hpFrac = 1 end
        local endX = wBar * hpFrac

        -- On met le blocage magique au plus près du "bout" des PV,
        -- puis le blocage normal juste à gauche (pas de chevauchement).
        local magicShown = math.min(magic, total)
        local blockShown = math.min(block, total - magicShown)

        local magicW = wBar * (magicShown / maxHp)
        local blockW = wBar * (blockShown / maxHp)

        -- Magic (doré)
        if UI.hpMagicBlockOverlay and magicW > 0.5 and endX > 0.5 then
          UI.hpMagicBlockOverlay:Show()
          UI.hpMagicBlockOverlay:SetAlpha(0.75)
          UI.hpMagicBlockOverlay:ClearAllPoints()
          UI.hpMagicBlockOverlay:SetPoint("TOPLEFT", hpBar, "TOPLEFT", math.max(0, endX - magicW), 0)
          UI.hpMagicBlockOverlay:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", math.max(0, endX - magicW), 0)
          UI.hpMagicBlockOverlay:SetWidth(magicW)
        else
          hideOverlay(UI.hpMagicBlockOverlay)
        end

        -- Block (gris) à gauche du magic
        if UI.hpBlockOverlay and blockW > 0.5 and endX > 0.5 then
          local startX = math.max(0, endX - magicW - blockW)
          UI.hpBlockOverlay:Show()
          UI.hpBlockOverlay:SetAlpha(0.65)
          UI.hpBlockOverlay:ClearAllPoints()
          UI.hpBlockOverlay:SetPoint("TOPLEFT", hpBar, "TOPLEFT", startX, 0)
          UI.hpBlockOverlay:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", startX, 0)
          UI.hpBlockOverlay:SetWidth(blockW)
        else
          hideOverlay(UI.hpBlockOverlay)
        end
      end
    end

    local w = hpBar:GetWidth() or 0
    for i = 1, #UI.hpMarkers do
      local m = UI.hpMarkers[i]
      local pct = (m.pct or 0)
      -- Threshold value is based on base max HP only.
      -- The bar range may include bonus HP, so convert base-threshold to a fraction of effMax.
      local thresholdHp = baseMaxHp * pct
      local x = (effMaxHp > 0) and (w * (thresholdHp / effMaxHp)) or 0
      if x < 0 then x = 0 elseif x > w then x = w end
      m:ClearAllPoints()
      m:SetPoint("LEFT", hpBar, "LEFT", x, 0)
    end

    local cap
    local w2 = s.wounds
    if w2 and w2.hit10 then cap = 0.25
    elseif w2 and w2.hit25 then cap = 0.50
    else cap = 1.0 end

    -- Ligne de plafond (sur la barre PV)
    if UI.hpCapMarker then
      if cap >= 0.999 then
        UI.hpCapMarker:Hide()
      else
        UI.hpCapMarker:Show()
        -- Core.Heal() caps at (baseMax*cap). Bonus HP does not extend the cap.
        local capHp = (baseMaxHp * cap)
        local xCap = (effMaxHp > 0) and (w * (capHp / effMaxHp)) or 0
        if xCap < 0 then xCap = 0 elseif xCap > w then xCap = w end
        UI.hpCapMarker:ClearAllPoints()
        UI.hpCapMarker:SetPoint("LEFT", hpBar, "LEFT", xCap, 0)
      end
    end

    if cap >= 0.999 then
      capText:SetText("")
    else
      capText:SetText(string.format("Plafond de soins : %d%%", roundPct(cap)))
    end

    -- Ressource
    local profile = getResProfile(s.classKey)
    local rowCount = #profile
    local barCount
    if s.classKey == "SHAMAN" then
      barCount = (rowCount > 0) and 1 or 0
    else
      barCount = rowCount
    end

    if UI.resPageLabel and UI.resPageLabel.SetText then
      local headerText
      if rowCount == 0 then
        headerText = "Aucune ressource"
      else
        headerText = (CLASS_STYLES[s.classKey] and CLASS_STYLES[s.classKey].label) or "Ressource"
      end
      UI.resPageLabel:SetText(headerText)
    end

    if UI.noResHint then
      if rowCount == 0 then UI.noResHint:Show() else UI.noResHint:Hide() end
    end
    if UI.resDeltaLabel then
      if rowCount == 0 then UI.resDeltaLabel:Hide() else UI.resDeltaLabel:Show() end
    end
    if UI.resDeltaEB then
      if rowCount == 0 then UI.resDeltaEB:Hide() else UI.resDeltaEB:Show() end
    end

    -- Move tabs under the last active resource bar.
    do
      local n = barCount
      if n < 0 then n = 0 end
      if n > 4 then n = 4 end

      local anchor = capText
      if n >= 1 and UI.resBars and UI.resBars[n] then
        anchor = UI.resBars[n]
      end

      -- Grow the window when multiple resource bars are visible (Shaman = 4).
      if frame and frame.SetHeight then
        local extraPad = 0
        if s.classKey == "SHAMAN" then
          extraPad = 70
        elseif n >= 4 then
          extraPad = 26
        end
        local targetH = BASE_FRAME_H + (math.max(0, n - 1) * RES_EXTRA_H) + extraPad
        if targetH < BASE_FRAME_H then targetH = BASE_FRAME_H end
        frame:SetHeight(targetH)
      end

      if UI.tabStrip and UI.tabStrip.ClearAllPoints then
        UI.tabStrip:ClearAllPoints()
        UI.tabStrip:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
        UI.tabStrip:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -10)
      end
    end

    local function getKeysForIdx(i)
      if i == 1 then return "res", "maxRes" end
      if i == 2 then return "res2", "maxRes2" end
      if i == 3 then return "res3", "maxRes3" end
      if i == 4 then return "res4", "maxRes4" end
      return nil, nil
    end

    -- Default: hide warlock corruption markers; they'll be re-shown when applicable.
    if UI.corruptionMarkers then
      for j = 1, #UI.corruptionMarkers do
        local m = UI.corruptionMarkers[j]
        if m then m:Hide() end
      end
    end

    for i = 1, 4 do
      local bar = UI.resBars and UI.resBars[i]
      local txt = UI.resTexts and UI.resTexts[i]
      local row = UI.resRow and UI.resRow[i]
      local rowLabel = UI.resRowLabel and UI.resRowLabel[i]
      local curEB = UI.resRowCur and UI.resRowCur[i]
      local maxEB = UI.resRowMax and UI.resRowMax[i]

      -- Shaman: display 4 resources in 1 stacked bar, but keep 4 edit rows.
      if s.classKey == "SHAMAN" then
        local p = profile[i]
        -- Bars: only use bar #1.
        if i ~= 1 then
          if bar then bar:Hide() end
          if txt then txt:SetText("") end
        end

        -- Rows: show/hide and bind each element.
        if not p then
          if row then row:Hide() end
        else
          local resKey, maxKey = getKeysForIdx(p.idx)
          local cur = s[resKey] or 0
          local maxv = s[maxKey] or 0
          if row then row:Show() end
          if rowLabel and rowLabel.SetText then rowLabel:SetText(p.label or "Ressource") end
          if curEB then setNumber(curEB, cur) end
          if maxEB then setNumber(maxEB, maxv) end
        end

        -- After the loop's first iteration, update the stacked bar visuals.
        if i == 1 and bar and bar._stackSegs then
          bar:Show()

          local totalMax = 0
          local totalCur = 0
          for j = 1, 4 do
            local pj = profile[j]
            if pj then
              local rk, mk = getKeysForIdx(pj.idx)
              local curJ = s[rk] or 0
              local maxJ = s[mk] or 0
              if maxJ > 0 and curJ > maxJ then curJ = maxJ end
              if curJ < 0 then curJ = 0 end
              totalCur = totalCur + curJ
              totalMax = totalMax + maxJ
            end
          end

          local pct = (totalMax > 0) and (totalCur / totalMax) or 0
          bar:SetValue(math.max(0, math.min(1, pct)))
          -- Hide base fill; segments provide the color.
          bar:SetStatusBarColor(0, 0, 0, 0)

          local wBar = bar:GetWidth() or 0
          local x = 0
          for j = 1, 4 do
            local seg = bar._stackSegs[j]
            local pj = profile[j]
            if seg and pj and totalMax > 0 and wBar > 0 then
              local rk, mk = getKeysForIdx(pj.idx)
              local curJ = s[rk] or 0
              local maxJ = s[mk] or 0
              if maxJ > 0 and curJ > maxJ then curJ = maxJ end
              if curJ < 0 then curJ = 0 end
              local segW = wBar * (curJ / totalMax)
              if segW > 0.5 then
                seg:Show()
                seg:SetVertexColor(pj.r, pj.g, pj.b, 0.95)
                seg:ClearAllPoints()
                seg:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
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
            txt:SetText(string.format(
              "Points élémentaires : %d / %d (%d%%)",
              totalCur,
              totalMax,
              roundPct(pct)
            ))
          end
        end

      else
        -- Default behavior: 1 bar per resource.
        local p = profile[i]
        if not p then
          if bar then bar:Hide() end
          if row then row:Hide() end
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

          local isWarlockCorruption = (s.classKey == "WARLOCK" and p.idx == 2)
          if isWarlockCorruption then
            maxv = 60
            if cur < 0 then cur = 0 elseif cur > 60 then cur = 60 end
          end
          local pct = (maxv and maxv > 0) and (cur / maxv) or 0

          if bar then
            bar:Show()
            bar:SetStatusBarColor(p.r, p.g, p.b, 1)
            bar:SetValue(math.max(0, math.min(1, pct)))
          end
          if txt then
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
            else
              txt:SetText(string.format("%s : %d / %d (%d%%)", p.label or "Ressource", cur, maxv, roundPct(pct)))
            end
          end

          -- Corruption threshold markers (10/25/45 out of 60)
          if UI.corruptionMarkers then
            if isWarlockCorruption and bar and (bar.GetWidth and (bar:GetWidth() or 0) > 0) then
              local wBar = bar:GetWidth() or 0
              for j = 1, #UI.corruptionMarkers do
                local m = UI.corruptionMarkers[j]
                if m then
                  m:Show()
                  local x = wBar * (m.pct or 0)
                  if x < 0 then x = 0 elseif x > wBar then x = wBar end
                  m:ClearAllPoints()
                  m:SetPoint("LEFT", bar, "LEFT", x, 0)
                end
              end
            else
              for j = 1, #UI.corruptionMarkers do
                local m = UI.corruptionMarkers[j]
                if m then m:Hide() end
              end
            end
          end

          if row then row:Show() end
          if rowLabel and rowLabel.SetText then rowLabel:SetText(p.label or "Ressource") end
          if curEB then setNumber(curEB, cur) end
          if maxEB then setNumber(maxEB, maxv) end

          -- Warlock corruption max is fixed; prevent editing the max box.
          if maxEB then
            if isWarlockCorruption then
              if maxEB.Disable then maxEB:Disable()
              elseif maxEB.EnableMouse then maxEB:EnableMouse(false) end
              if maxEB.SetAlpha then maxEB:SetAlpha(0.55) end
            else
              if maxEB.Enable then maxEB:Enable()
              elseif maxEB.EnableMouse then maxEB:EnableMouse(true) end
              if maxEB.SetAlpha then maxEB:SetAlpha(1) end
            end
          end
        end
      end
    end

    if UI.classButtons then
      for i = 1, #UI.classButtons do
        local b = UI.classButtons[i]
        if b and b.classKey then
          if b.classKey == s.classKey then
            b:SetAlpha(1)
            b:SetBackdropBorderColor(1, 1, 1, 0.9)
          else
            b:SetAlpha(0.75)
            b:SetBackdropBorderColor(0, 0, 0, 0.85)
          end
        end
      end
    end

    -- Inputs : on reflète la state (pratique MVP)
    setNumber(UI.inputs.hpCur, s.hp)
    setNumber(UI.inputs.hpMax, s.maxHp)
    setNumber(UI.inputs.tempHp, s.bonusHp)
    -- Resource inputs are handled per-row above.
    setNumber(UI.inputs.armor, s.armor)
    setNumber(UI.inputs.trueArmor, s.trueArmor)
    setNumber(UI.inputs.dodge, s.dodge)
    setNumber(UI.inputs.block, s.tempBlock)
    setNumber(UI.inputs.magicBlock, s.tempMagicBlock)
  end)
end

function ns.UI_Show(show)
  local db = GrosOrteilDB
  db.ui = db.ui or {}
  db.ui.shown = not not show
  if show then UI.frame:Show() else UI.frame:Hide() end
end

function ns.UI_ResetPosition()
  local db = GrosOrteilDB
  db.ui = db.ui or {}
  db.ui.point, db.ui.x, db.ui.y = "CENTER", 0, 0
  UI.frame:ClearAllPoints()
  UI.frame:SetPoint("CENTER")
end
