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
  DISCPRIEST   = { label = "Points de foi et insanité",      r = 0.95, g = 0.92, b = 0.80 },
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
    { idx = 2, label = "Seringues",   r = 0.20, g = 0.75, b = 0.85 },
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
  DISCPRIEST = {
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
  ROGUE        = "Furtif",
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
  DISCPRIEST   = "Prêtre discipline",
}

---------------------------------------------------------------------------
-- Class tab icons. 
---------------------------------------------------------------------------
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

Shared.CLASS_ICONS = {
  WARRIOR      = { texture = "Interface\\Icons\\inv12_apextalent_rogue_gravedigger", coords = { 0.07, 0.93, 0.07, 0.93 } },
  MAGE         = { texture = "Interface\\Icons\\inv12_apextalent_mage_touchofthearchmage", coords = { 0.07, 0.93, 0.07, 0.93 } },
  ROGUE        = { texture = "Interface\\Icons\\inv12_apextalent_rogue_ancientarts", coords = { 0.07, 0.93, 0.07, 0.93 } },
  DRUID        = { texture = "Interface\\Icons\\inv12_ability_druid_flourish_empowered", coords = { 0.07, 0.93, 0.07, 0.93 } },
  HUNTER       = { texture = CLASS_SHEET, coords = { 0.07, 0.93, 0.07, 0.93 } },
  SHAMAN       = { texture = "Interface\\Icons\\inv12_apextalent_shaman_stormstreamtotem", coords = { 0.07, 0.93, 0.07, 0.93 } },
  PRIEST       = { texture = "Interface\\Icons\\ability_priest_ascendance", coords = { 0.07, 0.93, 0.07, 0.93 } },
  WARLOCK      = { texture = "Interface\\Icons\\inv12_ability_warlock_ritualofsummoning", coords = { 0.07, 0.93, 0.07, 0.93 } },
  PALADIN      = { texture = "Interface\\Icons\\inv12_ability_paladin_hammerofwrath", coords = { 0.07, 0.93, 0.07, 0.93 } },
  DEATHKNIGHT  = { texture = CLASS_SHEET, coords = { 0.07, 0.93, 0.07, 0.93 } },
  MONK         = { texture = "Interface\\Icons\\inv12_apextalent_monk_spiritfont", coords = { 0.07, 0.93, 0.07, 0.93 } },
  DEMONHUNTER  = { texture = CLASS_SHEET, coords = { 0.07, 0.93, 0.07, 0.93 } },
  EVOKER       = { texture = CLASS_SHEET, coords = { 0.07, 0.93, 0.07, 0.93 } },

  MEDIC = {
    texture = "Interface\\Icons\\inv_misc_emberweavebandagelight",
    coords  = { 0.07, 0.93, 0.07, 0.93 },
  },
  SHADOWPRIEST = {
    texture = "Interface\\Icons\\inv12_ability_priest_powerwordmadness_eye",
    coords  = { 0.07, 0.93, 0.07, 0.93 },
  },
  DISCPRIEST = {
    texture = "Interface\\Icons\\inv12_apextalent_druid_ascendanceeclipses",
    coords  = { 0.07, 0.93, 0.07, 0.93 },
  },
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
-- Classes that use the Insanité (res2) mechanic: a bar that may exceed its
-- max, feeds a base-attack bonus at tiers 11 (+10) / 18 (+15), and gains +2
-- from a resource change. Shadow and Discipline priests share it.
---------------------------------------------------------------------------
local INSANITY_CLASSES = { SHADOWPRIEST = true, DISCPRIEST = true }
function Shared.HasInsanity(classKey)
  return INSANITY_CLASSES[classKey] == true
end

---------------------------------------------------------------------------
-- Wound cap from a wounds table ({hit25=bool, hit10=bool}): healing is
-- capped at 25% of max HP after a 10% wound, 50% after a 25% wound.
-- The single source of truth — Core, the main UI, the popup and the raid
-- panel all derive the cap through here.
---------------------------------------------------------------------------
function Shared.WoundCap(wounds)
  if type(wounds) == "table" then
    if wounds.hit10 then return 0.25 end
    if wounds.hit25 then return 0.50 end
  end
  return 1.0
end

---------------------------------------------------------------------------
-- Fixed display maxima for special class resources (idx 2):
-- Warlock Corruption caps at 60, priest Insanity (Shadow + Discipline)
-- displays out of 25 (the value itself may exceed it), Mage Arcane Charge
-- caps at 8. Returns the fixed max, or nil when there's no special cap.
---------------------------------------------------------------------------
local RES_DISPLAY_MAX = {
  WARLOCK      = { [2] = 60 },
  SHADOWPRIEST = { [2] = 25 },
  DISCPRIEST   = { [2] = 25 },
  MAGE         = { [2] = 8 },
}
function Shared.GetResDisplayMax(classKey, idx)
  local byIdx = RES_DISPLAY_MAX[classKey]
  return byIdx and byIdx[idx] or nil
end

---------------------------------------------------------------------------
-- Resource threshold marker definitions per class/idx — shared by the main
-- UI bars, the target popup, the hover popup and the raid panel cards.
-- Each def: { pct, r, g, b, a, w }.
---------------------------------------------------------------------------
-- Insanité (display cap 25): paliers 2 / 11 / 18, folie à 25. Shared by both
-- priest specs that carry the bar (Shadow + Discipline).
local INSANITY_MARKERS = {
  { pct = 2/25,  r = 0.65, g = 0.95, b = 0.65, a = 0.45, w = 2 },
  { pct = 11/25, r = 1.00, g = 0.82, b = 0.22, a = 0.55, w = 2 },
  { pct = 18/25, r = 1.00, g = 0.55, b = 0.10, a = 0.60, w = 2 },
  { pct = 25/25, r = 1.00, g = 0.25, b = 0.25, a = 0.70, w = 3 },
}
local RES_MARKER_DEFS = {
  WARLOCK = { [2] = {   -- Corruption (cap 60)
    { pct = 10/60, r = 0.65, g = 0.95, b = 0.65, a = 0.55, w = 2 },
    { pct = 25/60, r = 1.00, g = 0.82, b = 0.22, a = 0.55, w = 2 },
    { pct = 45/60, r = 1.00, g = 0.25, b = 0.25, a = 0.65, w = 3 },
  } },
  SHADOWPRIEST = { [2] = INSANITY_MARKERS },
  DISCPRIEST   = { [2] = INSANITY_MARKERS },
  MAGE = { [2] = {   -- Charge arcanique (cap 8)
    { pct = 4/8, r = 1.00, g = 0.82, b = 0.22, a = 0.65, w = 2 },
    { pct = 8/8, r = 0.75, g = 0.30, b = 1.00, a = 0.80, w = 3 },
  } },
}
local EMPTY_DEFS = {}
function Shared.GetResMarkerDefs(classKey, idx)
  local byIdx = RES_MARKER_DEFS[classKey]
  return byIdx and byIdx[idx] or EMPTY_DEFS
end

---------------------------------------------------------------------------
-- WoW "secret" values (unit names/GUIDs handed back under addon taint):
-- any compare/concat/string-op on one raises. Treat them as absent data.
---------------------------------------------------------------------------
local issecretvalue = rawget(_G, "issecretvalue")
function Shared.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

---------------------------------------------------------------------------
-- Normalized roster key: short character name (realm stripped), lowercase,
-- spaces removed. Used wherever member lists are matched by name.
---------------------------------------------------------------------------
function Shared.NormalizeNameKey(name)
  if Shared.IsSecret(name) then return nil end
  if type(name) ~= "string" then return nil end
  local base = name:match("^([^%-]+)") or name
  return base:lower():gsub("%s+", "")
end

---------------------------------------------------------------------------
-- Compare two addon versions ("120001", "1.4.10", 120001...): digit groups
-- are compared numerically left to right, missing groups count as 0.
-- Returns -1/0/1, or nil when either side is unusable (no digits / secret).
---------------------------------------------------------------------------
function Shared.CompareVersions(a, b)
  local function parts(v)
    if Shared.IsSecret(v) then return nil end
    if type(v) == "number" then v = tostring(v) end
    if type(v) ~= "string" then return nil end
    local out = {}
    for d in v:gmatch("%d+") do out[#out + 1] = tonumber(d) end
    if #out == 0 then return nil end
    return out
  end
  local pa, pb = parts(a), parts(b)
  if not pa or not pb then return nil end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return (x > y) and 1 or -1 end
  end
  return 0
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
-- Apply a class's icon (texture + coords) to a texture object. Look up the
-- entry in Shared.CLASS_ICONS to customize what's drawn for a given class.
---------------------------------------------------------------------------
function Shared.SetClassIconTexCoords(tex, classKey)
  if not tex or not tex.SetTexCoord then return end
  local def = Shared.CLASS_ICONS[classKey]
  tex:SetTexture((def and def.texture) or CLASS_SHEET)
  local c = def and def.coords
  if c then
    tex:SetTexCoord(c[1], c[2], c[3], c[4])
  else
    tex:SetTexCoord(0, 1, 0, 1)
  end
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

function Shared.UpdateHpShieldOverlays(blockOverlay, magicOverlay, bar, hpNow, maxHp, blockValue, magicValue, barWidth)
  if not bar then return end
  local wBar = barWidth or (bar:GetWidth()) or 0
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
-- Bar frame factory: dark backdrop + StatusBar, used by popup stat rows
-- Returns: { frame=BackdropFrame, bar=StatusBar }
---------------------------------------------------------------------------
function Shared.MakeBarFrame(parent, w, h)
  local barFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  barFrame:SetSize(w, h)
  barFrame:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  if ns.Theme then ns.Theme.ApplyNoteSkin(barFrame) end

  local bar = CreateFrame("StatusBar", nil, barFrame)
  bar:SetAllPoints(barFrame)
  bar:SetStatusBarTexture(ns.Theme and ns.Theme.Textures.STATUSBAR or "Interface\\Buttons\\WHITE8x8")
  if ns.Theme then ns.Theme.WatchBar(bar) end
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(0)

  return { frame = barFrame, bar = bar }
end

---------------------------------------------------------------------------
-- HP threshold + cap markers, identical across main UI, popup and hover
-- Returns: markers={[1]=50%, [2]=25%, [3]=10%}, capMarker=100%
---------------------------------------------------------------------------
local HP_MARKER_DEFS = {
  { pct = 0.50, r = 1.0, g = 1.0,  b = 1.0,  a = 0.35, w = 2 },
  { pct = 0.25, r = 1.0, g = 0.65, b = 0.10, a = 0.45, w = 2 },
  { pct = 0.10, r = 1.0, g = 0.15, b = 0.15, a = 0.55, w = 2 },
}
Shared.HP_MARKER_DEFS = HP_MARKER_DEFS
function Shared.MakeHpThresholdMarkers(bar)
  local markers = {}
  for i = 1, #HP_MARKER_DEFS do
    local d = HP_MARKER_DEFS[i]
    markers[i] = Shared.MakeMarker(bar, d.pct, d.r, d.g, d.b, d.a, d.w)
  end
  local capMarker = Shared.MakeMarker(bar, 1.0, 1.0, 0.9, 0.2, 0.7, 3)
  return markers, capMarker
end

---------------------------------------------------------------------------
-- Floating combat text: short-lived text rising and fading above a frame,
-- like the game's floating combat text ("-35", "+35", "Esquivé", "Blocage
-- total"). Returns show(text, r, g, b); fontstrings are pooled and reused.
---------------------------------------------------------------------------
function Shared.AttachFloatingText(anchor)
  local host = CreateFrame("Frame", nil, anchor)
  host:SetAllPoints(anchor)
  host:SetFrameLevel((anchor:GetFrameLevel() or 0) + 10)

  local pool = {}

  local function acquire()
    for i = 1, #pool do
      if not pool[i].anim:IsPlaying() then return pool[i] end
    end
    local fs = host:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetPoint("BOTTOM", host, "TOP", 0, 2)
    fs:Hide()

    local anim = fs:CreateAnimationGroup()
    local move = anim:CreateAnimation("Translation")
    move:SetOffset(0, 30)
    move:SetDuration(1.2)
    move:SetSmoothing("OUT")
    local fade = anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(0.5)
    fade:SetDuration(0.7)
    anim:SetScript("OnFinished", function() fs:Hide() end)

    local entry = { fs = fs, anim = anim }
    pool[#pool + 1] = entry
    return entry
  end

  return function(text, r, g, b)
    local e = acquire()
    e.anim:Stop()
    e.fs:SetText(text)
    e.fs:SetTextColor(r or 1, g or 1, b or 1, 1)
    e.fs:SetAlpha(1)
    e.fs:Show()
    e.anim:Play()
  end
end

---------------------------------------------------------------------------
-- French class name lookup
---------------------------------------------------------------------------
function Shared.GetClassNameFr(classKey)
  local key = type(classKey) == "string" and classKey or ""
  return Shared.CLASS_NAMES_FR[key] or (key ~= "" and key) or "Inconnue"
end

---------------------------------------------------------------------------
-- High-resolution class emblems: the round Legion class-hall crests
-- (transparent background, crisp at large sizes). Custom classes map to the
-- closest real class; falls back to the icon sheet when the atlas is missing.
---------------------------------------------------------------------------
local CLASS_EMBLEM_ATLAS = {
  WARRIOR      = "classhall-circle-warrior",
  MAGE         = "classhall-circle-mage",
  ROGUE        = "classhall-circle-rogue",
  DRUID        = "classhall-circle-druid",
  HUNTER       = "classhall-circle-hunter",
  SHAMAN       = "classhall-circle-shaman",
  PRIEST       = "classhall-circle-priest",
  SHADOWPRIEST = "classhall-circle-priest",
  DISCPRIEST   = "classhall-circle-priest",
  WARLOCK      = "classhall-circle-warlock",
  PALADIN      = "classhall-circle-paladin",
  DEATHKNIGHT  = "classhall-circle-deathknight",
  MONK         = "classhall-circle-monk",
  DEMONHUNTER  = "classhall-circle-demonhunter",
  MEDIC        = "classhall-circle-priest",
}

function Shared.SetClassEmblem(tex, classKey)
  if not tex then return false end
  local atlas = CLASS_EMBLEM_ATLAS[classKey]
  local cTexture = rawget(_G, "C_Texture")
  local info = atlas and cTexture and cTexture.GetAtlasInfo and cTexture.GetAtlasInfo(atlas)
  if info and tex.SetAtlas then
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetAtlas(atlas, false)
    return true
  end
  Shared.SetClassIconTexCoords(tex, classKey)
  return false
end

---------------------------------------------------------------------------
-- Corner size-grip, same UX as the main window's: drag the bottom-right
-- grabber to resize, right-click it to restore the default size, current
-- size shown in the centre while dragging, persisted via opts.save(scale).
-- These fixed-layout windows rescale their content instead of reflowing it,
-- so the "size" is a scale factor (saved value 1 = default).
-- opts.canResize can veto a resize (e.g. secure children under combat lockdown).
---------------------------------------------------------------------------
local SCALE_MIN, SCALE_MAX = 0.6, 1.8

-- Change a frame's scale while keeping its top-left corner visually fixed
-- (GetLeft/GetTop and SetPoint offsets are both in frame-local scale units).
local function setScaleKeepTopLeft(frame, newScale)
  local old = frame:GetScale() or 1
  if newScale == old then return end
  local left, top = frame:GetLeft(), frame:GetTop()
  frame:SetScale(newScale)
  if left and top then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", frame:GetParent() or UIParent, "BOTTOMLEFT",
      left * old / newScale, top * old / newScale)
  end
end

function Shared.AttachScaleGrip(frame, opts)
  opts = opts or {}

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
  grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)

  grip:SetScript("OnEnter", function(self)
    local tip = rawget(_G, "GameTooltip")
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    tip:ClearLines()
    tip:AddLine("Redimensionner", 1.00, 0.84, 0.30)
    tip:AddLine("Glisser : ajuster la taille de la fenêtre", 1, 1, 1, true)
    tip:AddLine("Clic droit : taille par défaut", 0.72, 0.62, 0.50, true)
    tip:Show()
  end)
  grip:SetScript("OnLeave", function()
    local tip = rawget(_G, "GameTooltip")
    if tip then tip:Hide() end
  end)

  local sizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  sizeLabel:SetPoint("CENTER", frame, "CENTER")
  sizeLabel:SetTextColor(1.00, 0.84, 0.30, 1)
  sizeLabel:SetShadowOffset(1, -1)
  sizeLabel:SetShadowColor(0, 0, 0, 0.80)
  sizeLabel:Hide()

  local resizing = false
  local originX, originY = 0, 0
  local baseScale, baseW, baseH = 1, 1, 1

  local function save(s)
    if opts.save then opts.save(s) end
  end

  local function stopResize()
    grip:SetScript("OnUpdate", nil)
    resizing = false
    sizeLabel:Hide()
    save(frame:GetScale() or 1)
  end

  local function onResizeUpdate()
    if opts.canResize and not opts.canResize() then stopResize(); return end
    local cx, cy = GetCursorPosition()
    local eff = UIParent:GetEffectiveScale()
    local dx = (cx - originX) / eff
    local dy = (cy - originY) / eff
    -- The bottom-right corner follows the cursor on both axes; averaging the
    -- two implied scales makes a diagonal drag feel natural.
    local sX = baseScale + dx / baseW
    local sY = baseScale - dy / baseH
    local s = (sX + sY) / 2
    if s < SCALE_MIN then s = SCALE_MIN elseif s > SCALE_MAX then s = SCALE_MAX end
    setScaleKeepTopLeft(frame, s)
    sizeLabel:SetText(math.floor(s * 100 + 0.5) .. " %")
  end

  grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    if opts.canResize and not opts.canResize() then return end
    resizing = true
    originX, originY = GetCursorPosition()
    baseScale = frame:GetScale() or 1
    baseW = frame:GetWidth() or 1
    baseH = frame:GetHeight() or 1
    sizeLabel:Show()
    grip:SetScript("OnUpdate", onResizeUpdate)
  end)

  grip:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and resizing then
      stopResize()
    elseif button == "RightButton" then
      if opts.canResize and not opts.canResize() then return end
      setScaleKeepTopLeft(frame, 1)
      save(1)
    end
  end)

  -- The window can vanish mid-drag (target change hides the popup); a hidden
  -- grip stops receiving OnUpdate/OnMouseUp, so settle the resize here.
  grip:SetScript("OnHide", function()
    if resizing then stopResize() end
  end)

  -- Restore the persisted scale (opts.load returns it, or nil for default).
  if opts.load then
    local s = tonumber(opts.load())
    if s and s > 0 then
      if s < SCALE_MIN then s = SCALE_MIN elseif s > SCALE_MAX then s = SCALE_MAX end
      frame:SetScale(s)
    end
  end

  return grip
end
