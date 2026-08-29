---@diagnostic disable: undefined-global
local _, ns = ...

local RaidPanel = {}
ns.RaidPanel = RaidPanel

local Shared    = ns.Shared
local RaidMeter = ns.RaidMeter  -- loaded just before this file (see .toc)

local type   = type
local math   = math
local string = string
local table  = table
local ipairs = ipairs

-- Stable WoW APIs: captured once at load (taint-neutral reads). Roster APIs are
-- looked up lazily inside getRaidMembers so the offline tests can swap them.
local CreateFrame = rawget(_G, "CreateFrame")
local UIParent    = rawget(_G, "UIParent")

-- ── Layout constants ──────────────────────────────────────────────────────────

local PANEL_W      = 360
local PANEL_H      = 580
local EDGE         = 4      -- gold tooltip-border inset around the board
local WOOD         = 20     -- wooden rail thickness (bulletin-board frame)
local PAD          = 8      -- gap between the rails and the cards
local PLAQUE_H     = 30     -- header plaque height
local FOOTER_H     = 14
local CONTENT_X    = EDGE + WOOD + PAD
local SCROLL_W     = PANEL_W - CONTENT_X * 2
local CARD_PAD     = 10
local ACCENT_W     = 3      -- class-colored stripe on the left card edge
local ICON_SIZE    = 16
local BAR_W        = SCROLL_W - CARD_PAD * 2
local ROW_H        = 15
local ROW_GAP      = 3
local NAME_H       = 16
local STATUS_H     = 16
local SECTION_GAP  = 7
local CARD_TOP_PAD = 6
local CARD_BOT_PAD = 7
local MAX_RES_BARS = 5

-- Pet sub-cards: smaller, indented under the owner card, and never draggable
-- on their own — they follow the owner card wherever it is dropped.
local PET_INDENT = 16
local PET_W      = SCROLL_W - PET_INDENT
local PET_BAR_W  = PET_W - CARD_PAD * 2
local PET_GAP    = 2
local PET_NAME_H = 14
local PET_COLOR      = { 0.95, 0.62, 0.18 }   -- warm orange, same as the popup pet accent
local PET_DEAD_COLOR = { 0.50, 0.32, 0.10 }

-- View switcher (Groupe / Compteur) and the meter view.
local VIEWTAB_H   = 22
local METERBAR_H  = 24
local METER_ROW_H = 24
local SCROLL_TOP_GROUP = EDGE + 6 + PLAQUE_H + 4 + VIEWTAB_H + PAD
local SCROLL_TOP_METER = SCROLL_TOP_GROUP + METERBAR_H + 4
local SCROLL_BOT       = EDGE + WOOD + 3 + FOOTER_H + 4

local HP_COLOR        = { 0.85, 0.16, 0.18 }
local HP_DEAD_COLOR   = { 0.45, 0.08, 0.09 }
local PLACEHOLDER_COL = { 0.30, 0.30, 0.32 }
local NAME_DEFAULT    = { 0.95, 0.82, 0.30 }
local CREAMY_BROWN    = { 0.48, 0.39, 0.32 }   -- TRP3's backdrop border color
local GOLD            = { 1.00, 0.675, 0.125 }
local CARD_BG         = { 0.085, 0.065, 0.045 }
local BORDER_AGONIE   = { 0.78, 0.16, 0.13 }
local BORDER_STAB     = { 0.28, 0.68, 0.30 }

-- HP threshold markers (50% / 25% / 10%) — same definitions everywhere.
local HP_MARKER_DEFS = Shared.HP_MARKER_DEFS

-- Cards are styled as tooltip "notes" pinned on the parchment board.
local BACKDROP_CARD = {
  bgFile   = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BACKDROP_PLAQUE = {
  bgFile   = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- ── Pure data extraction (testable offline, no WoW frames) ─────────────────────

local normalizeKey = Shared.NormalizeNameKey

-- Resource threshold markers per class/idx — single source of truth in Shared.
local resMarkerDefs = Shared.GetResMarkerDefs

local function getDisplayData(name, state)
  if not state then return nil end
  local effMaxHp  = math.max(1, tonumber(state.maxHp) or 0)
  local hp        = tonumber(state.hp) or 0
  local classKey  = type(state.classKey) == "string" and state.classKey or ""
  local resources = {}
  local profile   = Shared.GetResProfile(state)
  for _, p in ipairs(profile) do
    local rk, mk  = Shared.GetKeysForIdx(p.idx)
    local cur     = tonumber(state[rk]) or 0
    local maxv    = tonumber(state[mk]) or 0
    local dispMax = Shared.GetResDisplayMax(classKey, p.idx) or maxv
    if dispMax <= 0 then dispMax = 1 end
    resources[#resources + 1] = {
      label   = p.label or "Ressource",
      cur     = math.max(0, math.min(cur, dispMax)),
      max     = dispMax,
      r = p.r, g = p.g, b = p.b,
      markers = resMarkerDefs(classKey, p.idx),
    }
  end

  local style = Shared.CLASS_STYLES and Shared.CLASS_STYLES[classKey]
  local nameColor = style and { style.r, style.g, style.b } or NAME_DEFAULT

  -- Points de Chance (gold bar, only when the character has a chance pool).
  local chMax   = tonumber(state.maxChance) or 0
  local chance  = nil
  if chMax > 0 then
    local chCur = tonumber(state.chance) or 0
    chance = { cur = math.max(0, math.min(chCur, chMax)), max = chMax }
  end

  local status = nil
  if hp == 0 then
    status = state.stabilise and "stabilise" or "agonie"
  end

  -- Pet sub-card data (only when the member has an enabled pet).
  local petData = nil
  local pet = type(state.pet) == "table" and state.pet or nil
  if pet and pet.enabled then
    local petMaxHp = math.max(1, tonumber(pet.maxHp) or 0)
    local petHp    = math.max(0, math.min(tonumber(pet.hp) or 0, petMaxHp))
    petData = {
      name     = (type(pet.name) == "string" and pet.name ~= "") and pet.name or "Familier",
      hp       = petHp,
      maxHp    = petMaxHp,
      woundCap = Shared.WoundCap(pet.wounds),
    }
  end

  return {
    pet        = petData,
    name       = name,
    classKey   = classKey,
    classLabel = Shared.GetClassNameFr(classKey),
    nameColor  = nameColor,
    hp         = hp,
    maxHp      = effMaxHp,
    resources  = resources,
    chance     = chance,
    status     = status,
  }
end

local function getRaidMembers()
  -- Read-only lazy lookups (taint-neutral) so test overrides are visible.
  local isInRaid_   = rawget(_G, "IsInRaid")
  local isInGroup_  = rawget(_G, "IsInGroup")
  local unitExists_ = rawget(_G, "UnitExists")
  local unitName_   = rawget(_G, "UnitName")

  -- A secret name (WoW hands them back under addon taint) would raise later
  -- in normalizeKey/SetText/comm sends; a nameless row is useless anyway.
  local function usableName(n)
    if n and not Shared.IsSecret(n) then return n end
    return nil
  end

  local out       = {}
  local isInRaid  = isInRaid_  and isInRaid_()
  local isInGroup = isInGroup_ and isInGroup_()
  if isInRaid then
    for i = 1, 40 do
      local u = "raid" .. i
      if unitExists_ and unitExists_(u) then
        local n = usableName(unitName_ and unitName_(u))
        if n then out[#out + 1] = { name = n, unit = u } end
      end
    end
  elseif isInGroup then
    local pn = usableName(unitName_ and unitName_("player"))
    if pn then out[1] = { name = pn, unit = "player" } end
    for i = 1, 40 do
      local u = "party" .. i
      if unitExists_ and unitExists_(u) then
        local n = usableName(unitName_ and unitName_(u))
        if n then out[#out + 1] = { name = n, unit = u } end
      end
    end
  else
    local pn = usableName(unitName_ and unitName_("player"))
    if pn then out[1] = { name = pn, unit = "player" } end
  end
  return out
end

-- Map an ordered member list to display-data, pulling each state from the cache.
-- Members without a cached state become a { name } placeholder row.
local function collectData(members)
  local list = {}
  for _, m in ipairs(members or {}) do
    local st   = ns.TargetPopup and ns.TargetPopup.GetCachedState(m.name)
    local data = (st and getDisplayData(m.name, st)) or { name = m.name }
    data.unit = m.unit  -- carried for click-to-target (nil for nameless injects)
    list[#list + 1] = data
  end
  return list
end

-- ── Pure ordering helpers (drag-to-reorder; testable offline) ──────────────────

-- Group-view sorting is deliberately kept separate from RaidMeter ranking.
-- A nil sort spec means the legacy custom/manual order is active.
local DEFAULT_SORT_SPEC = { criterion = "name", direction = "asc" }
local VALID_SORT_CRITERIA = { name = true, hp = true, resource = true, class = true }
local VALID_SORT_DIRECTIONS = { asc = true, desc = true }

local function validateSortSpec(spec)
  if type(spec) ~= "table" then return nil end
  if not VALID_SORT_CRITERIA[spec.criterion] then return nil end
  if not VALID_SORT_DIRECTIONS[spec.direction] then return nil end
  return { criterion = spec.criterion, direction = spec.direction }
end

local function normalizeSortSpec(spec, fallback)
  return validateSortSpec(spec)
      or validateSortSpec(fallback)
      or { criterion = DEFAULT_SORT_SPEC.criterion, direction = DEFAULT_SORT_SPEC.direction }
end

local function safeNormalizeName(name)
  local ok, key = pcall(normalizeKey, name)
  if not ok or type(key) ~= "string" or key == "" then return nil end
  return key
end

local function safeNumber(value)
  local ok, n = pcall(tonumber, value)
  if not ok or type(n) ~= "number" or n ~= n then return nil end
  return n
end

local function safeSortString(value)
  local ok, result = pcall(function()
    if Shared.IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
  end)
  return ok and result or nil
end

-- Extract only plain sortable values. Secret-like or malformed fields are
-- treated as missing so comparison never performs an unsafe string operation.
local function getSortValue(data, criterion)
  data = type(data) == "table" and data or {}
  local name = safeNormalizeName(data.name)
  if criterion == "name" then
    return { known = name ~= nil, primary = name, name = name }
  elseif criterion == "hp" then
    local hp, maxHp = safeNumber(data.hp), safeNumber(data.maxHp)
    if hp == nil or maxHp == nil or maxHp <= 0 then
      return { known = false, name = name }
    end
    return { known = true, primary = hp / maxHp, secondary = hp, name = name }
  elseif criterion == "resource" then
    local resources = type(data.resources) == "table" and data.resources or nil
    local primary = resources and type(resources[1]) == "table" and resources[1] or nil
    local cur = primary and safeNumber(primary.cur) or nil
    local maxv = primary and safeNumber(primary.max) or nil
    if cur == nil or maxv == nil or maxv <= 0 then
      return { known = false, name = name }
    end
    return { known = true, primary = cur / maxv, secondary = cur, name = name }
  elseif criterion == "class" then
    local classKey = safeSortString(data.classKey)
    local knownClass = classKey and Shared.CLASS_NAMES_FR
      and Shared.CLASS_NAMES_FR[classKey] ~= nil
    if not knownClass then return { known = false, name = name } end
    local label = safeSortString(data.classLabel) or classKey
    return { known = true, primary = label, name = name }
  end
  return { known = false, name = name }
end

local function tieByName(a, b)
  if a.name == b.name then return nil end
  if a.name == nil then return false end
  if b.name == nil then return true end
  return a.name < b.name
end

-- Return a new array containing the original row objects. Missing values stay
-- last in both directions; original index is the final deterministic tie-break.
local function sortDisplayData(dataList, spec)
  local normalized = normalizeSortSpec(spec)
  local decorated = {}
  for i, row in ipairs(dataList or {}) do
    decorated[i] = { row = row, index = i, value = getSortValue(row, normalized.criterion) }
  end
  table.sort(decorated, function(a, b)
    local av, bv = a.value, b.value
    if av.known ~= bv.known then return av.known end
    if av.known then
      if av.primary ~= bv.primary then
        if normalized.direction == "desc" then return av.primary > bv.primary end
        return av.primary < bv.primary
      end
      if av.secondary ~= bv.secondary then
        if av.secondary == nil then return false end
        if bv.secondary == nil then return true end
        if normalized.direction == "desc" then return av.secondary > bv.secondary end
        return av.secondary < bv.secondary
      end
    end
    local byName = tieByName(av, bv)
    if byName ~= nil then return byName end
    return a.index < b.index
  end)
  local out = {}
  for i, entry in ipairs(decorated) do out[i] = entry.row end
  return out
end

-- Move list[fromIdx] so it lands at insertion slot toIdx (slots are positions
-- in the ORIGINAL list, 1..#list+1). Returns a new list; out-of-range moves
-- return an unchanged copy.
local function moveInList(list, fromIdx, toIdx)
  local out = {}
  for i, v in ipairs(list or {}) do out[i] = v end
  local n = #out
  if type(fromIdx) ~= "number" or fromIdx < 1 or fromIdx > n then return out end
  if type(toIdx) ~= "number" then return out end
  if toIdx < 1 then toIdx = 1 elseif toIdx > n + 1 then toIdx = n + 1 end
  local v = table.remove(out, fromIdx)
  local insertAt = (toIdx > fromIdx) and (toIdx - 1) or toIdx
  table.insert(out, insertAt, v)
  return out
end

-- Apply a saved order (array of normalized name keys): members whose key
-- appears in `order` come first, in that sequence; everyone else follows in
-- roster order. Unknown keys in `order` are ignored.
local function applySavedOrder(members, order)
  members = members or {}
  if type(order) ~= "table" or #order == 0 then return members end
  local byKey, used, out = {}, {}, {}
  for _, m in ipairs(members) do
    local k = safeNormalizeName(m.name)
    if k and byKey[k] == nil then byKey[k] = m end
  end
  for _, k in ipairs(order) do
    local m = byKey[k]
    if m and not used[k] then
      used[k] = true
      out[#out + 1] = m
    end
  end
  for _, m in ipairs(members) do
    local k = safeNormalizeName(m.name)
    if not (k and used[k]) then out[#out + 1] = m end
  end
  return out
end

-- Given the displayed card slots ({top=positive offset, h=height}, in order)
-- and a cursor offset from the content top, return the insertion slot
-- (1..#slots+1) using the midpoint rule.
local function dropIndexFromOffset(slots, offsetY)
  for i, s in ipairs(slots or {}) do
    if offsetY < (s.top or 0) + (s.h or 0) / 2 then return i end
  end
  return #(slots or {}) + 1
end

-- Saved custom order lives in the per-character DB.
local function getSavedOrder()
  local db = ns.GetDB and ns.GetDB()
  if type(db) == "table" and type(db.raidPanelOrder) == "table" then
    return db.raidPanelOrder
  end
  return nil
end

local function saveOrder(names)
  local db = ns.GetDB and ns.GetDB()
  if type(db) ~= "table" then return end
  local order = {}
  for _, n in ipairs(names or {}) do
    local k = safeNormalizeName(n)
    if k then order[#order + 1] = k end
  end
  db.raidPanelOrder = order
end

-- Automatic mode is persisted as a validated spec. Manual mode is represented
-- by no raidPanelSort entry, leaving raidPanelOrder untouched and reusable.
local function resolveSortSpec(savedSort, savedOrder)
  local explicit = validateSortSpec(savedSort)
  if explicit then return explicit end
  if type(savedOrder) == "table" and #savedOrder > 0 then return nil end
  return normalizeSortSpec(nil)
end

local function persistAutomaticSort(db, spec)
  local normalized = normalizeSortSpec(spec)
  if type(db) == "table" then
    db.raidPanelSort = {
      criterion = normalized.criterion,
      direction = normalized.direction,
    }
  end
  return normalized
end

local function persistManualSort(db)
  if type(db) == "table" then db.raidPanelSort = nil end
end

local function getSavedSort()
  local db = ns.GetDB and ns.GetDB()
  return type(db) == "table" and validateSortSpec(db.raidPanelSort) or nil
end

-- ── Frame layer (WoW-only; lazily built, sections pooled to avoid leaks) ───────

local frame, scrollFrame, content, headerFs, countFs, fadeIn, fadeOut, hintFs, sortButton
local sectionPool    = {}
local petPool        = {}
local currentMembers = nil
local pendingRelayout = false  -- a relayout was requested while in combat
local currentSort, sortStateLoaded

-- View switcher + meter state.
local currentView    = "group"   -- "group" (cards) | "meter" (damage/heal)
local meterMode      = "damage"  -- "damage" | "heal"
local meterBaselines = {}        -- local-only zero points (RaidMeter.Reset)
local meterContent, meterBar, meterTotalFs, meterEmptyFs
local meterRowPool = {}
local viewTabs     = {}
local modeBtns     = {}

-- Drag-to-reorder state.
local cardSlots           = {}  -- displayed card geometry, set by layoutSections
local currentDisplayNames = {}  -- names in displayed order
local dragging, dropLine, dropSlot

-- Forward declarations: assigned in the lifecycle section below, referenced
-- from closures created in buildSection/ensureFrame (resolved at call time).
local relayout, Refresh, applyView, layoutMeter
local applyFooterHint, styleViewTabs, styleModeBtns
local updateSortButton, setAutomaticSort, setManualSort
local startCardDrag, stopCardDrag
local setScrollGeometry

local SORT_LABELS = { name = "Nom", hp = "PV", resource = "Ressource", class = "Classe" }
local SORT_MENU_CHOICES = {
  { criterion = "name",     direction = "asc"  },
  { criterion = "name",     direction = "desc" },
  { criterion = "hp",       direction = "asc"  },
  { criterion = "hp",       direction = "desc" },
  { criterion = "resource", direction = "asc"  },
  { criterion = "resource", direction = "desc" },
  { criterion = "class",    direction = "asc"  },
  { criterion = "class",    direction = "desc" },
}

local function ensureSortState()
  if sortStateLoaded then return end
  local db = ns.GetDB and ns.GetDB()
  local rawSaved = type(db) == "table" and db.raidPanelSort or nil
  currentSort = resolveSortSpec(rawSaved, getSavedOrder())
  sortStateLoaded = true
end

local function sortDescription(spec)
  if not spec then return "Ordre manuel" end
  local label = SORT_LABELS[spec.criterion] or "Nom"
  local direction = spec.direction == "desc" and "décroissant" or "croissant"
  return label .. " — " .. direction
end

updateSortButton = function()
  if not sortButton then return end
  ensureSortState()
  if sortButton._icon then
    if currentSort then
      sortButton._icon:SetVertexColor(1.00, 0.84, 0.30, 1)
    else
      sortButton._icon:SetVertexColor(0.62, 0.53, 0.42, 1)
    end
  end
end

setAutomaticSort = function(spec)
  local db = ns.GetDB and ns.GetDB()
  currentSort = persistAutomaticSort(db, spec)
  sortStateLoaded = true
  updateSortButton()
  if relayout then relayout() end
end

setManualSort = function()
  local db = ns.GetDB and ns.GetDB()
  persistManualSort(db)
  currentSort = nil
  sortStateLoaded = true
  updateSortButton()
end

local function openSortMenu(anchor)
  local menuUtil = rawget(_G, "MenuUtil")
  if not (menuUtil and menuUtil.CreateContextMenu) then return end
  ensureSortState()
  menuUtil.CreateContextMenu(anchor, function(_, root)
    root:CreateTitle("Trier le groupe")
    for _, choice in ipairs(SORT_MENU_CHOICES) do
      -- Copy loop values for Lua 5.1 closures.
      local criterion, direction = choice.criterion, choice.direction
      local active = currentSort and currentSort.criterion == criterion
        and currentSort.direction == direction
      local label = sortDescription(choice)
      if active then label = "|cff20ff20✓|r " .. label end
      root:CreateButton(label, function()
        setAutomaticSort({ criterion = criterion, direction = direction })
      end)
    end
  end)
end

-- The panel's cache lookup, shared with the meter.
local function getStateFor(name)
  local popup = ns.TargetPopup
  return popup and popup.GetCachedState and popup.GetCachedState(name) or nil
end

-- The local player's card renders from the same comm cache as everyone else.
-- Prime it with the live Core state so self-changes show instantly instead of
-- waiting for the addon-message loopback.
local function primeSelfCache()
  local unitName = rawget(_G, "UnitName")
  local pn = unitName and unitName("player")
  local Core = ns.Core
  local popup = ns.TargetPopup
  if pn and Core and Core.state and popup and popup.InjectState then
    popup.InjectState(pn, Core.state)
  end
end

local InCombatLockdown = rawget(_G, "InCombatLockdown")
local function inCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function applyBarText(fs)
  fs:SetTextColor(1, 1, 1, 1)
  fs:SetShadowColor(0, 0, 0, 0.95)
  fs:SetShadowOffset(1, -1)
end

-- Reuse marker textures across relayouts (textures can't be destroyed, only hidden).
local function applyMarkers(barObj, defs)
  barObj.markers = barObj.markers or {}
  local m = barObj.markers
  local bw = barObj.barW or BAR_W
  local h = barObj.bar:GetHeight()
  if not h or h <= 0 then h = ROW_H end
  for i, d in ipairs(defs) do
    local t = m[i]
    if not t then
      t = Shared.MakeMarker(barObj.bar, d.pct, d.r, d.g, d.b, d.a, d.w)
      m[i] = t
    else
      t:SetColorTexture(d.r, d.g, d.b, d.a or 0.5)
      t:SetWidth(d.w or 2)
      t.pct = d.pct
    end
    local x = bw * (d.pct or 0)
    if x < 0 then x = 0 elseif x > bw then x = bw end
    t:SetHeight(h)
    t:ClearAllPoints()
    t:SetPoint("LEFT", barObj.bar, "LEFT", x, 0)
    t:Show()
  end
  for i = #defs + 1, #m do m[i]:Hide() end
end

local function hideMarkers(barObj)
  if barObj.markers then
    for i = 1, #barObj.markers do barObj.markers[i]:Hide() end
  end
end

-- Best display name: TRP3/RP name if known, else the character name. Guarded
-- so a missing or erroring RP lib never breaks the layout.
local function resolveDisplayName(name)
  local popup = ns.TargetPopup
  if popup and popup.GetRPDisplayName then
    local ok, rp = pcall(popup.GetRPDisplayName, name)
    if ok and type(rp) == "string" and rp ~= "" then return rp end
  end
  return name
end

-- Right-click context menu: "Soigner" -> heal prompt. Uses MenuUtil when
-- present (modern retail); otherwise falls back straight to the heal prompt.
local function openMemberMenu(sec)
  local name = sec._name
  if not name or name == "" then return end
  local menuUtil = rawget(_G, "MenuUtil")
  if menuUtil and menuUtil.CreateContextMenu then
    menuUtil.CreateContextMenu(sec, function(_, root)
      root:CreateTitle(sec._displayName or name)
      root:CreateButton("Soigner", function()
        if ns.Heal and ns.Heal.PromptAndSend then ns.Heal.PromptAndSend(name) end
      end)
    end)
  elseif ns.Heal and ns.Heal.PromptAndSend then
    ns.Heal.PromptAndSend(name)
  end
end

-- Pet-card variant: "Soigner" prompts for a heal aimed at the member's PET
-- (the owner still gets the accept/refuse popup on their side).
local function openPetMenu(sec)
  local name = sec._name
  if not name or name == "" then return end
  local petName = sec._displayName or "Familier"
  local menuUtil = rawget(_G, "MenuUtil")
  if menuUtil and menuUtil.CreateContextMenu then
    menuUtil.CreateContextMenu(sec, function(_, root)
      root:CreateTitle(petName)
      root:CreateButton("Soigner", function()
        if ns.Heal and ns.Heal.PromptAndSend then ns.Heal.PromptAndSend(name, true, petName) end
      end)
    end)
  elseif ns.Heal and ns.Heal.PromptAndSend then
    ns.Heal.PromptAndSend(name, true, petName)
  end
end

local function makeBar(parent, w)
  local bf = Shared.MakeBarFrame(parent, w or BAR_W, ROW_H)
  -- Top-half sheen for the glass effect used by the main window's bars.
  local sheen = bf.bar:CreateTexture(nil, "OVERLAY", nil, -1)
  sheen:SetTexture("Interface\\Buttons\\WHITE8x8")
  sheen:SetVertexColor(1, 1, 1, 0.06)
  sheen:SetPoint("TOPLEFT",  bf.bar, "TOPLEFT",  1, -1)
  sheen:SetPoint("TOPRIGHT", bf.bar, "TOPRIGHT", -1, -1)
  sheen:SetHeight(math.max(1, math.floor(ROW_H / 2)))
  local label = bf.bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetAllPoints(bf.bar)
  label:SetJustifyH("CENTER")
  label:SetJustifyV("MIDDLE")
  applyBarText(label)
  return { frame = bf.frame, bar = bf.bar, label = label, markers = {} }
end

local function buildSection()
  -- A SecureActionButton so left-click can target the member without tainting
  -- (insecure TargetUnit is blocked by Blizzard). Bars don't enable mouse, so
  -- their clicks fall through to this parent. Right-click opens the action menu.
  local sec = CreateFrame("Button", nil, content, "SecureActionButtonTemplate, BackdropTemplate")
  sec:SetWidth(SCROLL_W)
  if sec.SetBackdrop then
    sec:SetBackdrop(BACKDROP_CARD)
    sec:SetBackdropColor(CARD_BG[1], CARD_BG[2], CARD_BG[3], 0.92)
    sec:SetBackdropBorderColor(CREAMY_BROWN[1], CREAMY_BROWN[2], CREAMY_BROWN[3], 0.90)
  end
  -- Both down and up must be registered: since 10.x, secure action buttons
  -- fire on the edge selected by the ActionButtonUseKeyDown cvar, so an
  -- "AnyUp"-only registration can silently drop the protected target click.
  sec:RegisterForClicks("AnyDown", "AnyUp")
  -- Left-click targets the `unit` attribute. Both plain and wildcard forms are
  -- set so it works with or without held modifiers.
  if sec.SetAttribute then
    sec:SetAttribute("type1", "target")
    sec:SetAttribute("*type1", "target")
  end
  -- Custom right-click menu runs in PostClick — the blessed hook for insecure
  -- work AFTER the secure action. Touching OnClick (HookScript) or any handler
  -- that runs BEFORE it (OnMouseUp) taints the click and Blizzard then blocks
  -- the protected target, which is why earlier attempts silently did nothing.
  -- With both click edges registered, only act on release so it fires once.
  sec:SetScript("PostClick", function(self, button, down)
    if button == "RightButton" and not down then openMemberMenu(self) end
  end)
  -- Drag-to-reorder: pick the card up and drop it at the gold insertion line.
  -- A plain click (no movement) still fires the secure target action; the drag
  -- only starts past the movement threshold. Disabled during combat — secure
  -- frames can't be re-anchored under lockdown anyway.
  sec:RegisterForDrag("LeftButton")
  sec:SetScript("OnDragStart", function(self) if startCardDrag then startCardDrag(self) end end)
  sec:SetScript("OnDragStop",  function(self) if stopCardDrag  then stopCardDrag(self)  end end)
  sec:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = sec.GetHighlightTexture and sec:GetHighlightTexture()
  if hl then hl:SetVertexColor(1.0, 0.95, 0.6, 0.08) end

  -- Class-colored accent stripe along the left card edge.
  local accent = sec:CreateTexture(nil, "BORDER")
  accent:SetTexture("Interface\\Buttons\\WHITE8x8")
  accent:SetPoint("TOPLEFT",    sec, "TOPLEFT",    3, -3)
  accent:SetPoint("BOTTOMLEFT", sec, "BOTTOMLEFT", 3, 3)
  accent:SetWidth(ACCENT_W)
  sec.accent = accent

  -- Class icon in front of the name.
  local icon = sec:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("TOPLEFT", sec, "TOPLEFT", CARD_PAD, -CARD_TOP_PAD)
  sec.icon = icon

  local nameFs = sec:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameFs:SetPoint("TOPLEFT",  icon, "TOPRIGHT", 5, 0)
  nameFs:SetPoint("TOPRIGHT", sec,  "TOPRIGHT", -CARD_PAD, -CARD_TOP_PAD)
  nameFs:SetHeight(NAME_H)
  nameFs:SetJustifyH("LEFT")
  nameFs:SetShadowColor(0, 0, 0, 0.9)
  nameFs:SetShadowOffset(1, -1)
  sec.nameFs = nameFs

  -- Thin class-tinted rule between the name row and the bars.
  local rule = sec:CreateTexture(nil, "ARTWORK")
  rule:SetTexture("Interface\\Buttons\\WHITE8x8")
  rule:SetPoint("TOPLEFT",  sec, "TOPLEFT",  CARD_PAD, -(CARD_TOP_PAD + NAME_H + 1))
  rule:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -CARD_PAD, -(CARD_TOP_PAD + NAME_H + 1))
  rule:SetHeight(1)
  sec.rule = rule

  -- Hover: gold border glow only (no tooltip — the footer carries the hints,
  -- and a tooltip here got in the way of click-to-target).
  sec:SetScript("OnEnter", function(self)
    if self.SetBackdropBorderColor then
      self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end
  end)
  sec:SetScript("OnLeave", function(self)
    local c = self._borderColor or CREAMY_BROWN
    if self.SetBackdropBorderColor then
      self:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 0.90)
    end
  end)

  sec.hp  = makeBar(sec)
  sec.res = {}
  for i = 1, MAX_RES_BARS do
    sec.res[i] = makeBar(sec)
  end
  sec.chanceBar = makeBar(sec)

  local statusFs = sec:CreateFontString(nil, "OVERLAY")
  statusFs:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
  statusFs:SetJustifyH("CENTER")
  statusFs:Hide()
  sec.statusFs = statusFs
  -- Soft pulse for the "EN AGONIE" state.
  if statusFs.CreateAnimationGroup then
    local pulse = statusFs:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.7)
    sec.statusPulse = pulse
  end

  return sec
end

local function getSection(i)
  local sec = sectionPool[i]
  if sec then return sec end
  sec = buildSection()
  sectionPool[i] = sec
  return sec
end

-- Fill a pooled section with one member's data; returns its total height.
-- Only ever called out of combat (relayout defers otherwise), so the secure
-- SetAttribute is safe.
local function updateSection(sec, data)
  local hasState = data.hp ~= nil
  sec._unit = data.unit
  sec._name = data.name
  local shown = resolveDisplayName(data.name)
  sec._displayName = shown
  if not inCombat() and sec.SetAttribute then
    sec:SetAttribute("unit", data.unit)  -- left-click target
  end

  local col = data.nameColor or NAME_DEFAULT
  sec.nameFs:SetTextColor(col[1], col[2], col[3], 1)
  if data.classLabel and data.classLabel ~= "" then
    sec.nameFs:SetText(string.format("%s  |cffb0a08c— %s|r", shown or "?", data.classLabel))
  else
    sec.nameFs:SetText(shown or "?")
  end

  -- Class crest (question mark while waiting for data).
  if hasState and data.classKey and data.classKey ~= "" then
    Shared.SetClassEmblem(sec.icon, data.classKey)
    if sec.icon.SetDesaturated then sec.icon:SetDesaturated(false) end
  else
    sec.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    sec.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if sec.icon.SetDesaturated then sec.icon:SetDesaturated(true) end
  end

  -- Accent stripe + border follow the member's condition.
  local accentCol, borderCol = col, CREAMY_BROWN
  if not hasState then
    accentCol = PLACEHOLDER_COL
  elseif data.status == "agonie" then
    accentCol, borderCol = BORDER_AGONIE, BORDER_AGONIE
  elseif data.status == "stabilise" then
    accentCol, borderCol = BORDER_STAB, BORDER_STAB
  end
  sec._borderColor = borderCol
  sec.accent:SetVertexColor(accentCol[1], accentCol[2], accentCol[3], 0.90)
  sec.rule:SetVertexColor(col[1], col[2], col[3], hasState and 0.30 or 0.12)
  if sec.SetBackdropBorderColor and not (sec.IsMouseOver and sec:IsMouseOver()) then
    sec:SetBackdropBorderColor(borderCol[1], borderCol[2], borderCol[3], 0.90)
  end
  sec:SetAlpha(hasState and 1 or 0.65)

  local top = CARD_TOP_PAD + NAME_H + 5

  -- HP bar
  sec.hp.frame:ClearAllPoints()
  sec.hp.frame:SetPoint("TOPLEFT", sec, "TOPLEFT", CARD_PAD, -top)
  if hasState then
    local maxHp = math.max(1, data.maxHp or 1)
    local hp    = math.max(0, math.min(data.hp, maxHp))
    sec.hp.bar:SetMinMaxValues(0, maxHp)
    sec.hp.bar:SetValue(hp)
    local c = (data.hp == 0) and HP_DEAD_COLOR or HP_COLOR
    sec.hp.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    sec.hp.label:SetText(string.format("PV : %d / %d  (%d%%)",
      math.floor(data.hp + 0.5), math.floor(maxHp + 0.5), Shared.RoundPct(hp / maxHp)))
    applyMarkers(sec.hp, HP_MARKER_DEFS)
  else
    sec.hp.bar:SetMinMaxValues(0, 1)
    sec.hp.bar:SetValue(0)
    sec.hp.bar:SetStatusBarColor(PLACEHOLDER_COL[1], PLACEHOLDER_COL[2], PLACEHOLDER_COL[3], 1)
    sec.hp.label:SetText("En attente...")
    hideMarkers(sec.hp)
  end
  sec.hp.frame:Show()
  top = top + ROW_H + ROW_GAP

  -- Resource bars
  local res = data.resources or {}
  for i = 1, MAX_RES_BARS do
    local rb = sec.res[i]
    local r  = hasState and res[i]
    if r then
      rb.frame:ClearAllPoints()
      rb.frame:SetPoint("TOPLEFT", sec, "TOPLEFT", CARD_PAD, -top)
      rb.bar:SetMinMaxValues(0, r.max)
      rb.bar:SetValue(r.cur)
      rb.bar:SetStatusBarColor(r.r, r.g, r.b, 1)
      rb.label:SetText(string.format("%s : %d / %d",
        r.label, math.floor(r.cur + 0.5), math.floor(r.max + 0.5)))
      applyMarkers(rb, r.markers or {})
      rb.frame:Show()
      top = top + ROW_H + ROW_GAP
    else
      rb.frame:Hide()
      hideMarkers(rb)
    end
  end

  -- Points de Chance (gold), shown only when the member has a chance pool.
  if hasState and data.chance then
    local cb = sec.chanceBar
    cb.frame:ClearAllPoints()
    cb.frame:SetPoint("TOPLEFT", sec, "TOPLEFT", CARD_PAD, -top)
    cb.bar:SetMinMaxValues(0, data.chance.max)
    cb.bar:SetValue(data.chance.cur)
    cb.bar:SetStatusBarColor(0.95, 0.78, 0.20, 1)
    cb.label:SetText(string.format("PC : %d / %d",
      math.floor(data.chance.cur + 0.5), math.floor(data.chance.max + 0.5)))
    hideMarkers(cb)
    cb.frame:Show()
    top = top + ROW_H + ROW_GAP
  else
    sec.chanceBar.frame:Hide()
    hideMarkers(sec.chanceBar)
  end

  -- Status line (only at 0 HP); "EN AGONIE" pulses softly.
  if hasState and data.status then
    sec.statusFs:ClearAllPoints()
    sec.statusFs:SetPoint("TOPLEFT",  sec, "TOPLEFT",  CARD_PAD, -top)
    sec.statusFs:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -CARD_PAD, -top)
    sec.statusFs:SetHeight(STATUS_H)
    if data.status == "stabilise" then
      sec.statusFs:SetText("|cff44ee44** STABILISE **|r")
      if sec.statusPulse then sec.statusPulse:Stop() end
    else
      sec.statusFs:SetText("|cffee2222** EN AGONIE **|r")
      if sec.statusPulse and not sec.statusPulse:IsPlaying() then sec.statusPulse:Play() end
    end
    sec.statusFs:Show()
    top = top + STATUS_H + ROW_GAP
  else
    if sec.statusPulse then sec.statusPulse:Stop() end
    sec.statusFs:Hide()
  end

  local totalH = top + CARD_BOT_PAD
  sec:SetHeight(totalH)
  return totalH
end

-- Pet sub-card: a smaller secure button glued under its owner's card. Same
-- click behavior (left-click targets the pet, right-click opens the pet's
-- heal menu) but no drag registration — it can only move with its owner.
local function buildPetSection()
  local sec = CreateFrame("Button", nil, content, "SecureActionButtonTemplate, BackdropTemplate")
  sec:SetWidth(PET_W)
  if sec.SetBackdrop then
    sec:SetBackdrop(BACKDROP_CARD)
    sec:SetBackdropColor(CARD_BG[1], CARD_BG[2], CARD_BG[3], 0.85)
    sec:SetBackdropBorderColor(CREAMY_BROWN[1], CREAMY_BROWN[2], CREAMY_BROWN[3], 0.90)
  end
  sec:RegisterForClicks("AnyDown", "AnyUp")
  if sec.SetAttribute then
    sec:SetAttribute("type1", "target")
    sec:SetAttribute("*type1", "target")
  end
  sec:SetScript("PostClick", function(self, button, down)
    if button == "RightButton" and not down then openPetMenu(self) end
  end)
  sec:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = sec.GetHighlightTexture and sec:GetHighlightTexture()
  if hl then hl:SetVertexColor(1.0, 0.95, 0.6, 0.08) end

  -- Warm-orange accent stripe (pets have no class color).
  local accent = sec:CreateTexture(nil, "BORDER")
  accent:SetTexture("Interface\\Buttons\\WHITE8x8")
  accent:SetPoint("TOPLEFT",    sec, "TOPLEFT",    3, -3)
  accent:SetPoint("BOTTOMLEFT", sec, "BOTTOMLEFT", 3, 3)
  accent:SetWidth(ACCENT_W)
  accent:SetVertexColor(PET_COLOR[1], PET_COLOR[2], PET_COLOR[3], 0.90)
  sec.accent = accent

  local nameFs = sec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nameFs:SetPoint("TOPLEFT",  sec, "TOPLEFT",  CARD_PAD, -CARD_TOP_PAD)
  nameFs:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -CARD_PAD, -CARD_TOP_PAD)
  nameFs:SetHeight(PET_NAME_H)
  nameFs:SetJustifyH("LEFT")
  nameFs:SetShadowColor(0, 0, 0, 0.9)
  nameFs:SetShadowOffset(1, -1)
  sec.nameFs = nameFs

  sec:SetScript("OnEnter", function(self)
    if self.SetBackdropBorderColor then
      self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end
  end)
  sec:SetScript("OnLeave", function(self)
    if self.SetBackdropBorderColor then
      self:SetBackdropBorderColor(CREAMY_BROWN[1], CREAMY_BROWN[2], CREAMY_BROWN[3], 0.90)
    end
  end)

  sec.hp = makeBar(sec, PET_BAR_W)
  sec.hp.barW = PET_BAR_W
  return sec
end

local function getPetSection(i)
  local sec = petPool[i]
  if sec then return sec end
  sec = buildPetSection()
  petPool[i] = sec
  return sec
end

-- Fill a pooled pet sub-card from data.pet; returns its height. Like
-- updateSection, only ever called out of combat.
local function updatePetSection(sec, data)
  local pet = data.pet
  sec._name = data.name  -- owner name: right-click menu acts on the owner
  sec._displayName = pet.name

  if not inCombat() and sec.SetAttribute then
    local ownerUnit = data.unit
    local petUnit
    if ownerUnit == "player" then
      petUnit = "pet"
    elseif type(ownerUnit) == "string" then
      petUnit = ownerUnit .. "pet"
    end
    sec:SetAttribute("unit", petUnit)  -- left-click targets the pet
  end

  sec.nameFs:SetTextColor(PET_COLOR[1], PET_COLOR[2], PET_COLOR[3], 1)
  sec.nameFs:SetText(string.format("%s  |cffb0a08c— Familier|r", pet.name or "Familier"))

  local top = CARD_TOP_PAD + PET_NAME_H + 3
  sec.hp.frame:ClearAllPoints()
  sec.hp.frame:SetPoint("TOPLEFT", sec, "TOPLEFT", CARD_PAD, -top)
  local maxHp = math.max(1, pet.maxHp or 1)
  local hp    = math.max(0, math.min(pet.hp or 0, maxHp))
  sec.hp.bar:SetMinMaxValues(0, maxHp)
  sec.hp.bar:SetValue(hp)
  local c = (hp == 0) and PET_DEAD_COLOR or PET_COLOR
  sec.hp.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
  sec.hp.label:SetText(string.format("PV : %d / %d  (%d%%)",
    math.floor(hp + 0.5), math.floor(maxHp + 0.5), Shared.RoundPct(hp / maxHp)))

  -- Same 50/25/10 thresholds as everyone, plus the wound-cap notch (gold,
  -- matching Shared.MakeHpThresholdMarkers' cap marker).
  local defs = HP_MARKER_DEFS
  if pet.woundCap and pet.woundCap < 1.0 then
    defs = {}
    for i, d in ipairs(HP_MARKER_DEFS) do defs[i] = d end
    defs[#defs + 1] = { pct = pet.woundCap, r = 1.0, g = 0.9, b = 0.2, a = 0.7, w = 3 }
  end
  applyMarkers(sec.hp, defs)

  local totalH = top + ROW_H + CARD_BOT_PAD
  sec:SetHeight(totalH)
  return totalH
end

local function layoutSections(dataList)
  if not content then return end
  local y = 0
  local slots, names = {}, {}
  local petCount = 0
  for i, data in ipairs(dataList) do
    local sec = getSection(i)
    local h   = updateSection(sec, data)
    sec._displayIndex = i
    sec:ClearAllPoints()
    sec:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    sec:Show()
    local slotH = h
    -- Pet sub-card hangs right under its owner; it counts into the owner's
    -- drag slot so drops always land around the owner+pet pair.
    if data.pet then
      petCount = petCount + 1
      local psec = getPetSection(petCount)
      local ph   = updatePetSection(psec, data)
      psec:ClearAllPoints()
      psec:SetPoint("TOPLEFT", content, "TOPLEFT", PET_INDENT, -(y + h + PET_GAP))
      psec:Show()
      slotH = h + PET_GAP + ph
    end
    slots[i] = { top = y, h = slotH }
    names[i] = data.name
    y = y + slotH + SECTION_GAP
  end
  for i = #dataList + 1, #sectionPool do
    sectionPool[i]:Hide()
  end
  for i = petCount + 1, #petPool do
    petPool[i]:Hide()
  end
  cardSlots           = slots  -- drop-line geometry for drag-to-reorder
  currentDisplayNames = names
  content:SetHeight(math.max(y, 1))
  if countFs then
    countFs:SetText(#dataList == 1 and "1 membre" or (#dataList .. " membres"))
  end
end

local function ensureFrame()
  if frame then return end

  frame = CreateFrame("Frame", "GrosOrteilRaidPanel", UIParent, "BackdropTemplate")
  frame:SetSize(PANEL_W, PANEL_H)
  frame:SetPoint("CENTER")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetToplevel(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
  frame:SetScript("OnDragStop",  function(f) f:StopMovingOrSizing() end)

  -- Bulletin-board skin shared with the main window and the radar:
  -- parchment + creamy tooltip border + wooden rails + header plaque.
  Shared.ApplyBoardSkin(frame)
  Shared.ApplyBoardRails(frame)

  -- ESC closes it (standard pattern; taint-safe for a non-protected frame).
  local specials = rawget(_G, "UISpecialFrames")
  if type(specials) == "table" then
    table.insert(specials, "GrosOrteilRaidPanel")
  end

  local plaque = Shared.MakePlaque(frame, PLAQUE_H)

  headerFs = plaque:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  headerFs:SetPoint("LEFT",  plaque, "LEFT",  10, 0)
  headerFs:SetJustifyH("LEFT")
  headerFs:SetTextColor(1.00, 0.84, 0.30, 1)
  headerFs:SetShadowColor(0, 0, 0, 0.8)
  headerFs:SetShadowOffset(1, -1)
  headerFs:SetText("Ressources du Groupe")

  local closeBtn = CreateFrame("Button", nil, plaque, "UIPanelCloseButton")
  closeBtn:SetSize(24, 24)
  closeBtn:SetPoint("RIGHT", plaque, "RIGHT", -2, 0)
  closeBtn:SetScript("OnClick", function() RaidPanel.Hide() end)

  countFs = plaque:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  countFs:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
  countFs:SetJustifyH("RIGHT")
  countFs:SetTextColor(0.78, 0.66, 0.46, 1)
  countFs:SetText("")

  -- View switcher pinned under the plaque: Groupe (cards) / Compteur (meter).
  local tabW = math.floor((SCROLL_W - 6) / 2)
  local function makeViewTab(label, view, x)
    local b = CreateFrame("Button", nil, frame, "BackdropTemplate")
    b:SetSize(tabW, VIEWTAB_H)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_X + x, -(EDGE + 6 + PLAQUE_H + 4))
    if b.SetBackdrop then b:SetBackdrop(BACKDROP_PLAQUE) end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetShadowColor(0, 0, 0, 0.8)
    fs:SetShadowOffset(1, -1)
    fs:SetText(label)
    b._text = fs
    b._view = view
    b:SetScript("OnClick", function()
      if applyView and currentView ~= view then applyView(view) end
    end)
    b:SetScript("OnEnter", function(self)
      if currentView ~= view then self._text:SetTextColor(1.0, 0.90, 0.50, 1) end
    end)
    b:SetScript("OnLeave", function()
      if styleViewTabs then styleViewTabs() end
    end)
    viewTabs[#viewTabs + 1] = b
  end
  makeViewTab("Groupe",   "group", 0)
  makeViewTab("Compteur", "meter", tabW + 6)

  -- Meter controls (meter view only): [Dégâts | Soins] switch, group total,
  -- and a local reset. Hidden in group view; applyView toggles it.
  meterBar = CreateFrame("Frame", nil, frame)
  meterBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  CONTENT_X, -(SCROLL_TOP_GROUP + 2))
  meterBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CONTENT_X, -(SCROLL_TOP_GROUP + 2))
  meterBar:SetHeight(METERBAR_H - 2)
  meterBar:Hide()

  local function makeModeBtn(label, mode, x)
    local b = CreateFrame("Button", nil, meterBar, "BackdropTemplate")
    b:SetSize(70, METERBAR_H - 4)
    b:SetPoint("LEFT", meterBar, "LEFT", x, 0)
    if b.SetBackdrop then b:SetBackdrop(BACKDROP_PLAQUE) end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetShadowColor(0, 0, 0, 0.8)
    fs:SetShadowOffset(1, -1)
    fs:SetText(label)
    b._text = fs
    b._mode = mode
    b:SetScript("OnClick", function()
      if meterMode ~= mode then
        meterMode = mode
        if styleModeBtns then styleModeBtns() end
        if applyFooterHint then applyFooterHint() end
        if relayout then relayout() end
      end
    end)
    b:SetScript("OnEnter", function(self)
      local tip = rawget(_G, "GameTooltip")
      if not tip then return end
      tip:SetOwner(self, "ANCHOR_TOP")
      tip:ClearLines()
      tip:AddLine(mode == "heal" and "Soins prodigués" or "Dégâts subis",
        GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(mode == "heal"
        and "Total des soins prodigués aux autres par chaque membre (via Soigner)."
        or  "Total des dégâts subis par chaque membre (familier inclus).",
        1, 1, 1, true)
      tip:Show()
    end)
    b:SetScript("OnLeave", function()
      local tip = rawget(_G, "GameTooltip")
      if tip then tip:Hide() end
    end)
    modeBtns[#modeBtns + 1] = b
  end
  makeModeBtn("Dégâts", "damage", 0)
  makeModeBtn("Soins",  "heal",   74)

  local resetBtn = CreateFrame("Button", nil, meterBar)
  resetBtn:SetSize(18, 18)
  resetBtn:SetPoint("RIGHT", meterBar, "RIGHT", -1, 0)
  resetBtn:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
  resetBtn:SetHighlightTexture("Interface\\Buttons\\UI-RefreshButton")
  local resetHl = resetBtn.GetHighlightTexture and resetBtn:GetHighlightTexture()
  if resetHl then resetHl:SetBlendMode("ADD"); resetHl:SetAlpha(0.4) end
  resetBtn:SetScript("OnClick", function()
    RaidMeter.Reset(currentMembers or {}, getStateFor, meterBaselines)
    if relayout then relayout() end
  end)
  resetBtn:SetScript("OnEnter", function(self)
    local tip = rawget(_G, "GameTooltip")
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_TOP")
    tip:ClearLines()
    tip:AddLine("Remise à zéro", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Repart de zéro pour vous uniquement — les fiches des autres joueurs ne sont pas modifiées.", 1, 1, 1, true)
    tip:Show()
  end)
  resetBtn:SetScript("OnLeave", function()
    local tip = rawget(_G, "GameTooltip")
    if tip then tip:Hide() end
  end)

  meterTotalFs = meterBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  meterTotalFs:SetPoint("RIGHT", resetBtn, "LEFT", -8, 0)
  meterTotalFs:SetJustifyH("RIGHT")
  meterTotalFs:SetTextColor(1.00, 0.84, 0.30, 1)
  meterTotalFs:SetShadowColor(0, 0, 0, 0.8)
  meterTotalFs:SetShadowOffset(1, -1)
  meterTotalFs:SetText("")

  -- Ordinary addon-owned sort control, kept left of the 16x16 resize grip.
  -- It never inherits a secure template and only changes presentation state.
  sortButton = CreateFrame("Button", nil, frame, "BackdropTemplate")
  sortButton:SetSize(28, 18)
  sortButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 24)
  sortButton:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
  if sortButton.SetBackdrop then
    sortButton:SetBackdrop(BACKDROP_PLAQUE)
    sortButton:SetBackdropColor(0.10, 0.075, 0.05, 0.95)
    sortButton:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.90)
  end
  local sortIcon = sortButton:CreateTexture(nil, "ARTWORK")
  sortIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  sortIcon:SetSize(15, 15)
  sortIcon:SetPoint("CENTER", sortButton, "CENTER", 0, 0)
  sortButton._icon = sortIcon
  sortButton:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
  sortButton:SetScript("OnClick", function(self) openSortMenu(self) end)
  sortButton:SetScript("OnEnter", function(self)
    local tip = rawget(_G, "GameTooltip")
    if not tip then return end
    ensureSortState()
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    tip:ClearLines()
    tip:AddLine("Tri du groupe", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine(sortDescription(currentSort), 1, 1, 1)
    if not currentSort then
      tip:AddLine("Un glisser-déposer a activé l'ordre manuel.", 0.72, 0.62, 0.50, true)
    end
    tip:AddLine("Cliquez pour choisir le critère et le sens du tri.", 0.72, 0.62, 0.50, true)
    tip:Show()
  end)
  sortButton:SetScript("OnLeave", function()
    local tip = rawget(_G, "GameTooltip")
    if tip then tip:Hide() end
  end)
  updateSortButton()

  -- Footer hint just above the bottom rail (text set per view/drag state).
  hintFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hintFs:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CONTENT_X, EDGE + WOOD + 3)
  hintFs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -56, EDGE + WOOD + 3)
  hintFs:SetHeight(FOOTER_H)
  hintFs:SetJustifyH("LEFT")
  hintFs:SetTextColor(0.42, 0.34, 0.25, 1)
  hintFs:SetText("Clic g. : cibler  —  Clic d. : actions  —  Glisser : réordonner")

  scrollFrame = CreateFrame("ScrollFrame", "GrosOrteilRaidPanelScroll", frame)

  -- The meter view needs extra headroom for its control bar, so the scroll
  -- area's top edge moves per view; applyView calls this.
  setScrollGeometry = function(top)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_X, -top)
    scrollFrame:SetSize(SCROLL_W, PANEL_H - top - SCROLL_BOT)
  end
  setScrollGeometry(SCROLL_TOP_GROUP)

  content = CreateFrame("Frame", nil, scrollFrame)
  content:SetSize(SCROLL_W, 1)
  scrollFrame:SetScrollChild(content)

  -- Second scroll child for the meter view; applyView swaps them.
  meterContent = CreateFrame("Frame", nil, scrollFrame)
  meterContent:SetSize(SCROLL_W, 1)
  meterContent:Hide()

  meterEmptyFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  meterEmptyFs:SetPoint("CENTER", scrollFrame, "CENTER", 0, 20)
  meterEmptyFs:SetTextColor(0.55, 0.46, 0.36, 1)
  meterEmptyFs:Hide()

  -- Slim scroll indicator in the gap between the cards and the right rail.
  -- Anchored to the scroll frame so it follows the per-view geometry.
  local rail = frame:CreateTexture(nil, "ARTWORK")
  rail:SetColorTexture(0, 0, 0, 0.20)
  rail:SetWidth(3)
  rail:SetPoint("TOPRIGHT",    scrollFrame, "TOPRIGHT", PAD - 2, 0)
  rail:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", PAD - 2, 0)
  rail:Hide()
  local thumb = frame:CreateTexture(nil, "ARTWORK", nil, 1)
  thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.55)
  thumb:SetWidth(3)
  thumb:Hide()

  local function updateScrollThumb()
    local range = scrollFrame:GetVerticalScrollRange() or 0
    if range <= 0 then rail:Hide(); thumb:Hide(); return end
    rail:Show(); thumb:Show()
    local h      = scrollFrame:GetHeight() or 1
    local thumbH = math.max(24, h * h / (h + range))
    local ofs    = (h - thumbH) * ((scrollFrame:GetVerticalScroll() or 0) / range)
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, -ofs)
  end

  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
    local cur   = sf:GetVerticalScroll()
    local range = sf:GetVerticalScrollRange()
    local nv    = cur - delta * 30
    if nv < 0 then nv = 0 elseif nv > range then nv = range end
    sf:SetVerticalScroll(nv)
    updateScrollThumb()
  end)
  scrollFrame:SetScript("OnScrollRangeChanged", updateScrollThumb)
  scrollFrame:SetScript("OnVerticalScroll", updateScrollThumb)

  -- Gentle fade-in when the panel opens, fade-out when it closes.
  fadeIn  = Shared.MakeFadeIn(frame, 0.18)
  fadeOut = Shared.MakeFadeOut(frame, 0.15)

  -- Resize grip (drag = rescale, right-click = default), persisted per
  -- character. Vetoed in combat: rescaling would move the secure card
  -- buttons, which is blocked under lockdown.
  if Shared.AttachScaleGrip then
    Shared.AttachScaleGrip(frame, {
      load = function()
        local db = ns.GetDB and ns.GetDB()
        return type(db) == "table" and type(db.settings) == "table"
          and db.settings.raidPanelScale or nil
      end,
      save = function(s)
        local db = ns.GetDB and ns.GetDB()
        if type(db) ~= "table" then return end
        db.settings = db.settings or {}
        db.settings.raidPanelScale = s
      end,
      canResize = function() return not inCombat() end,
    })
  end

  -- Secure section buttons can't be moved/shown/re-attributed in combat, so a
  -- relayout requested during combat is deferred until combat ends. Roster
  -- changes re-pull the member list so joins/leaves show without reopening.
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:RegisterEvent("GROUP_ROSTER_UPDATE")
  frame:SetScript("OnEvent", function(_, event)
    if not frame:IsShown() then return end
    if event == "GROUP_ROSTER_UPDATE" then
      if Refresh then Refresh() end
      return
    end
    if pendingRelayout then
      pendingRelayout = false
      if relayout then relayout() end
    end
  end)

  -- Live self-updates: peers learn about our changes via comm, but locally we
  -- prime our own cache entry straight from Core so the panel and the meter
  -- react instantly to every change of the local sheet.
  if ns.Core and ns.Core.OnChange then
    ns.Core.OnChange(function()
      if frame:IsShown() then
        primeSelfCache()
        if relayout then relayout() end
      end
    end)
  end

  applyView(currentView)
end

-- ── Meter view (plain frames — no secure buttons, safe to relayout anywhere) ───

-- "1234567" → "1 234 567" (French thousands separator).
local function fmtInt(n)
  n = math.floor((tonumber(n) or 0) + 0.5)
  local s = tostring(n):reverse():gsub("(%d%d%d)", "%1 "):reverse()
  return (s:gsub("^%s+", ""))
end

local function getMeterRow(i)
  local row = meterRowPool[i]
  if row then return row end
  row = CreateFrame("Frame", nil, meterContent, "BackdropTemplate")
  row:SetSize(SCROLL_W, METER_ROW_H)
  if row.SetBackdrop then
    row:SetBackdrop(BACKDROP_CARD)
    row:SetBackdropColor(CARD_BG[1], CARD_BG[2], CARD_BG[3], 0.92)
    row:SetBackdropBorderColor(CREAMY_BROWN[1], CREAMY_BROWN[2], CREAMY_BROWN[3], 0.90)
  end
  -- Class-colored fill, proportional to the top member's value.
  local fill = row:CreateTexture(nil, "BORDER")
  fill:SetTexture("Interface\\Buttons\\WHITE8x8")
  fill:SetPoint("TOPLEFT",    row, "TOPLEFT",    3, -3)
  fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 3, 3)
  row.fill = fill
  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(16, 16)
  icon:SetPoint("LEFT", row, "LEFT", 8, 0)
  row.icon = icon
  local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  value:SetJustifyH("RIGHT")
  value:SetShadowColor(0, 0, 0, 0.9)
  value:SetShadowOffset(1, -1)
  row.value = value
  local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  name:SetPoint("LEFT",  icon,  "RIGHT", 5, 0)
  name:SetPoint("RIGHT", value, "LEFT", -6, 0)
  name:SetJustifyH("LEFT")
  name:SetShadowColor(0, 0, 0, 0.9)
  name:SetShadowOffset(1, -1)
  row.name = name
  meterRowPool[i] = row
  return row
end

layoutMeter = function()
  if not meterContent then return end
  local result = RaidMeter.BuildRows(currentMembers or {}, getStateFor, meterBaselines, meterMode)
  local rows  = result.rows
  local fullW = SCROLL_W - 6
  local y = 0
  for i, r in ipairs(rows) do
    local row = getMeterRow(i)
    local style = Shared.CLASS_STYLES and Shared.CLASS_STYLES[r.classKey]
    local cr, cg, cb
    if style then cr, cg, cb = style.r, style.g, style.b
    else cr, cg, cb = NAME_DEFAULT[1], NAME_DEFAULT[2], NAME_DEFAULT[3] end
    if r.classKey ~= "" then
      Shared.SetClassEmblem(row.icon, r.classKey)
      if row.icon.SetDesaturated then row.icon:SetDesaturated(false) end
    else
      row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      if row.icon.SetDesaturated then row.icon:SetDesaturated(true) end
    end
    row.name:SetText(string.format("%d.  %s", i, resolveDisplayName(r.name)))
    row.name:SetTextColor(cr, cg, cb, 1)
    row.value:SetText(string.format("%s — %d%%", fmtInt(r.value), math.floor(r.share * 100 + 0.5)))
    row.value:SetTextColor(0.95, 0.90, 0.75, 1)
    local w = (result.maxValue > 0) and math.floor(fullW * (r.value / result.maxValue)) or 0
    if w < 1 then w = 1 end
    row.fill:SetWidth(w)
    row.fill:SetVertexColor(cr, cg, cb, 0.28)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", meterContent, "TOPLEFT", 0, -y)
    row:Show()
    y = y + METER_ROW_H + 3
  end
  for i = #rows + 1, #meterRowPool do meterRowPool[i]:Hide() end
  meterContent:SetHeight(math.max(y, 1))
  if meterTotalFs then
    meterTotalFs:SetText("Total : " .. fmtInt(result.total))
  end
  if meterEmptyFs then
    if #rows == 0 then
      meterEmptyFs:SetText(meterMode == "heal"
        and "Aucun soin prodigué pour l'instant."
        or  "Aucun dégât enregistré pour l'instant.")
      meterEmptyFs:Show()
    else
      meterEmptyFs:Hide()
    end
  end
  if countFs and currentMembers then
    local n = #currentMembers
    countFs:SetText(n == 1 and "1 membre" or (n .. " membres"))
  end
end

-- ── View switching ─────────────────────────────────────────────────────────────

styleViewTabs = function()
  for _, b in ipairs(viewTabs) do
    local active = (b._view == currentView)
    if b.SetBackdropColor then
      b:SetBackdropColor(0.10, 0.075, 0.05, active and 0.97 or 0.55)
      if active then
        b:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
      else
        b:SetBackdropBorderColor(CREAMY_BROWN[1], CREAMY_BROWN[2], CREAMY_BROWN[3], 0.90)
      end
    end
    if active then b._text:SetTextColor(1.00, 0.84, 0.30, 1)
    else           b._text:SetTextColor(0.62, 0.53, 0.42, 1) end
  end
end

styleModeBtns = function()
  for _, b in ipairs(modeBtns) do
    local active = (b._mode == meterMode)
    if b.SetBackdropColor then
      b:SetBackdropColor(0.10, 0.075, 0.05, active and 0.97 or 0.45)
      if active then
        b:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
      else
        b:SetBackdropBorderColor(CREAMY_BROWN[1], CREAMY_BROWN[2], CREAMY_BROWN[3], 0.90)
      end
    end
    if active then b._text:SetTextColor(1.00, 0.84, 0.30, 1)
    else           b._text:SetTextColor(0.62, 0.53, 0.42, 1) end
  end
end

applyFooterHint = function()
  if not hintFs then return end
  if dragging then
    hintFs:SetText("Relâchez pour déposer la fiche")
  elseif currentView == "meter" then
    hintFs:SetText(meterMode == "heal"
      and "Soins prodigués aux autres, par membre"
      or  "Dégâts subis par membre, familier inclus")
  else
    hintFs:SetText("Clic g. : cibler  —  Clic d. : actions  —  Glisser : réordonner")
  end
end

applyView = function(view)
  currentView = (view == "meter") and "meter" or "group"
  local isMeter = (currentView == "meter")
  if setScrollGeometry then
    setScrollGeometry(isMeter and SCROLL_TOP_METER or SCROLL_TOP_GROUP)
  end
  if meterBar then meterBar:SetShown(isMeter) end
  if sortButton then sortButton:SetShown(not isMeter) end
  if scrollFrame and content and meterContent then
    scrollFrame:SetScrollChild(isMeter and meterContent or content)
    content:SetShown(not isMeter)
    meterContent:SetShown(isMeter)
    scrollFrame:SetVerticalScroll(0)
  end
  if meterEmptyFs and not isMeter then meterEmptyFs:Hide() end
  if headerFs then
    headerFs:SetText(isMeter and "Compteur du Groupe" or "Ressources du Groupe")
  end
  styleViewTabs()
  styleModeBtns()
  updateSortButton()
  applyFooterHint()
  relayout()
end

-- ── Drag-to-reorder (group view) ───────────────────────────────────────────────

local function cursorOffsetInContent()
  local getCursor = rawget(_G, "GetCursorPosition")
  if not (getCursor and content) then return 0 end
  local _, cy = getCursor()
  local scale = (content.GetEffectiveScale and content:GetEffectiveScale()) or 1
  if not scale or scale == 0 then scale = 1 end
  local top = (content.GetTop and content:GetTop()) or 0
  return top - cy / scale
end

local function updateDropLine()
  if not (dragging and dropLine) then return end
  dropSlot = dropIndexFromOffset(cardSlots, cursorOffsetInContent())
  local y
  if dropSlot <= #cardSlots then
    y = cardSlots[dropSlot].top - math.floor(SECTION_GAP / 2) - 1
  elseif #cardSlots > 0 then
    local last = cardSlots[#cardSlots]
    y = last.top + last.h + math.floor(SECTION_GAP / 2)
  else
    y = 0
  end
  if y < 0 then y = 0 end
  dropLine:ClearAllPoints()
  dropLine:SetPoint("TOPLEFT",  content, "TOPLEFT",  1, -y)
  dropLine:SetPoint("TOPRIGHT", content, "TOPRIGHT", -1, -y)
end

startCardDrag = function(sec)
  if dragging or inCombat() or currentView ~= "group" then return end
  if not (sec and sec._displayIndex) then return end
  dragging = sec
  dropSlot = sec._displayIndex
  sec:SetAlpha(0.45)
  if not dropLine then
    -- Hosted on a raised frame so the line draws above the cards (a parent's
    -- own textures always render below its child frames).
    local host = CreateFrame("Frame", nil, content)
    host:SetAllPoints(content)
    host:SetFrameLevel((content:GetFrameLevel() or 0) + 30)
    dropLine = host:CreateTexture(nil, "OVERLAY")
    dropLine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.90)
    dropLine:SetHeight(2)
  end
  dropLine:Show()
  frame:SetScript("OnUpdate", updateDropLine)
  updateDropLine()
  applyFooterHint()
end

stopCardDrag = function(sec)
  if dragging ~= sec then return end
  dragging = nil
  frame:SetScript("OnUpdate", nil)
  if dropLine then dropLine:Hide() end
  local fromIdx = sec._displayIndex
  if fromIdx and dropSlot and not inCombat() then
    saveOrder(moveInList(currentDisplayNames, fromIdx, dropSlot))
    setManualSort()
    currentMembers = applySavedOrder(currentMembers or {}, getSavedOrder())
  end
  applyFooterHint()
  relayout()  -- restores the dragged card's alpha via updateSection
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

relayout = function()
  if not frame then return end
  if currentView == "meter" then
    layoutMeter()
    return
  end
  if inCombat() then pendingRelayout = true; return end
  ensureSortState()
  local data = collectData(currentMembers)
  if currentSort then data = sortDisplayData(data, currentSort) end
  layoutSections(data)
end

-- GROUP_ROSTER_UPDATE fires in bursts while a raid forms; one state request
-- per member every few seconds is plenty (peers throttle responses anyway).
local REQUEST_BURST_COOLDOWN = 3
local lastRequestBurst = 0

Refresh = function()
  currentMembers = applySavedOrder(getRaidMembers(), getSavedOrder())
  primeSelfCache()
  -- Fire-and-forget fresh requests; replies refresh rows via OnStateArrived.
  local GetTime = rawget(_G, "GetTime")
  local now = (GetTime and GetTime()) or 0
  if ns.Comm and ns.Comm.RequestState
      and (now - lastRequestBurst) >= REQUEST_BURST_COOLDOWN then
    lastRequestBurst = now
    for _, m in ipairs(currentMembers) do
      ns.Comm:RequestState(m.name)
    end
  end
  relayout()
end

function RaidPanel.Show()
  ensureFrame()
  if fadeOut then fadeOut:Stop() end  -- cancel a pending close fade
  Refresh()
  if scrollFrame then scrollFrame:SetVerticalScroll(0) end
  frame:Show()
  frame:Raise()
  if fadeIn then fadeIn:Play() end
end

function RaidPanel.Hide()
  if not frame then return end
  if fadeOut and frame:IsShown() and not fadeOut:IsPlaying() then
    fadeOut:Play()
  else
    frame:Hide()
  end
end

function RaidPanel.Toggle()
  -- A panel mid-fade-out counts as hidden, so toggling reopens it.
  if frame and frame:IsShown() and not (fadeOut and fadeOut:IsPlaying()) then
    RaidPanel.Hide()
  else
    RaidPanel.Show()
  end
end

function RaidPanel.Init()
  if not ns.TargetPopup or not ns.TargetPopup.OnStateArrived then return end
  ns.TargetPopup.OnStateArrived(function(sender, _)
    if not frame or not frame:IsShown() then return end
    local key = normalizeKey(sender)
    if not key then return end
    for _, m in ipairs(currentMembers or {}) do
      if normalizeKey(m.name) == key then
        relayout()
        return
      end
    end
  end)
end

-- Test handles (pure functions, no WoW frames required)
RaidPanel._getDisplayData      = getDisplayData
RaidPanel._getRaidMembers      = getRaidMembers
RaidPanel._collectData         = collectData
RaidPanel._resMarkerDefs       = resMarkerDefs
RaidPanel._normalizeKey        = normalizeKey
RaidPanel._normalizeSortSpec   = normalizeSortSpec
RaidPanel._validateSortSpec    = validateSortSpec
RaidPanel._getSortValue        = getSortValue
RaidPanel._sortDisplayData     = sortDisplayData
RaidPanel._resolveSortSpec     = resolveSortSpec
RaidPanel._persistAutomaticSort = persistAutomaticSort
RaidPanel._persistManualSort   = persistManualSort
RaidPanel._moveInList          = moveInList
RaidPanel._applySavedOrder     = applySavedOrder
RaidPanel._dropIndexFromOffset = dropIndexFromOffset
RaidPanel._saveOrder           = saveOrder
RaidPanel._getSavedOrder       = getSavedOrder
RaidPanel._getSavedSort        = getSavedSort

function ns.RaidPanel_Init()
  RaidPanel.Init()
end
