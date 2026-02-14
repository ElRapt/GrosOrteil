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

function ns.UI_Init()
  local db = GrosOrteilDB
  db.ui = db.ui or { point = "CENTER", x = 0, y = 0, shown = true }

  local frame = CreateFrame("Frame", "GrosOrteilFrame", UIParent, "BackdropTemplate")
  UI.frame = frame
  frame:SetSize(420, 260)
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
  frame:SetBackdropColor(0, 0, 0, 0.9)

  frame:SetPoint(db.ui.point, UIParent, db.ui.point, db.ui.x, db.ui.y)
  if db.ui.shown then frame:Show() else frame:Hide() end

  -- Titre
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("GrosOrteil — Suivi RPG (local)")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  -- Barres
  local hpBar = CreateFrame("StatusBar", nil, frame)
  UI.hpBar = hpBar
  hpBar:SetSize(392, 20)
  hpBar:SetPoint("TOPLEFT", 14, -34)
  hpBar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  hpBar:SetMinMaxValues(0, 1)
  hpBar:SetValue(1)

  local hpText = hpBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  UI.hpText = hpText
  hpText:SetPoint("CENTER")

  -- Marqueurs 50/25/10%
  UI.hpMarkers = {}
  local function makeMarker(parent, pct)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface/Buttons/WHITE8x8")
    t:SetWidth(2)
    t:SetHeight(20)
    t:SetColorTexture(1, 1, 1, 0.4)
    t.pct = pct
    return t
  end
  UI.hpMarkers[1] = makeMarker(hpBar, 0.50)
  UI.hpMarkers[2] = makeMarker(hpBar, 0.25)
  UI.hpMarkers[3] = makeMarker(hpBar, 0.10)

  local capText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  UI.capText = capText
  capText:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, -4)
  capText:SetText("")

  local resBar = CreateFrame("StatusBar", nil, frame)
  UI.resBar = resBar
  resBar:SetSize(392, 16)
  resBar:SetPoint("TOPLEFT", capText, "BOTTOMLEFT", 0, -6)
  resBar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  resBar:SetMinMaxValues(0, 1)
  resBar:SetValue(1)

  local resText = resBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  UI.resText = resText
  resText:SetPoint("CENTER")

  -- Section: PV / Ressource (inputs)
  mkLabel(frame, "PV", 14, -98)
  local hpCur = mkEdit(frame, 60, 20, 50, -96)
  local hpMax = mkEdit(frame, 60, 20, 120, -96)
  mkLabel(frame, "sur", 112, -98)

  mkButton(frame, "Appliquer", 80, 20, 190, -96, function()
    Core.SetHP(getNumber(hpCur), getNumber(hpMax))
  end)

  mkLabel(frame, "Ressource", 14, -124)
  local resCur = mkEdit(frame, 60, 20, 86, -122)
  local resMax = mkEdit(frame, 60, 20, 156, -122)
  mkLabel(frame, "sur", 148, -124)

  mkButton(frame, "Appliquer", 80, 20, 226, -122, function()
    Core.SetRes(getNumber(resCur), getNumber(resMax))
  end)

  local resEnabled = mkCheck(frame, "Activer la ressource", 312, -124, function(checked)
    Core.SetResEnabled(checked)
  end)
  UI.resEnabled = resEnabled

  -- Armure / Armure vraie / Blocage temp
  mkLabel(frame, "Armure", 14, -156)
  local armorEB = mkEdit(frame, 60, 20, 70, -154)

  mkLabel(frame, "Armure vraie", 144, -156)
  local trueArmorEB = mkEdit(frame, 60, 20, 232, -154)

  mkButton(frame, "Appliquer", 80, 20, 308, -154, function()
    Core.SetArmor(getNumber(armorEB), getNumber(trueArmorEB))
  end)

  mkLabel(frame, "Blocage (temp.)", 14, -184)
  local blockEB = mkEdit(frame, 60, 20, 120, -182)
  mkButton(frame, "Appliquer", 80, 20, 190, -182, function()
    Core.SetTempBlock(getNumber(blockEB))
  end)
  mkButton(frame, "Réinit.", 60, 20, 276, -182, function()
    Core.ResetTempBlock()
  end)

  -- Dégâts / Soins / Ressource +-
  mkLabel(frame, "Valeur", 14, -216)
  local valEB = mkEdit(frame, 60, 20, 70, -214)

  mkButton(frame, "Dégâts (armure)", 120, 20, 144, -214, function()
    Core.DamageWithArmor(getNumber(valEB) or 0)
  end)

  mkButton(frame, "Dégâts (vrai)", 100, 20, 272, -214, function()
    Core.DamageTrue(getNumber(valEB) or 0)
  end)

  mkButton(frame, "Soins", 70, 20, 14, -242, function()
    Core.Heal(getNumber(valEB) or 0)
  end)

  mkButton(frame, "Soins divins (75%)", 140, 20, 90, -242, function()
    Core.DivineHeal()
  end)

  mkButton(frame, "+ Ress.", 70, 20, 238, -242, function()
    Core.AddRes(getNumber(valEB) or 0)
  end)

  mkButton(frame, "- Ress.", 70, 20, 312, -242, function()
    Core.AddRes(-(getNumber(valEB) or 0))
  end)

  -- Sauvegarde pour synchroniser les champs à l’état
  UI.inputs = {
    hpCur = hpCur, hpMax = hpMax,
    resCur = resCur, resMax = resMax,
    armor = armorEB, trueArmor = trueArmorEB,
    block = blockEB,
  }

  -- Binding état -> UI
  Core.OnChange(function(s)
    -- Barres (bar clamp 0..1, mais PV peut être négatif)
    local hpPct = (s.maxHp and s.maxHp > 0) and (s.hp / s.maxHp) or 0
    hpBar:SetValue(math.max(0, math.min(1, hpPct)))
    hpText:SetText(string.format("PV : %d / %d (%d%%)", s.hp or 0, s.maxHp or 0, roundPct(hpPct)))

    -- Marqueurs
    local w = hpBar:GetWidth()
    for i = 1, #UI.hpMarkers do
      local m = UI.hpMarkers[i]
      local x = w * (m.pct or 0)
      m:ClearAllPoints()
      m:SetPoint("LEFT", hpBar, "LEFT", x, 0)
    end

    -- Plafond de soins
    local cap = s.woundCap or 1.0
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
