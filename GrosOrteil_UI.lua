local ADDON, ns = ...
local Core = ns.Core

local UI = {}
ns.UI = UI

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

local function mkEdit(parent, w, h, x, y)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(w, h)
  eb:SetPoint("TOPLEFT", x, y)
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
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

local function mkCheck(parent, text, x, y, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
  cb:SetPoint("TOPLEFT", x, y)
  cb.Text:SetText(text)
  cb:SetScript("OnClick", function(self) onClick(self:GetChecked()) end)
  return cb
end

local function getNumber(eb)
  local t = eb:GetText()
  local n = tonumber(t)
  return n
end

local function setNumber(eb, n)
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

  local FRAME_W, FRAME_H = 520, 340
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
    db.ui.point, db.ui.x, db.ui.y = point, x, y
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

  local resBar = CreateFrame("StatusBar", nil, frame)
  UI.resBar = resBar
  resBar:SetSize(CONTENT_W, 16)
  resBar:SetPoint("TOPLEFT", capText, "BOTTOMLEFT", 0, -8)
  resBar:SetMinMaxValues(0, 1)
  resBar:SetValue(1)
  skinBar(resBar, 0.2, 0.55, 1.0) -- bleu

  local resText = resBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  UI.resText = resText
  resText:SetPoint("CENTER")

  -- Onglets
  local tabStrip = CreateFrame("Frame", nil, frame)
  tabStrip:SetPoint("TOPLEFT", resBar, "BOTTOMLEFT", 0, -10)
  tabStrip:SetPoint("TOPRIGHT", resBar, "BOTTOMRIGHT", 0, -10)
  tabStrip:SetHeight(24)

  local contentHost = CreateFrame("Frame", nil, frame)
  contentHost:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -10)
  contentHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)

  UI.tabs = UI.tabs or {}
  UI.pages = UI.pages or {}

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
  local TAB_W = math.floor((CONTENT_W - (TAB_GAP * 3)) / 4)

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

  mkTab("PV & Ress.", 1)
  mkTab("Armure/Bloc.", 2)
  mkTab("Dégâts", 3)
  mkTab("Soins", 4)

  local pageHP = mkPage()
  local pageArmor = mkPage()
  local pageDmg = mkPage()
  local pageHeal = mkPage()

  -- Onglet 1 : PV & Ressource
  local xHP = centerX(360)
  mkLabel(pageHP, "PV", xHP + 0, -6)
  local hpCur = mkEdit(pageHP, 70, 20, xHP + 36, -4)
  local hpMax = mkEdit(pageHP, 70, 20, xHP + 126, -4)
  mkLabel(pageHP, "/", xHP + 112, -6)
  mkButton(pageHP, "Appliquer", 90, 20, xHP + 210, -4, function()
    Core.SetHP(getNumber(hpCur), getNumber(hpMax))
  end)

  local xRes = centerX(420)
  mkLabel(pageHP, "Ressource", xRes + 0, -38)
  local resCur = mkEdit(pageHP, 70, 20, xRes + 96, -36)
  local resMax = mkEdit(pageHP, 70, 20, xRes + 186, -36)
  mkLabel(pageHP, "/", xRes + 172, -38)
  mkButton(pageHP, "Appliquer", 90, 20, xRes + 270, -36, function()
    Core.SetRes(getNumber(resCur), getNumber(resMax))
  end)

  local resEnabled = mkCheck(pageHP, "Activer la ressource", centerX(260), -66, function(checked)
    Core.SetResEnabled(checked)
  end)
  UI.resEnabled = resEnabled

  mkLabelCenter(pageHP, "Ajuster ressource", 0, -94)
  local xAdj = centerX(252)
  local resValEB = mkEdit(pageHP, 70, 20, xAdj + 0, -118)
  mkButton(pageHP, "+ Ress.", 80, 20, xAdj + 86, -118, function()
    Core.AddRes(getNumber(resValEB) or 0)
  end)
  mkButton(pageHP, "- Ress.", 80, 20, xAdj + 172, -118, function()
    Core.AddRes(-(getNumber(resValEB) or 0))
  end)

  -- Onglet 2 : Armure & Blocage
  local xArmor = centerX(330)
  mkLabel(pageArmor, "Armure", xArmor + 0, -6)
  local armorEB = mkEdit(pageArmor, 70, 20, xArmor + 56, -4)
  mkLabel(pageArmor, "Armure vraie", xArmor + 150, -6)
  local trueArmorEB = mkEdit(pageArmor, 70, 20, xArmor + 238, -4)

  mkButton(pageArmor, "Appliquer", 110, 20, centerX(110), -34, function()
    Core.SetArmor(getNumber(armorEB), getNumber(trueArmorEB))
  end)

  local xBlock = centerX(362)
  mkLabel(pageArmor, "Blocage (temp.)", xBlock + 0, -70)
  local blockEB = mkEdit(pageArmor, 70, 20, xBlock + 120, -68)
  mkButton(pageArmor, "Appliquer", 90, 20, xBlock + 206, -68, function()
    Core.SetTempBlock(getNumber(blockEB))
  end)
  mkButton(pageArmor, "Réinit.", 70, 20, xBlock + 302, -68, function()
    Core.ResetTempBlock()
  end)

  -- Onglet 3 : Dégâts
  local xValD = centerX(180)
  mkLabel(pageDmg, "Valeur", xValD + 0, -6)
  local dmgValEB = mkEdit(pageDmg, 80, 20, xValD + 56, -4)

  local xDmgBtns = centerX(392)
  mkButton(pageDmg, "Dégâts (armure)", 190, 22, xDmgBtns + 0, -36, function()
    Core.DamageWithArmor(getNumber(dmgValEB) or 0)
  end)
  mkButton(pageDmg, "Dégâts (vrai)", 190, 22, xDmgBtns + 202, -36, function()
    Core.DamageTrue(getNumber(dmgValEB) or 0)
  end)

  -- Onglet 4 : Soins
  local xValH = centerX(180)
  mkLabel(pageHeal, "Valeur", xValH + 0, -6)
  local healValEB = mkEdit(pageHeal, 80, 20, xValH + 56, -4)

  local xHealBtns = centerX(392)
  mkButton(pageHeal, "Soins", 190, 22, xHealBtns + 0, -36, function()
    Core.Heal(getNumber(healValEB) or 0)
  end)
  mkButton(pageHeal, "Soins divins (75%)", 190, 22, xHealBtns + 202, -36, function()
    Core.DivineHeal()
  end)

  UI.inputs = {
    hpCur = hpCur, hpMax = hpMax,
    resCur = resCur, resMax = resMax,
    armor = armorEB, trueArmor = trueArmorEB,
    block = blockEB,
  }

  setTab(1)

  Core.OnChange(function(s)
    local hpPct = (s.maxHp and s.maxHp > 0) and (s.hp / s.maxHp) or 0
    hpBar:SetValue(math.max(0, math.min(1, hpPct)))
    hpText:SetText(string.format("PV : %d / %d (%d%%)", s.hp or 0, s.maxHp or 0, roundPct(hpPct)))

    local w = hpBar:GetWidth()
    for i = 1, #UI.hpMarkers do
      local m = UI.hpMarkers[i]
      local x = w * (m.pct or 0)
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
        local xCap = w * cap
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
    UI.resEnabled:SetChecked(not not s.resEnabled)
    if s.resEnabled then
      resBar:Show()
      local rPct = (s.maxRes and s.maxRes > 0) and (s.res / s.maxRes) or 0
      resBar:SetValue(math.max(0, math.min(1, rPct)))
      resText:SetText(string.format("Ressource : %d / %d (%d%%)", s.res or 0, s.maxRes or 0, roundPct(rPct)))
    else
      resBar:Hide()
    end

    -- Inputs : on reflète la state (pratique MVP)
    setNumber(UI.inputs.hpCur, s.hp)
    setNumber(UI.inputs.hpMax, s.maxHp)
    setNumber(UI.inputs.resCur, s.res)
    setNumber(UI.inputs.resMax, s.maxRes)
    setNumber(UI.inputs.armor, s.armor)
    setNumber(UI.inputs.trueArmor, s.trueArmor)
    setNumber(UI.inputs.block, s.tempBlock)
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
