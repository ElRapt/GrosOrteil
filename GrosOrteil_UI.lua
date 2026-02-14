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

  local frame = CreateFrame("Frame", "GrosOrteilFrame", UIParent, "BackdropTemplate")
  UI.frame = frame
  frame:SetSize(420, 285)
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
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("GrosOrteil — Treize du Treize")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  -- Barres
  local hpBar = CreateFrame("StatusBar", nil, frame)
  UI.hpBar = hpBar
  hpBar:SetSize(392, 20)
  hpBar:SetPoint("TOPLEFT", 14, -34)
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
  resBar:SetSize(392, 16)
  resBar:SetPoint("TOPLEFT", capText, "BOTTOMLEFT", 0, -8)
  resBar:SetMinMaxValues(0, 1)
  resBar:SetValue(1)
  skinBar(resBar, 0.2, 0.55, 1.0) -- bleu

  local resText = resBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  UI.resText = resText
  resText:SetPoint("CENTER")

  -- Section: PV / Ressource (inputs)
  mkLabel(frame, "PV", 14, -102)
  local hpCur = mkEdit(frame, 60, 20, 50, -100)
  local hpMax = mkEdit(frame, 60, 20, 120, -100)
  mkLabel(frame, "sur", 112, -102)

  mkButton(frame, "Appliquer", 80, 20, 190, -100, function()
    Core.SetHP(getNumber(hpCur), getNumber(hpMax))
  end)

  mkLabel(frame, "Ressource", 14, -130)
  local resCur = mkEdit(frame, 60, 20, 86, -128)
  local resMax = mkEdit(frame, 60, 20, 156, -128)
  mkLabel(frame, "sur", 148, -130)

  mkButton(frame, "Appliquer", 80, 20, 226, -128, function()
    Core.SetRes(getNumber(resCur), getNumber(resMax))
  end)

  local resEnabled = mkCheck(frame, "Activer la ressource", 312, -130, function(checked)
    Core.SetResEnabled(checked)
  end)
  UI.resEnabled = resEnabled

  -- Armure / Armure vraie / Blocage temp
  mkLabel(frame, "Armure", 14, -164)
  local armorEB = mkEdit(frame, 60, 20, 70, -162)

  mkLabel(frame, "Armure vraie", 144, -164)
  local trueArmorEB = mkEdit(frame, 60, 20, 232, -162)

  mkButton(frame, "Appliquer", 80, 20, 308, -162, function()
    Core.SetArmor(getNumber(armorEB), getNumber(trueArmorEB))
  end)

  mkLabel(frame, "Blocage (temp.)", 14, -194)
  local blockEB = mkEdit(frame, 60, 20, 120, -192)
  mkButton(frame, "Appliquer", 80, 20, 190, -192, function()
    Core.SetTempBlock(getNumber(blockEB))
  end)
  mkButton(frame, "Réinit.", 60, 20, 276, -192, function()
    Core.ResetTempBlock()
  end)

  -- Dégâts / Soins / Ressource +-
  mkLabel(frame, "Valeur", 14, -226)
  local valEB = mkEdit(frame, 60, 20, 70, -224)

  mkButton(frame, "Dégâts (armure)", 120, 20, 144, -224, function()
    Core.DamageWithArmor(getNumber(valEB) or 0)
  end)

  mkButton(frame, "Dégâts (vrai)", 100, 20, 272, -224, function()
    Core.DamageTrue(getNumber(valEB) or 0)
  end)

  mkButton(frame, "Soins", 70, 20, 14, -252, function()
    Core.Heal(getNumber(valEB) or 0)
  end)

  mkButton(frame, "Soins divins (75%)", 140, 20, 90, -252, function()
    Core.DivineHeal()
  end)

  mkButton(frame, "+ Ress.", 70, 20, 238, -252, function()
    Core.AddRes(getNumber(valEB) or 0)
  end)

  mkButton(frame, "- Ress.", 70, 20, 312, -252, function()
    Core.AddRes(-(getNumber(valEB) or 0))
  end)

  UI.inputs = {
    hpCur = hpCur, hpMax = hpMax,
    resCur = resCur, resMax = resMax,
    armor = armorEB, trueArmor = trueArmorEB,
    block = blockEB,
  }

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
