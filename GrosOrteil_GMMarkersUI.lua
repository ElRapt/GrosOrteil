---@diagnostic disable: undefined-global
-- GrosOrteil/GMMarkersUI.lua
-- GM-only window for managing stats on the 8 WoW raid target markers.
-- Visible only when the player is the group leader or assistant.
-- Reads ns.UITheme (exposed by GrosOrteil_UI.lua) for style constants.
local _, ns = ...

local GMMarkersUI = {}
ns.GMMarkersUI = GMMarkersUI

local GMMarkers = ns.GMMarkers
local Shared    = ns.Shared

---------------------------------------------------------------------------
-- Style constants (from main UI theme)
---------------------------------------------------------------------------

local C, TEX

local function ensureTheme()
  if C then return end
  local theme = ns.UITheme or {}
  C   = theme.C   or {}
  TEX = theme.TEX or {}
end

---------------------------------------------------------------------------
-- Backdrop definitions (same style as main UI)
---------------------------------------------------------------------------

local function makeBackdrops()
  return {
    FLAT      = "Interface/Buttons/WHITE8x8",
    STATUSBAR = "Interface/TargetingFrame/UI-StatusBar",
  }
end

---------------------------------------------------------------------------
-- Widget factories (self-contained — no dependency on UI.lua locals)
---------------------------------------------------------------------------

local function mkLabel(parent, text, x, y)
  ensureTheme()
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetTextColor((C.TEXT_LABEL or {0.82,0.74,0.55})[1], (C.TEXT_LABEL or {0.82,0.74,0.55})[2], (C.TEXT_LABEL or {0.82,0.74,0.55})[3], 1)
  fs:SetText(text)
  return fs
end

-- Numeric edit box (same pattern as main UI mkEdit).
local function mkEdit(parent, w, h, x, y, onCommit)
  ensureTheme()
  local flat = (TEX and TEX.FLAT) or "Interface/Buttons/WHITE8x8"
  local CD   = C.BROWN_DEEP    or {0.08,0.05,0.02}
  local CDK  = C.BROWN_DARK    or {0.14,0.09,0.04}
  local GM   = C.GOLD_MUTED    or {0.55,0.42,0.18}
  local GB   = C.GOLD_BRIGHT   or {1.00,0.82,0.22}
  local TB   = C.TEXT_BRIGHT   or {1.00,0.95,0.80}

  local wrap = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  wrap:SetSize(w, h)
  wrap:SetPoint("TOPLEFT", x, y)
  wrap:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 2,
                     insets = { left=2, right=2, top=2, bottom=2 } })
  wrap:SetBackdropColor(CD[1], CD[2], CD[3], 0.92)
  wrap:SetBackdropBorderColor(GM[1], GM[2], GM[3], 0.70)

  local eb = CreateFrame("EditBox", nil, wrap)
  eb:SetPoint("TOPLEFT", 5, -2)
  eb:SetPoint("BOTTOMRIGHT", -4, 2)
  eb:SetFontObject("GameFontHighlight")
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetTextColor(TB[1], TB[2], TB[3], 1)
  eb:SetScript("OnEditFocusGained", function()
    wrap:SetBackdropBorderColor(GB[1], GB[2], GB[3], 0.90)
    wrap:SetBackdropColor(CDK[1], CDK[2], CDK[3], 0.95)
  end)
  eb:SetScript("OnEditFocusLost", function()
    wrap:SetBackdropBorderColor(GM[1], GM[2], GM[3], 0.70)
    wrap:SetBackdropColor(CD[1], CD[2], CD[3], 0.92)
    if onCommit then onCommit() end
  end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onCommit then onCommit() end
  end)
  eb._wrap = wrap
  return eb
end

-- Text (non-numeric) edit box for label field.
local function mkTextEdit(parent, w, h, x, y, onCommit)
  ensureTheme()
  local flat = (TEX and TEX.FLAT) or "Interface/Buttons/WHITE8x8"
  local CD   = C.BROWN_DEEP    or {0.08,0.05,0.02}
  local CDK  = C.BROWN_DARK    or {0.14,0.09,0.04}
  local GM   = C.GOLD_MUTED    or {0.55,0.42,0.18}
  local GB   = C.GOLD_BRIGHT   or {1.00,0.82,0.22}
  local TB   = C.TEXT_BRIGHT   or {1.00,0.95,0.80}

  local wrap = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  wrap:SetSize(w, h)
  wrap:SetPoint("TOPLEFT", x, y)
  wrap:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 2,
                     insets = { left=2, right=2, top=2, bottom=2 } })
  wrap:SetBackdropColor(CD[1], CD[2], CD[3], 0.92)
  wrap:SetBackdropBorderColor(GM[1], GM[2], GM[3], 0.70)

  local eb = CreateFrame("EditBox", nil, wrap)
  eb:SetPoint("TOPLEFT", 5, -2)
  eb:SetPoint("BOTTOMRIGHT", -4, 2)
  eb:SetFontObject("GameFontHighlight")
  eb:SetAutoFocus(false)
  eb:SetTextColor(TB[1], TB[2], TB[3], 1)
  eb:SetMaxLetters(64)
  eb:SetScript("OnEditFocusGained", function()
    wrap:SetBackdropBorderColor(GB[1], GB[2], GB[3], 0.90)
    wrap:SetBackdropColor(CDK[1], CDK[2], CDK[3], 0.95)
  end)
  eb:SetScript("OnEditFocusLost", function()
    wrap:SetBackdropBorderColor(GM[1], GM[2], GM[3], 0.70)
    wrap:SetBackdropColor(CD[1], CD[2], CD[3], 0.92)
    if onCommit then onCommit() end
  end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onCommit then onCommit() end
  end)
  eb._wrap = wrap
  return eb
end

local function mkButton(parent, text, w, h, x, y, onClick)
  ensureTheme()
  local flat = (TEX and TEX.FLAT) or "Interface/Buttons/WHITE8x8"
  local CDK  = C.BROWN_DARK    or {0.14,0.09,0.04}
  local CD   = C.BROWN_DEEP    or {0.08,0.05,0.02}
  local GM   = C.GOLD_MUTED    or {0.55,0.42,0.18}
  local GL   = C.GOLD_LIGHT    or {1.00,0.90,0.55}
  local TD   = C.TEXT_DISABLED or {0.40,0.34,0.22}

  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  b:SetPoint("TOPLEFT", x, y)
  b:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1,
                  insets = { left=2, right=2, top=2, bottom=2 } })
  b:SetBackdropColor(CDK[1], CDK[2], CDK[3], 0.90)
  b:SetBackdropBorderColor(GM[1], GM[2], GM[3], 0.80)

  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture(flat)
  hl:SetColorTexture(1.0, 0.80, 0.30, 0.10)

  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("CENTER", 0, 0)
  fs:SetTextColor(GL[1], GL[2], GL[3], 1)
  fs:SetText(text)
  b._fs = fs

  function b:SetText(t) fs:SetText(t) end
  function b:GetText() return fs:GetText() end

  b:SetScript("OnMouseDown", function() if b:IsEnabled() then fs:SetPoint("CENTER", 1, -1) end end)
  b:SetScript("OnMouseUp",   function() fs:SetPoint("CENTER", 0, 0) end)

  local origDisable = b.Disable
  function b:Disable()
    origDisable(self)
    fs:SetTextColor(TD[1], TD[2], TD[3], 1)
    self:SetBackdropColor(CD[1], CD[2], CD[3], 0.65)
    self:SetBackdropBorderColor(GM[1], GM[2], GM[3], 0.35)
  end
  local origEnable = b.Enable
  function b:Enable()
    origEnable(self)
    fs:SetTextColor(GL[1], GL[2], GL[3], 1)
    self:SetBackdropColor(CDK[1], CDK[2], CDK[3], 0.90)
    self:SetBackdropBorderColor(GM[1], GM[2], GM[3], 0.80)
  end

  if onClick then b:SetScript("OnClick", function() onClick() end) end
  return b
end

local function mkSep(parent, y, w)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(w or 480, 1)
  f:SetPoint("TOPLEFT", 0, y)
  ensureTheme()
  local GM = C.GOLD_MUTED or {0.55,0.42,0.18}
  f:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8", edgeSize = 0 })
  f:SetBackdropColor(GM[1], GM[2], GM[3], 0.35)
  return f
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local frame         -- main window
local sidebarRows   = {}
local currentIdx    = 1
local currentUnreg  = nil

-- Content-area widget refs (rebuilt on first show, reused after)
local W = {}  -- W.labelEB, W.hpEB, W.maxHpEB, W.armorEB, etc.

---------------------------------------------------------------------------
-- GM eligibility
---------------------------------------------------------------------------

local function isGM()
  local inGroup = (type(IsInRaid)  == "function" and IsInRaid())
               or (type(IsInGroup) == "function" and IsInGroup())
  if not inGroup then return false end
  if type(UnitIsGroupLeader)    == "function" and UnitIsGroupLeader("player")    then return true end
  if type(UnitIsGroupAssistant) == "function" and UnitIsGroupAssistant("player") then return true end
  return false
end

local function updateGMVisibility()
  if not frame then return end
  if not isGM() then
    frame:Hide()
  end
  -- We never auto-show; the GM opens with /go gm.
end

---------------------------------------------------------------------------
-- Sidebar
---------------------------------------------------------------------------

local function buildSidebar(parent)
  ensureTheme()
  local flat    = (TEX and TEX.FLAT) or "Interface/Buttons/WHITE8x8"
  local CD      = C.BROWN_DEEP  or {0.08,0.05,0.02}
  local GM      = C.GOLD_MUTED  or {0.55,0.42,0.18}
  local GB      = C.GOLD_BRIGHT or {1.00,0.82,0.22}
  local TN      = C.TEXT_NORMAL or {0.90,0.84,0.68}

  local sidebar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  sidebar:SetPoint("TOPLEFT",    16, -40)
  sidebar:SetPoint("BOTTOMLEFT", 16,  16)
  sidebar:SetWidth(130)
  sidebar:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1,
                        insets = { left=0, right=0, top=0, bottom=0 } })
  sidebar:SetBackdropColor(CD[1]*0.7, CD[2]*0.7, CD[3]*0.7, 0.95)
  sidebar:SetBackdropBorderColor(GM[1], GM[2], GM[3], 0.60)

  local markers = Shared.RAID_MARKERS or {}
  local ROW_H   = 40

  for i = 1, 8 do
    local m = markers[i] or { idx=i, name="Marqueur "..i, texture="" }
    local row = CreateFrame("Button", nil, sidebar)
    row:SetSize(130, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i-1)*ROW_H)

    -- Hover highlight
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(flat)
    hl:SetColorTexture(1, 0.80, 0.30, 0.08)

    -- Active indicator (left edge strip)
    local sel = row:CreateTexture(nil, "ARTWORK")
    sel:SetSize(3, ROW_H)
    sel:SetPoint("LEFT", 0, 0)
    sel:SetTexture(flat)
    sel:SetColorTexture(GB[1], GB[2], GB[3], 0)
    row._sel = sel

    -- Marker icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 8, 0)
    if m.texture and m.texture ~= "" then icon:SetTexture(m.texture) end

    -- Label
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", 36, 0)
    lbl:SetTextColor(TN[1], TN[2], TN[3], 1)
    lbl:SetText(m.name)
    row._label = lbl

    row:SetScript("OnClick", function()
      GMMarkersUI.SelectMarker(i)
    end)

    sidebarRows[i] = row
  end

  return sidebar
end

---------------------------------------------------------------------------
-- Content area population
---------------------------------------------------------------------------

local function safeNum(v)
  return type(v) == "number" and v or 0
end

local function setEB(eb, v)
  if not eb or not eb.SetText then return end
  eb:SetText(tostring(math.floor(safeNum(v) + 0.5)))
end

local function readEB(eb)
  if not eb or not eb.GetText then return 0 end
  return tonumber(eb:GetText()) or 0
end

local function refreshContent(idx)
  local s = GMMarkers.states and GMMarkers.states[idx]
  if not s then return end

  -- Label
  if W.labelEB and W.labelEB.SetText then W.labelEB:SetText(s.label or "") end

  -- HP
  setEB(W.hpEB,    s.hp)
  setEB(W.maxHpEB, s.maxHp)

  -- Chance
  setEB(W.chanceEB,    s.chance)
  setEB(W.maxChanceEB, s.maxChance)

  -- Armor
  setEB(W.armorEB,     s.armor)
  setEB(W.trueArmorEB, s.trueArmor)
  setEB(W.tempArmorEB, s.tempArmor)
  setEB(W.dodgeEB,     s.dodge)
  setEB(W.blockEB,     s.tempBlock)

  -- Magic shield
  local ms = s.magicShield or {}
  setEB(W.msHpEB,    ms.hp)
  setEB(W.msMaxEB,   ms.maxHp)
  setEB(W.msArmorEB, ms.armor)

  -- Resource
  setEB(W.resEB,    s.res)
  setEB(W.maxResEB, s.maxRes)

  -- Attack
  setEB(W.meleeEB, s.attaqueMelee)
  setEB(W.distEB,  s.attaqueDistance)

  -- History
  if W.historyText then
    local lines = {}
    local hist  = s.history or {}
    for i = 1, math.min(30, #hist) do
      local e = hist[i]
      if e then
        local line
        if e.dodged then
          line = string.format("|cFFFFFF00Esquivé|r %d", safeNum(e.input))
        elseif e.kind == "HEAL" then
          line = string.format("|cFF55FF55Soins|r +%d → %d/%d", safeNum(e.applied), safeNum(e.hpAfter), safeNum(e.maxHp))
        elseif e.kind == "DIVINE_HEAL" then
          line = string.format("|cFF55FF55Soins divins|r +%.0f → %d/%d", safeNum(e.gain), safeNum(e.hpAfter), safeNum(e.maxHp))
        elseif e.kind == "SURGERY" then
          line = string.format("|cFF55FF55Chirurgie|r +%.0f → %d/%d", safeNum(e.gain), safeNum(e.hpAfter), safeNum(e.maxHp))
        elseif e.kind == "RESTORE_HP" then
          line = string.format("|cFF55FF55Restauration|r %d → %d/%d", safeNum(e.hpBefore), safeNum(e.hpAfter), safeNum(e.maxHp))
        elseif e.kind == "REGEN_HP" then
          line = string.format("|cFF88FF88Regen HP|r +%.0f → %d/%d", safeNum(e.gain), safeNum(e.hpAfter), safeNum(e.maxHp))
        elseif e.kind == "REGEN_RES" then
          line = string.format("|cFF8888FFRegen Res|r +%.0f → %d/%d", safeNum(e.gain), safeNum(e.resAfter), safeNum(e.maxRes))
        elseif e.kind == "DAMAGE_ARMOR" then
          line = string.format("|cFFFF4444Dégâts|r -%d → %d/%d", safeNum(e.damage), safeNum(e.hpAfter), safeNum(e.maxHp))
        elseif e.kind == "DAMAGE_TRUE" then
          line = string.format("|cFFFF8888Vrai Dmg|r -%d → %d/%d", safeNum(e.damage), safeNum(e.hpAfter), safeNum(e.maxHp))
        else
          line = string.format("%s %d→%d", tostring(e.kind or "?"), safeNum(e.hpBefore), safeNum(e.hpAfter))
        end
        lines[#lines+1] = line
      end
    end
    W.historyText:SetText(table.concat(lines, "\n"))
  end
end

---------------------------------------------------------------------------
-- Content scroll area
---------------------------------------------------------------------------

local function buildContent(parent, SIDEBAR_W)
  ensureTheme()
  local flat    = (TEX and TEX.FLAT) or "Interface/Buttons/WHITE8x8"
  local CD      = C.BROWN_DEEP  or {0.08,0.05,0.02}
  local GM      = C.GOLD_MUTED  or {0.55,0.42,0.18}
  local TL      = C.TEXT_LABEL  or {0.82,0.74,0.55}
  local TT      = C.TEXT_TITLE  or {1.00,0.84,0.30}

  local CONTENT_X = SIDEBAR_W + 26
  local CONTENT_W = 520
  local CONTENT_H = 660

  -- Background panel for content area
  local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  bg:SetPoint("TOPLEFT",     CONTENT_X - 6, -34)
  bg:SetPoint("BOTTOMRIGHT", -10,             10)
  bg:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1 })
  bg:SetBackdropColor(CD[1]*0.6, CD[2]*0.6, CD[3]*0.6, 0.80)
  bg:SetBackdropBorderColor(GM[1], GM[2], GM[3], 0.40)

  -- ScrollFrame
  local sf = CreateFrame("ScrollFrame", "GrosOrteilGMScrollFrame", parent, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT",     CONTENT_X, -38)
  sf:SetPoint("BOTTOMRIGHT", -28,         14)

  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(CONTENT_W, CONTENT_H)
  sf:SetScrollChild(child)

  local Y = -10  -- current Y offset

  -- ── Identité ──────────────────────────────────────────────────────────
  local iconTex = child:CreateTexture(nil, "ARTWORK")
  iconTex:SetSize(28, 28)
  iconTex:SetPoint("TOPLEFT", 8, Y)
  W._markerIcon = iconTex

  mkLabel(child, "Label :", 44, Y + 6)

  W.labelEB = mkTextEdit(child, 200, 20, 100, Y + 4, function()
    if W.labelEB then GMMarkers.SetLabel(currentIdx, W.labelEB:GetText() or "") end
  end)

  Y = Y - 38

  -- ── Points de vie ──────────────────────────────────────────────────────
  mkLabel(child, "── Points de vie ──", 8, Y)
  Y = Y - 22

  mkLabel(child, "PV :", 8, Y)
  W.hpEB = mkEdit(child, 58, 20, 36, Y + 2, function()
    GMMarkers.SetHP(currentIdx, readEB(W.hpEB), readEB(W.maxHpEB))
  end)
  mkLabel(child, "/", 98, Y)
  W.maxHpEB = mkEdit(child, 58, 20, 106, Y + 2, function()
    GMMarkers.SetHP(currentIdx, readEB(W.hpEB), readEB(W.maxHpEB))
  end)

  mkButton(child, "Restaurer PV", 90, 22, 172, Y + 2, function()
    GMMarkers.RestoreHP(currentIdx)
  end)
  mkButton(child, "Regen J/J", 76, 22, 268, Y + 2, function()
    GMMarkers.DailyRegenHP(currentIdx)
  end)

  Y = Y - 30

  -- ── Points de chance ──────────────────────────────────────────────────
  mkLabel(child, "Chance :", 8, Y)
  W.chanceEB = mkEdit(child, 50, 20, 68, Y + 2, function()
    GMMarkers.SetChance(currentIdx, readEB(W.chanceEB), readEB(W.maxChanceEB))
  end)
  mkLabel(child, "/", 122, Y)
  W.maxChanceEB = mkEdit(child, 50, 20, 130, Y + 2, function()
    GMMarkers.SetChance(currentIdx, readEB(W.chanceEB), readEB(W.maxChanceEB))
  end)

  Y = Y - 34
  mkSep(child, Y, CONTENT_W - 20)
  Y = Y - 14

  -- ── Armure & Esquive ───────────────────────────────────────────────────
  mkLabel(child, "── Armure & Défense ──", 8, Y)
  Y = Y - 22

  mkLabel(child, "Armure :",      8,   Y)
  W.armorEB     = mkEdit(child, 52, 20, 68,  Y + 2, function() GMMarkers.SetArmor(currentIdx, readEB(W.armorEB), readEB(W.trueArmorEB)) end)
  mkLabel(child, "TrueA :",       130, Y)
  W.trueArmorEB = mkEdit(child, 52, 20, 182, Y + 2, function() GMMarkers.SetArmor(currentIdx, readEB(W.armorEB), readEB(W.trueArmorEB)) end)
  mkLabel(child, "TempA :",       248, Y)
  W.tempArmorEB = mkEdit(child, 52, 20, 300, Y + 2, function() GMMarkers.SetTempArmor(currentIdx, readEB(W.tempArmorEB)) end)

  Y = Y - 28

  mkLabel(child, "Esquive :",     8,   Y)
  W.dodgeEB  = mkEdit(child, 52, 20, 68,  Y + 2, function() GMMarkers.SetDodge(currentIdx,    readEB(W.dodgeEB)) end)
  mkLabel(child, "Blocage :",     130, Y)
  W.blockEB  = mkEdit(child, 52, 20, 182, Y + 2, function() GMMarkers.SetTempBlock(currentIdx, readEB(W.blockEB)) end)
  mkButton(child, "Reset Bloc",   72, 20, 244, Y + 2, function() GMMarkers.ResetTempBlock(currentIdx) end)

  Y = Y - 34
  mkSep(child, Y, CONTENT_W - 20)
  Y = Y - 14

  -- ── Bouclier magique ───────────────────────────────────────────────────
  mkLabel(child, "── Bouclier magique ──", 8, Y)
  Y = Y - 22

  mkLabel(child, "PV :",     8,   Y)
  W.msHpEB    = mkEdit(child, 52, 20, 34,  Y + 2, function()
    GMMarkers.SetMagicShield(currentIdx, readEB(W.msHpEB), readEB(W.msMaxEB), readEB(W.msArmorEB))
  end)
  mkLabel(child, "/",        90,  Y)
  W.msMaxEB   = mkEdit(child, 52, 20, 96,  Y + 2, function()
    GMMarkers.SetMagicShield(currentIdx, readEB(W.msHpEB), readEB(W.msMaxEB), readEB(W.msArmorEB))
  end)
  mkLabel(child, "Armure :", 158, Y)
  W.msArmorEB = mkEdit(child, 52, 20, 218, Y + 2, function()
    GMMarkers.SetMagicShield(currentIdx, readEB(W.msHpEB), readEB(W.msMaxEB), readEB(W.msArmorEB))
  end)
  mkButton(child, "Reset", 52, 20, 278, Y + 2, function()
    GMMarkers.ResetMagicShield(currentIdx)
  end)

  Y = Y - 34
  mkSep(child, Y, CONTENT_W - 20)
  Y = Y - 14

  -- ── Ressource ──────────────────────────────────────────────────────────
  mkLabel(child, "── Ressource ──", 8, Y)
  Y = Y - 22

  mkLabel(child, "Res :", 8, Y)
  W.resEB    = mkEdit(child, 58, 20, 40, Y + 2, function()
    GMMarkers.SetRes(currentIdx, readEB(W.resEB), readEB(W.maxResEB))
  end)
  mkLabel(child, "/", 102, Y)
  W.maxResEB = mkEdit(child, 58, 20, 110, Y + 2, function()
    GMMarkers.SetRes(currentIdx, readEB(W.resEB), readEB(W.maxResEB))
  end)
  mkButton(child, "Regen J/J", 76, 22, 178, Y + 2, function()
    GMMarkers.DailyRegenRes(currentIdx)
  end)

  Y = Y - 34
  mkSep(child, Y, CONTENT_W - 20)
  Y = Y - 14

  -- ── Attaque ────────────────────────────────────────────────────────────
  mkLabel(child, "── Attaque ──", 8, Y)
  Y = Y - 22

  mkLabel(child, "CaC :",  8,   Y)
  W.meleeEB = mkEdit(child, 52, 20, 40,  Y + 2, function()
    GMMarkers.SetAttaque(currentIdx, readEB(W.meleeEB), readEB(W.distEB))
  end)
  mkLabel(child, "Dist :", 106, Y)
  W.distEB  = mkEdit(child, 52, 20, 138, Y + 2, function()
    GMMarkers.SetAttaque(currentIdx, readEB(W.meleeEB), readEB(W.distEB))
  end)

  Y = Y - 34
  mkSep(child, Y, CONTENT_W - 20)
  Y = Y - 14

  -- ── Actions ────────────────────────────────────────────────────────────
  mkLabel(child, "── Actions ──", 8, Y)
  Y = Y - 22

  mkLabel(child, "Valeur :", 8, Y)
  W.actionEB = mkEdit(child, 68, 20, 68, Y + 2)

  Y = Y - 28

  local function actionVal()
    return readEB(W.actionEB)
  end

  -- Row 1: damage + heal
  mkButton(child, "Dégâts",      80, 22, 8,   Y, function() GMMarkers.DamageWithArmor(currentIdx, actionVal()) end)
  mkButton(child, "Vrai dégâts", 84, 22, 96,  Y, function() GMMarkers.DamageTrue(currentIdx,      actionVal()) end)
  mkButton(child, "Soins",       70, 22, 188, Y, function() GMMarkers.Heal(currentIdx,             actionVal()) end)

  Y = Y - 28

  -- Row 2: bypass heals + reset
  mkButton(child, "Soins divins", 90, 22, 8,   Y, function() GMMarkers.DivineHeal(currentIdx) end)
  mkButton(child, "Chirurgie",    82, 22, 106, Y, function() GMMarkers.Surgery(currentIdx)    end)

  Y = Y - 30
  mkButton(child, "Réinitialiser ce marqueur", 180, 22, 8, Y, function()
    GMMarkers.ResetMarker(currentIdx)
  end)
  mkButton(child, "Vider historique", 120, 22, 196, Y, function()
    GMMarkers.ClearHistory(currentIdx)
  end)

  Y = Y - 36
  mkSep(child, Y, CONTENT_W - 20)
  Y = Y - 14

  -- ── Historique ─────────────────────────────────────────────────────────
  mkLabel(child, "── Historique ──", 8, Y)
  Y = Y - 22

  local histFrame = CreateFrame("Frame", nil, child, "BackdropTemplate")
  histFrame:SetSize(CONTENT_W - 20, 130)
  histFrame:SetPoint("TOPLEFT", 8, Y)
  histFrame:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1 })
  histFrame:SetBackdropColor(0.04, 0.03, 0.01, 0.90)
  histFrame:SetBackdropBorderColor(GM[1], GM[2], GM[3], 0.40)

  W.historyText = histFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  W.historyText:SetPoint("TOPLEFT", 6, -4)
  W.historyText:SetWidth(CONTENT_W - 36)
  W.historyText:SetJustifyH("LEFT")
  W.historyText:SetJustifyV("TOP")
  W.historyText:SetTextColor(TL[1], TL[2], TL[3], 1)
  W.historyText:SetText("")

  -- Update child height to fit content
  child:SetHeight(math.abs(Y) + 160)

  return sf
end

---------------------------------------------------------------------------
-- Sidebar highlight
---------------------------------------------------------------------------

local function highlightSidebar(idx)
  ensureTheme()
  local GB = C.GOLD_BRIGHT or {1.00,0.82,0.22}
  for i = 1, 8 do
    local row = sidebarRows[i]
    if row and row._sel then
      if i == idx then
        row._sel:SetColorTexture(GB[1], GB[2], GB[3], 0.90)
      else
        row._sel:SetColorTexture(GB[1], GB[2], GB[3], 0)
      end
    end
  end
  -- Update marker icon in content area
  local markers = Shared.RAID_MARKERS or {}
  local m = markers[idx] or {}
  if W._markerIcon then
    if m.texture and m.texture ~= "" then
      W._markerIcon:SetTexture(m.texture)
    else
      W._markerIcon:SetTexture(nil)
    end
  end
end

---------------------------------------------------------------------------
-- Marker selection
---------------------------------------------------------------------------

function GMMarkersUI.SelectMarker(idx)
  if idx < 1 or idx > 8 then return end

  -- Unregister previous listener
  if currentUnreg then pcall(currentUnreg); currentUnreg = nil end

  currentIdx = idx
  highlightSidebar(idx)
  refreshContent(idx)

  -- Register new listener
  currentUnreg = GMMarkers.OnChange(idx, function()
    if currentIdx == idx then refreshContent(idx) end
  end)
end

---------------------------------------------------------------------------
-- Window construction
---------------------------------------------------------------------------

local function buildWindow()
  ensureTheme()
  local flat    = (TEX and TEX.FLAT) or "Interface/Buttons/WHITE8x8"
  local BG_DARK = (TEX and TEX.BG_DARK)    or "Interface/DialogFrame/UI-DialogBox-Background-Dark"
  local BD_GOLD = (TEX and TEX.BORDER_GOLD) or "Interface/DialogFrame/UI-DialogBox-Gold-Border"
  local CD      = C.BROWN_DEEP  or {0.08,0.05,0.02}
  local GM      = C.GOLD_MUTED  or {0.55,0.42,0.18}
  local TT      = C.TEXT_TITLE  or {1.00,0.84,0.30}

  local SIDEBAR_W = 148
  local WIN_W     = 720
  local WIN_H     = 540

  frame = CreateFrame("Frame", "GrosOrteilGMFrame", UIParent, "BackdropTemplate")
  frame:SetSize(WIN_W, WIN_H)
  frame:SetPoint("CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame:Hide()

  frame:SetBackdrop({
    bgFile    = BG_DARK,
    edgeFile  = BD_GOLD,
    tile      = true, tileSize = 32, edgeSize = 32,
    insets    = { left=10, right=10, top=10, bottom=10 },
  })
  frame:SetBackdropColor(CD[1], CD[2], CD[3], 0.98)
  frame:SetBackdropBorderColor(1, 1, 1, 1)

  -- Register in UISpecialFrames so ESC closes it.
  table.insert(UISpecialFrames, "GrosOrteilGMFrame")

  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetTextColor(TT[1], TT[2], TT[3], 1)
  title:SetText("Tableau de Bord MJ")

  -- Close button
  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  if closeBtn and closeBtn.SetPoint then
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
  end

  buildSidebar(frame)
  buildContent(frame, SIDEBAR_W)

  return frame
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function ns.GMMarkersUI_Show(show)
  if not frame then return end
  if show and not isGM() then
    print("|cFF00FF00GrosOrteil|r : Vous devez être chef ou assistant de groupe pour ouvrir le tableau MJ.")
    return
  end
  if show then frame:Show() else frame:Hide() end
end

function ns.GMMarkersUI_Init()
  buildWindow()
  GMMarkersUI.frame = frame

  -- Event frame for GM role changes
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("GROUP_ROSTER_UPDATE")
  ev:RegisterEvent("RAID_ROSTER_UPDATE")
  ev:RegisterEvent("PARTY_LEADER_CHANGED")
  ev:SetScript("OnEvent", function() updateGMVisibility() end)

  -- Select first marker by default
  GMMarkersUI.SelectMarker(1)
end
