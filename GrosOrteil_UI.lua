local _, ns = ...
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

  local xRes = centerX(420)
  mkLabel(pageHP, "Ressource", xRes + 0, -74)
  local resCur, resMax
  mkLabel(pageHP, "/", xRes + 172, -74)
  local function applyRes()
    Core.SetRes(getNumber(resCur), getNumber(resMax))
  end
  resCur = mkEdit(pageHP, 70, 20, xRes + 96, -72, applyRes)
  resMax = mkEdit(pageHP, 70, 20, xRes + 186, -72, applyRes)
  mkButton(pageHP, "Appliquer", 90, 20, xRes + 270, -72, applyRes)

  local resEnabled = mkCheck(pageHP, "Activer la ressource", centerX(260), -102, function(checked)
    Core.SetResEnabled(checked)
  end)
  UI.resEnabled = resEnabled

  mkLabelCenter(pageHP, "Ajuster ressource", 0, -130)
  local xAdj = centerX(252)
  local resValEB = mkEdit(pageHP, 70, 20, xAdj + 0, -154)
  mkButton(pageHP, "+ Ress.", 80, 20, xAdj + 86, -154, function()
    Core.AddRes(getNumber(resValEB) or 0)
  end)
  mkButton(pageHP, "- Ress.", 80, 20, xAdj + 172, -154, function()
    Core.AddRes(-(getNumber(resValEB) or 0))
  end)

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
  local blockEB
  local function applyBlock()
    Core.SetTempBlock(getNumber(blockEB))
  end
  blockEB = mkEdit(pageArmor, 70, 20, xBlock + 120, -68, applyBlock)
  mkButton(pageArmor, "Appliquer", 90, 20, xBlock + 206, -68, applyBlock)
  mkButton(pageArmor, "Réinit.", 70, 20, xBlock + 302, -68, function()
    Core.ResetTempBlock()
  end)

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
    resCur = resCur, resMax = resMax,
    armor = armorEB, trueArmor = trueArmorEB,
    dodge = dodgeEB,
    block = blockEB,
  }

  setTab(1)

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

    -- Blocage overlay (gris)
    if UI.hpBlockOverlay then
      local maxHp = effMaxHp
      local block = math.max(0, s.tempBlock or 0)
      local wBar = hpBar:GetWidth() or 0

      local hpFrac = 0
      if maxHp > 0 then hpFrac = hpNow / maxHp end
      hpFrac = math.max(0, math.min(1, hpFrac))

      local blockFrac = 0
      if maxHp > 0 then blockFrac = block / maxHp end
      blockFrac = math.max(0, blockFrac)


      local endX = wBar * hpFrac
      local startX = math.max(0, endX - (wBar * blockFrac))
      local blockW = endX - startX

      if blockW > 0.5 and endX > 0.5 then
        UI.hpBlockOverlay:Show()
        UI.hpBlockOverlay:ClearAllPoints()
        UI.hpBlockOverlay:SetPoint("TOPLEFT", hpBar, "TOPLEFT", startX, 0)
        UI.hpBlockOverlay:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", startX, 0)
        UI.hpBlockOverlay:SetWidth(blockW)
      else
        UI.hpBlockOverlay:Hide()
      end
    end

    local w = hpBar:GetWidth()
    local baseScale = (effMaxHp > 0) and (baseMaxHp / effMaxHp) or 0
    for i = 1, #UI.hpMarkers do
      local m = UI.hpMarkers[i]
      local x = w * (m.pct or 0) * baseScale
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
        local xCap = (effMaxHp > 0) and (w * ((baseMaxHp * cap) / effMaxHp)) or 0
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
    setNumber(UI.inputs.tempHp, s.bonusHp)
    setNumber(UI.inputs.resCur, s.res)
    setNumber(UI.inputs.resMax, s.maxRes)
    setNumber(UI.inputs.armor, s.armor)
    setNumber(UI.inputs.trueArmor, s.trueArmor)
    setNumber(UI.inputs.dodge, s.dodge)
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
