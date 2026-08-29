-- GrosOrteil/Grimoire.lua
-- Local-only authoring domain for the character Grimoire.
local _, ns = ...

local Grimoire = {}
ns.Grimoire = Grimoire

local Core = ns.Core
local Shared = ns.Shared

local function isPositiveInteger(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value >= 1
    and value == math.floor(value)
end

local function normalizeString(value)
  if type(value) == "string" then return value end
  if type(value) == "number" or type(value) == "boolean" then
    return tostring(value)
  end
  return ""
end

local function trim(value)
  value = normalizeString(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local DAMAGE_HEALING_ERROR = "Les dégâts / soins doivent être un entier positif ou une plage valide (ex. 30-50)."

function Grimoire.ParseDamageHealingInput(value)
  if value == nil or value == false then return nil, nil, nil end
  if type(value) == "number" then
    if isPositiveInteger(value) then return value, nil, nil end
    return nil, nil, DAMAGE_HEALING_ERROR
  end

  local text = trim(value)
  if text == "" then return nil, nil, nil end
  local minimum, maximum = text:match("^[Rr]?%s*(%d+)%s*%-%s*[Rr]?%s*(%d+)$")
  if minimum then
    minimum, maximum = tonumber(minimum), tonumber(maximum)
    if not isPositiveInteger(minimum) or not isPositiveInteger(maximum) or maximum < minimum then
      return nil, nil, DAMAGE_HEALING_ERROR
    end
    return minimum, maximum, nil
  end

  minimum = tonumber(text:match("^[Rr]?%s*(%d+)$"))
  if isPositiveInteger(minimum) then return minimum, nil, nil end
  return nil, nil, DAMAGE_HEALING_ERROR
end

local function normalizeStoredDamageHealing(minimumValue, maximumValue)
  if maximumValue == nil then
    local minimum, maximum = Grimoire.ParseDamageHealingInput(minimumValue)
    return minimum, maximum
  end
  local minimum = tonumber(minimumValue)
  local maximum = tonumber(maximumValue)
  if not isPositiveInteger(minimum) then return nil, nil end
  if not isPositiveInteger(maximum) or maximum < minimum then return minimum, nil end
  return minimum, maximum
end

function Grimoire.FormatDamageHealing(value, maximumValue)
  if type(value) == "table" then
    maximumValue = value.damageHealingMax
    value = value.damageHealing
  end
  local minimum, maximum = normalizeStoredDamageHealing(value, maximumValue)
  if not minimum then return nil end
  if maximum then return "R" .. tostring(minimum) .. "-" .. tostring(maximum) end
  return "R" .. tostring(minimum)
end

local function copyIcon(icon)
  if type(icon) ~= "table" then return nil end
  return {
    name = icon.name,
    type = icon.type,
    file = icon.file,
    atlas = icon.atlas,
  }
end

local function copyCost(cost)
  if type(cost) ~= "table" then return nil end
  return {
    classKey = cost.classKey,
    resourceIdx = cost.resourceIdx,
    amount = cost.amount,
  }
end

local function normalizeIcon(icon)
  if type(icon) ~= "table" then return nil end
  local name = type(icon.name) == "string" and trim(icon.name) or ""
  if name == "" then return nil end

  local iconType = icon.type
  local file = icon.file
  if type(file) == "string" then
    file = trim(file)
    if file == "" then file = nil end
  end
  local atlas = type(icon.atlas) == "string" and trim(icon.atlas) or nil
  if atlas == "" then atlas = nil end

  if iconType ~= "file" and iconType ~= "atlas" then
    if atlas then iconType = "atlas"
    elseif type(file) == "number" or (type(file) == "string" and file ~= "") then
      iconType = "file"
    else
      -- Legacy entries sometimes persisted only the TRP selector name. Keep
      -- that identity and normalize to a file-style fallback locator.
      iconType = "file"
    end
  end
  if iconType == "file" then
    if type(file) ~= "number" and type(file) ~= "string" then file = nil end
    atlas = nil
  elseif iconType == "atlas" then
    file = nil
  end

  return { name = name, type = iconType, file = file, atlas = atlas }
end

local function getResourcesForClass(classKey)
  if type(classKey) ~= "string" or classKey == "" then return {} end
  if not Shared or type(Shared.GetResProfile) ~= "function" then return {} end
  local profiles = Shared.RES_PROFILES_BY_CLASS or {}
  local styles = Shared.CLASS_STYLES or {}
  if profiles[classKey] == nil and styles[classKey] == nil then return {} end

  -- Deliberately omit pet state. GetResProfile appends pet authority when a
  -- pet is active, and player Techniques must never offer that entry.
  local profile = Shared.GetResProfile({ classKey = classKey })
  local out = {}
  for i = 1, #profile do
    local resource = profile[i]
    local idx = resource and resource.idx
    if isPositiveInteger(idx) and idx <= 4 then
      out[#out + 1] = {
        idx = idx,
        label = normalizeString(resource.label),
        r = resource.r,
        g = resource.g,
        b = resource.b,
      }
    end
  end
  return out
end

function Grimoire.GetCostResource(classKey, resourceIdx)
  local resources = getResourcesForClass(classKey)
  for i = 1, #resources do
    if resources[i].idx == resourceIdx then return resources[i] end
  end
  return nil
end

local function normalizeStoredCost(cost)
  if type(cost) ~= "table" then return nil end
  local classKey = type(cost.classKey) == "string" and trim(cost.classKey) or ""
  local resourceIdx = tonumber(cost.resourceIdx)
  local amount = tonumber(cost.amount)
  if classKey == "" or not isPositiveInteger(resourceIdx) or not isPositiveInteger(amount) then
    return nil
  end
  if not Grimoire.GetCostResource(classKey, resourceIdx) then return nil end
  return { classKey = classKey, resourceIdx = resourceIdx, amount = amount }
end

local function normalizeTechnique(raw, id)
  raw = type(raw) == "table" and raw or {}
  local uses = tonumber(raw.usesPerMission)
  if not isPositiveInteger(uses) then uses = nil end
  local damageHealing, damageHealingMax = normalizeStoredDamageHealing(
    raw.damageHealing, raw.damageHealingMax
  )
  return {
    id = id,
    title = normalizeString(raw.title),
    description = normalizeString(raw.description),
    icon = normalizeIcon(raw.icon),
    cost = normalizeStoredCost(raw.cost),
    usesPerMission = uses,
    damageHealing = damageHealing,
    damageHealingMax = damageHealingMax,
  }
end

local function hasOnlyKeys(value, allowed)
  if type(value) ~= "table" then return false end
  for key in pairs(value) do
    if not allowed[key] then return false end
  end
  return true
end

local TECHNIQUE_KEYS = {
  id = true, title = true, description = true, icon = true,
  cost = true, usesPerMission = true, damageHealing = true, damageHealingMax = true,
}
local ICON_KEYS = { name = true, type = true, file = true, atlas = true }
local COST_KEYS = { classKey = true, resourceIdx = true, amount = true }

local function isAlreadyNormalized(raw, clean)
  if type(raw) ~= "table" or not hasOnlyKeys(raw, TECHNIQUE_KEYS) then return false end
  if raw.id ~= clean.id or raw.title ~= clean.title or raw.description ~= clean.description
      or raw.usesPerMission ~= clean.usesPerMission
      or raw.damageHealing ~= clean.damageHealing
      or raw.damageHealingMax ~= clean.damageHealingMax then
    return false
  end
  if raw.icon == nil ~= (clean.icon == nil) then return false end
  if raw.icon then
    if not hasOnlyKeys(raw.icon, ICON_KEYS)
        or raw.icon.name ~= clean.icon.name or raw.icon.type ~= clean.icon.type
        or raw.icon.file ~= clean.icon.file or raw.icon.atlas ~= clean.icon.atlas then
      return false
    end
  end
  if raw.cost == nil ~= (clean.cost == nil) then return false end
  if raw.cost then
    if not hasOnlyKeys(raw.cost, COST_KEYS)
        or raw.cost.classKey ~= clean.cost.classKey
        or raw.cost.resourceIdx ~= clean.cost.resourceIdx
        or raw.cost.amount ~= clean.cost.amount then
      return false
    end
  end
  return true
end

local function orderedValues(value)
  if type(value) ~= "table" then return {} end
  local keys = {}
  for key in pairs(value) do
    if isPositiveInteger(key) then keys[#keys + 1] = key end
  end
  table.sort(keys)
  local out = {}
  for i = 1, #keys do out[#out + 1] = value[keys[i]] end
  return out
end

function Grimoire.EnsureState(state)
  if type(state) ~= "table" then return nil end
  local stored = type(state.grimoire) == "table" and state.grimoire or {}
  local source = orderedValues(stored.techniques)
  local used = {}
  local maxId = 0

  -- Reserve valid, unique legacy IDs first so a missing ID can never steal an
  -- identity that appears later in the persisted order.
  for i = 1, #source do
    local id = type(source[i]) == "table" and tonumber(source[i].id) or nil
    if isPositiveInteger(id) and not used[id] then
      used[id] = true
      if id > maxId then maxId = id end
    end
  end

  local nextId = tonumber(stored.nextTechniqueId)
  if not isPositiveInteger(nextId) then nextId = 1 end
  if nextId <= maxId then nextId = maxId + 1 end

  local normalized = {}
  local assigned = {}
  for i = 1, #source do
    local raw = source[i]
    local id = type(raw) == "table" and tonumber(raw.id) or nil
    if not isPositiveInteger(id) or assigned[id] then
      while used[nextId] or assigned[nextId] do nextId = nextId + 1 end
      id = nextId
      used[id] = true
      nextId = nextId + 1
    end
    assigned[id] = true
    if id >= nextId then nextId = id + 1 end
    local clean = normalizeTechnique(raw, id)
    normalized[#normalized + 1] = isAlreadyNormalized(raw, clean) and raw or clean
  end

  local canReuseArray = type(stored.techniques) == "table"
    and #stored.techniques == #normalized
  if canReuseArray then
    for i = 1, #normalized do
      if stored.techniques[i] ~= normalized[i] then canReuseArray = false; break end
    end
  end
  stored.nextTechniqueId = nextId
  if not canReuseArray then stored.techniques = normalized end
  state.grimoire = stored
  return state.grimoire
end

local function resolveState(state)
  state = state or (Core and Core.state)
  if type(state) ~= "table" then return nil end
  Grimoire.EnsureState(state)
  return state
end

local function commitIfActive(state)
  if Core and state == Core.state and type(Core.CommitGrimoireMutation) == "function" then
    Core.CommitGrimoireMutation()
  end
end

function Grimoire.GetTechniques(state)
  state = resolveState(state)
  return state and state.grimoire.techniques or {}
end

function Grimoire.GetTechniqueById(id, state)
  id = tonumber(id)
  local techniques = Grimoire.GetTechniques(state)
  for i = 1, #techniques do
    if techniques[i].id == id then return techniques[i], i end
  end
  return nil
end

function Grimoire.GetAvailableCostResources(state)
  state = resolveState(state)
  return getResourcesForClass(state and state.classKey)
end

function Grimoire.ValidateCost(state, cost)
  state = resolveState(state)
  if cost == nil or cost == false then return true, nil, nil end
  local normalized = normalizeStoredCost(cost)
  if not normalized then return false, "Coût invalide." end
  if not state or normalized.classKey ~= state.classKey then
    return false, "Cette ressource appartient à une autre classe.", normalized
  end
  local resource = Grimoire.GetCostResource(normalized.classKey, normalized.resourceIdx)
  if not resource then return false, "Ressource indisponible.", normalized end
  return true, nil, normalized, resource
end

local function validateAuthoredFields(state, fields)
  fields = type(fields) == "table" and fields or {}
  local title = trim(fields.title)
  if title == "" then return nil, "Le titre est obligatoire." end

  local cost = fields.cost
  if cost == false then cost = nil end
  local ok, err, normalizedCost = Grimoire.ValidateCost(state, cost)
  if not ok then return nil, err end

  local uses = fields.usesPerMission
  if uses == false then uses = nil end
  if uses ~= nil then
    uses = tonumber(uses)
    if not isPositiveInteger(uses) then
      return nil, "Le nombre d’utilisations doit être un entier positif."
    end
  end

  local damageHealing = fields.damageHealing
  local damageHealingMax = fields.damageHealingMax
  if damageHealing == false then
    damageHealing, damageHealingMax = nil, nil
  else
    if damageHealingMax == false then damageHealingMax = nil end
    if damageHealingMax == nil then
      local parseError
      damageHealing, damageHealingMax, parseError = Grimoire.ParseDamageHealingInput(damageHealing)
      if parseError then return nil, parseError end
    else
      damageHealing = tonumber(damageHealing)
      damageHealingMax = tonumber(damageHealingMax)
      if not isPositiveInteger(damageHealing) or not isPositiveInteger(damageHealingMax)
          or damageHealingMax < damageHealing then
        return nil, DAMAGE_HEALING_ERROR
      end
    end
  end

  local icon = fields.icon
  if icon == false then icon = nil end
  if icon ~= nil then
    icon = normalizeIcon(icon)
    if not icon then return nil, "Icône invalide." end
  end

  return {
    title = title,
    description = normalizeString(fields.description),
    icon = icon,
    cost = normalizedCost,
    usesPerMission = uses,
    damageHealing = damageHealing,
    damageHealingMax = damageHealingMax,
  }
end

function Grimoire.CreateTechnique(fields, state)
  state = resolveState(state)
  if not state then return nil, "État indisponible." end
  local clean, err = validateAuthoredFields(state, fields)
  if not clean then return nil, err end

  local grimoire = state.grimoire
  local id = grimoire.nextTechniqueId
  local occupied = {}
  for i = 1, #grimoire.techniques do occupied[grimoire.techniques[i].id] = true end
  while occupied[id] do id = id + 1 end
  grimoire.nextTechniqueId = id + 1
  local technique = normalizeTechnique(clean, id)
  grimoire.techniques[#grimoire.techniques + 1] = technique
  commitIfActive(state)
  return technique
end

local function sameIcon(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  return a.name == b.name and a.type == b.type and a.file == b.file and a.atlas == b.atlas
end

local function sameCost(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  return a.classKey == b.classKey and a.resourceIdx == b.resourceIdx and a.amount == b.amount
end

function Grimoire.UpdateTechnique(id, fields, state)
  state = resolveState(state)
  if not state then return nil, "État indisponible." end
  local technique = Grimoire.GetTechniqueById(id, state)
  if not technique then return nil, "Technique introuvable." end
  fields = type(fields) == "table" and fields or {}
  -- Treat this API as a patch. Explicit false clears optional fields; omitted
  -- fields retain their current value.
  local merged = {
    title = technique.title,
    description = technique.description,
    icon = copyIcon(technique.icon),
    cost = copyCost(technique.cost),
    usesPerMission = technique.usesPerMission,
    damageHealing = technique.damageHealing,
    damageHealingMax = technique.damageHealingMax,
  }
  if fields.title ~= nil then merged.title = fields.title end
  if fields.description ~= nil then merged.description = fields.description end
  if fields.icon ~= nil then merged.icon = fields.icon end
  if fields.cost ~= nil then merged.cost = fields.cost end
  if fields.usesPerMission ~= nil then merged.usesPerMission = fields.usesPerMission end
  if fields.damageHealing ~= nil then
    merged.damageHealing = fields.damageHealing
    if fields.damageHealing == false then
      merged.damageHealingMax = false
    elseif type(fields.damageHealing) == "string" and fields.damageHealing:find("%-")
        and fields.damageHealingMax == nil then
      merged.damageHealingMax = nil
    end
  end
  if fields.damageHealingMax ~= nil then merged.damageHealingMax = fields.damageHealingMax end
  local clean, err = validateAuthoredFields(state, merged)
  if not clean then return nil, err end
  -- Cost validation defensively normalizes state, so reacquire by stable ID
  -- before mutating instead of retaining a possibly replaced table reference.
  technique = Grimoire.GetTechniqueById(id, state)
  if not technique then return nil, "Technique introuvable." end

  local changed = technique.title ~= clean.title
    or technique.description ~= clean.description
    or not sameIcon(technique.icon, clean.icon)
    or not sameCost(technique.cost, clean.cost)
    or technique.usesPerMission ~= clean.usesPerMission
    or technique.damageHealing ~= clean.damageHealing
    or technique.damageHealingMax ~= clean.damageHealingMax
  if not changed then return technique end

  technique.title = clean.title
  technique.description = clean.description
  technique.icon = copyIcon(clean.icon)
  technique.cost = copyCost(clean.cost)
  technique.usesPerMission = clean.usesPerMission
  technique.damageHealing = clean.damageHealing
  technique.damageHealingMax = clean.damageHealingMax
  commitIfActive(state)
  return technique
end

function Grimoire.DeleteTechnique(id, state)
  state = resolveState(state)
  if not state then return false end
  local _, index = Grimoire.GetTechniqueById(id, state)
  if not index then return false end
  table.remove(state.grimoire.techniques, index)
  commitIfActive(state)
  return true
end

function Grimoire.MoveTechnique(id, delta, state)
  state = resolveState(state)
  if not state then return false end
  delta = tonumber(delta)
  if delta ~= -1 and delta ~= 1 then return false end
  local _, index = Grimoire.GetTechniqueById(id, state)
  if not index then return false end
  local target = index + delta
  local techniques = state.grimoire.techniques
  if target < 1 or target > #techniques then return false end
  techniques[index], techniques[target] = techniques[target], techniques[index]
  commitIfActive(state)
  return true
end

function Grimoire.FormatTechniqueForCopy(technique)
  technique = type(technique) == "table" and technique or {}
  return "[" .. normalizeString(technique.title) .. " : "
    .. normalizeString(technique.description) .. "]"
end

function Grimoire.CopyTechnique(technique)
  if type(technique) ~= "table" then return nil end
  return {
    id = technique.id,
    title = technique.title,
    description = technique.description,
    icon = copyIcon(technique.icon),
    cost = copyCost(technique.cost),
    usesPerMission = technique.usesPerMission,
    damageHealing = technique.damageHealing,
    damageHealingMax = technique.damageHealingMax,
  }
end
