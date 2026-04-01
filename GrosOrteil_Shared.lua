---@diagnostic disable: undefined-global
-- GrosOrteil/Shared.lua
-- Shared data tables and utility functions used by multiple modules.
local _, ns = ...

local Shared = {}
ns.Shared = Shared

---------------------------------------------------------------------------
-- Class style definitions (label, color per class)
---------------------------------------------------------------------------
Shared.CLASS_STYLES = {
  MEDIC        = { label = "Fournitures",                    r = 0.85, g = 0.12, b = 0.12 },
  PALADIN      = { label = "Puissance sacrée",               r = 1.00, g = 0.82, b = 0.22 },
  PRIEST       = { label = "Puissance sacrée",               r = 1.00, g = 0.82, b = 0.22 },
  SHADOWPRIEST = { label = "Points de foi et insanité",      r = 0.60, g = 0.20, b = 0.85 },
  MAGE         = { label = "Mana",                           r = 0.20, g = 0.55, b = 1.00 },
  ROGUE        = { label = "Énergie",                        r = 1.00, g = 0.90, b = 0.10 },
  WARLOCK      = { label = "Énergie gangrénée, Corruption et Fragments d'âme", r = 0.20, g = 0.85, b = 0.25 },
  DRUID        = { label = "Esprit",                         r = 1.00, g = 0.55, b = 0.10 },
  MONK         = { label = "Chi",                            r = 0.55, g = 1.00, b = 0.55 },
  SHAMAN       = { label = "Points élémentaires",            r = 0.00, g = 0.44, b = 0.87 },
}

---------------------------------------------------------------------------
-- Resource profiles per class
---------------------------------------------------------------------------
Shared.RES_PROFILES_BY_CLASS = {
  WARRIOR = {},
  MEDIC = {
    { idx = 1, label = "Fournitures", r = 0.85, g = 0.12, b = 0.12 },
  },
  WARLOCK = {
    { idx = 1, label = "Énergie gangrénée", r = 0.20, g = 0.85, b = 0.25 },
    { idx = 2, label = "Corruption",        r = 0.55, g = 0.20, b = 0.85 },
    { idx = 3, label = "Fragments d'âme",   r = 0.85, g = 0.15, b = 0.25 },
  },
  MAGE = {
    { idx = 1, label = "Mana",             r = 0.20, g = 0.55, b = 1.00 },
    { idx = 2, label = "Charge arcanique", r = 0.75, g = 0.30, b = 1.00 },
  },
  SHADOWPRIEST = {
    { idx = 1, label = "Points de foi", r = 1.00, g = 1.00, b = 1.00 },
    { idx = 2, label = "Insanité",      r = 0.60, g = 0.20, b = 0.85 },
  },
  SHAMAN = {
    { idx = 1, label = "Terre", r = 0.55, g = 0.35, b = 0.15 },
    { idx = 2, label = "Air",   r = 0.60, g = 0.95, b = 0.95 },
    { idx = 3, label = "Eau",   r = 0.20, g = 0.55, b = 1.00 },
    { idx = 4, label = "Feu",   r = 1.00, g = 0.35, b = 0.10 },
  },
}

---------------------------------------------------------------------------
-- French class names (for display)
---------------------------------------------------------------------------
Shared.CLASS_NAMES_FR = {
  WARRIOR      = "Classique",
  MAGE         = "Mage",
  ROGUE        = "Voleur",
  DRUID        = "Druide",
  HUNTER       = "Chasseur",
  SHAMAN       = "Chaman",
  PRIEST       = "Prêtre",
  WARLOCK      = "Démoniste",
  PALADIN      = "Paladin",
  DEATHKNIGHT  = "Chevalier de la mort",
  MONK         = "Moine",
  DEMONHUNTER  = "Chasseur de démons",
  EVOKER       = "Évocateur",
  MEDIC        = "Médecin",
  SHADOWPRIEST = "Prêtre ombre",
}

---------------------------------------------------------------------------
-- Class icon texture coordinates (standard WoW class icon sheet)
---------------------------------------------------------------------------
Shared.CLASS_ICON_COORDS = {
  WARRIOR      = { 0,    0.25, 0,    0.25 },
  MAGE         = { 0.25, 0.50, 0,    0.25 },
  ROGUE        = { 0.50, 0.75, 0,    0.25 },
  DRUID        = { 0.75, 1.00, 0,    0.25 },
  HUNTER       = { 0,    0.25, 0.25, 0.50 },
  SHAMAN       = { 0.25, 0.50, 0.25, 0.50 },
  PRIEST       = { 0.50, 0.75, 0.25, 0.50 },
  WARLOCK      = { 0.75, 1.00, 0.25, 0.50 },
  PALADIN      = { 0,    0.25, 0.50, 0.75 },
  DEATHKNIGHT  = { 0.25, 0.50, 0.50, 0.75 },
  MONK         = { 0.50, 0.75, 0.50, 0.75 },
  DEMONHUNTER  = { 0.75, 1.00, 0.50, 0.75 },
  EVOKER       = { 0,    0.25, 0.75, 1.00 },
}

---------------------------------------------------------------------------
-- Resource index → state key mapping
---------------------------------------------------------------------------
function Shared.GetKeysForIdx(i)
  if i == 1 then return "res",  "maxRes"  end
  if i == 2 then return "res2", "maxRes2" end
  if i == 3 then return "res3", "maxRes3" end
  if i == 4 then return "res4", "maxRes4" end
  if i == 5 then return "auth", "maxAuth" end
  return nil, nil
end

---------------------------------------------------------------------------
-- Build the active resource profile for a given state
---------------------------------------------------------------------------
function Shared.GetResProfile(state)
  local classKey = state and state.classKey
  local profiles = Shared.RES_PROFILES_BY_CLASS
  local styles   = Shared.CLASS_STYLES
  local p = (type(classKey) == "string") and profiles[classKey] or nil
  local out = {}

  if p then
    for i = 1, #p do out[#out + 1] = p[i] end
  else
    local s = (type(classKey) == "string") and styles[classKey] or nil
    if s then
      out[1] = { idx = 1, label = s.label or "Ressource", r = s.r or 0.2, g = s.g or 0.55, b = s.b or 1.0 }
    else
      out[1] = { idx = 1, label = "Ressource", r = 0.20, g = 0.55, b = 1.00 }
    end
  end

  if state and state.pet and state.pet.enabled and state.pet.authorityEnabled then
    out[#out + 1] = { idx = 5, label = "Points d'autorité", r = 1.00, g = 0.45, b = 0.10 }
  end

  return out
end

---------------------------------------------------------------------------
-- Round a number to the nearest integer
---------------------------------------------------------------------------
function Shared.Round(v)
  if type(v) ~= "number" then return 0 end
  if v >= 0 then return math.floor(v + 0.5) end
  return -math.floor((-v) + 0.5)
end

---------------------------------------------------------------------------
-- Round a fraction to an integer percentage
---------------------------------------------------------------------------
function Shared.RoundPct(x)
  return math.floor(x * 100 + 0.5)
end

---------------------------------------------------------------------------
-- Set class icon tex coords on a texture, with special-case icons
---------------------------------------------------------------------------
function Shared.SetClassIconTexCoords(tex, classKey)
  if not tex or not tex.SetTexCoord then return end

  if classKey == "MEDIC" then
    tex:SetTexture("Interface\\Icons\\INV_Misc_Bandage_15")
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return
  elseif classKey == "SHADOWPRIEST" then
    tex:SetTexture("Interface\\Icons\\Spell_Shadow_Shadowform")
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return
  end

  tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
  local c = Shared.CLASS_ICON_COORDS[classKey]
  if not c then
    tex:SetTexCoord(0, 1, 0, 1)
    return
  end
  tex:SetTexCoord(c[1], c[2], c[3], c[4])
end

---------------------------------------------------------------------------
-- Bar marker helpers (shared between main UI and target popup)
---------------------------------------------------------------------------
function Shared.MakeMarker(bar, pct, r, g, b, a, w)
  local t = bar:CreateTexture(nil, "OVERLAY")
  t:SetTexture("Interface/Buttons/WHITE8x8")
  t:SetWidth(w or 2)
  t:SetHeight(bar:GetHeight() or 14)
  t:SetColorTexture(r or 1, g or 1, b or 1, a or 0.45)
  t.pct = pct or 0
  t:Hide()
  return t
end

function Shared.HideMarkers(markers)
  if not markers then return end
  for i = 1, #markers do
    if markers[i] then markers[i]:Hide() end
  end
end

function Shared.PositionMarkers(markers, bar)
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

---------------------------------------------------------------------------
-- Shield overlay helpers
---------------------------------------------------------------------------
function Shared.HideOverlay(tex)
  if not tex then return end
  tex:Hide()
  tex:SetAlpha(0)
  tex:SetWidth(0.001)
end

function Shared.UpdateHpShieldOverlays(blockOverlay, magicOverlay, bar, hpNow, maxHp, blockValue, magicValue)
  if not bar then return end
  local wBar = bar:GetWidth() or 0
  local hpForOverlay = math.max(0, hpNow or 0)
  local block = math.max(0, blockValue or 0)
  local magic = math.max(0, magicValue or 0)
  local total = math.min(hpForOverlay, block + magic)

  if maxHp <= 0 or wBar <= 0 or total <= 0 then
    Shared.HideOverlay(blockOverlay)
    Shared.HideOverlay(magicOverlay)
    return
  end

  local hpFrac = hpForOverlay / maxHp
  if hpFrac < 0 then hpFrac = 0 elseif hpFrac > 1 then hpFrac = 1 end
  local endX = wBar * hpFrac

  local magicShown = math.min(magic, total)
  local blockShown = math.min(block, total - magicShown)

  local magicW = wBar * (magicShown / maxHp)
  local blockW = wBar * (blockShown / maxHp)

  if magicOverlay and magicW > 0.5 and endX > 0.5 then
    magicOverlay:Show()
    magicOverlay:SetAlpha(0.75)
    magicOverlay:ClearAllPoints()
    magicOverlay:SetPoint("TOPLEFT", bar, "TOPLEFT", math.max(0, endX - magicW), 0)
    magicOverlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", math.max(0, endX - magicW), 0)
    magicOverlay:SetWidth(magicW)
  else
    Shared.HideOverlay(magicOverlay)
  end

  if blockOverlay and blockW > 0.5 and endX > 0.5 then
    local startX = math.max(0, endX - magicW - blockW)
    blockOverlay:Show()
    blockOverlay:SetAlpha(0.65)
    blockOverlay:ClearAllPoints()
    blockOverlay:SetPoint("TOPLEFT", bar, "TOPLEFT", startX, 0)
    blockOverlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", startX, 0)
    blockOverlay:SetWidth(blockW)
  else
    Shared.HideOverlay(blockOverlay)
  end
end

---------------------------------------------------------------------------
-- French class name lookup
---------------------------------------------------------------------------
function Shared.GetClassNameFr(classKey)
  local key = type(classKey) == "string" and classKey or ""
  return Shared.CLASS_NAMES_FR[key] or (key ~= "" and key) or "Inconnue"
end
