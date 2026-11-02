local _, ns = ...
local Mounts = {}
ns.Mounts = Mounts
local Core, Shared = ns.Core, ns.Shared
local selectedID = 0
local eventFrame

local function number(value, minimum, fallback)
  if Shared.IsSecret(value) or type(value) ~= "number" or value ~= value
      or math.abs(value) == math.huge then return fallback end
  return math.max(minimum, math.min(1e9, value))
end

local function ensureMount(s, id, name)
  s.mounts = type(s.mounts) == "table" and s.mounts or {}
  local m = type(s.mounts[id]) == "table" and s.mounts[id] or {}
  s.mounts[id] = m
  m.name = type(m.name) == "string" and m.name ~= "" and m.name or name or "Monture"
  m.maxHp = number(m.maxHp, 1, 20)
  m.hp = math.min(m.maxHp, number(m.hp, 0, m.maxHp))
  m.armor = number(m.armor, 0, 0)
  m.dodge = number(m.dodge, 0, 0)
  m.isPet = m.isPet == true
  m.wounds = type(m.wounds) == "table" and m.wounds or {}
  return m
end

function Mounts.EnsureState(s)
  s.mounts = type(s.mounts) == "table" and s.mounts or {}
  -- World state is refreshed at login, never restored from SavedVariables.
  s.mounted, s.activeMountID = false, nil
  selectedID = 0
end

function Mounts.GetSelectedID() return selectedID end

function Mounts.GetSelected()
  local s = Core.state
  if not s then return nil end
  local config = ensureMount(s, selectedID)
  return config.isPet and Core.GetPet() or config, config
end

function Mounts.GetActive(s)
  s = s or Core.state
  if not s or not s.mounted then return nil end
  local config = type(s.mounts) == "table" and s.mounts[s.activeMountID or 0]
  if not config then return nil end
  return config.isPet and s.pet or config, config
end

function Mounts.Select(id)
  local valid = number(id, 0)
  if valid == nil or valid ~= id or id ~= math.floor(id) or not Core.state then return false end
  selectedID = id
  ensureMount(Core.state, id)
  Core.RefreshMountState()
  return true
end

function Mounts.SelectNext(direction)
  local s = Core.state
  if not s then return end
  local ids = {}
  for id in pairs(s.mounts) do
    if type(id) == "number" and id > 0 then ids[#ids + 1] = id end
  end
  table.sort(ids)
  if #ids == 0 then return Mounts.Select(0) end
  local index = direction > 0 and 0 or 1
  for i, id in ipairs(ids) do if id == selectedID then index = i; break end end
  Mounts.Select(ids[(index - 1 + direction) % #ids + 1])
end

function Mounts.SetPetLink(enabled)
  local _, config = Mounts.GetSelected()
  if not config or config.isPet == not not enabled then return end
  config.isPet = not not enabled
  Core.CommitMountMutation()
end

function Mounts.SetField(field, value, id)
  local m
  if id ~= nil and Core.state then
    local config = Core.state.mounts[id]
    if not config then return false end
    m = config.isPet and Core.GetPet() or config
  else m = Mounts.GetSelected() end
  if not m then return false end
  if field == "name" then
    if type(value) ~= "string" then return false end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return false end
    value = value:sub(1, 120)
  elseif field == "hp" or field == "maxHp" or field == "armor" or field == "dodge" then
    value = number(value, field == "maxHp" and 1 or 0)
    if value == nil then return false end
  else return false end
  if m[field] == value then return true end
  m[field] = value
  m.hp = math.min(m.hp, m.maxHp)
  if field == "hp" or field == "maxHp" then
    m.wounds = { hit25 = m.hp / m.maxHp <= 0.25, hit10 = m.hp / m.maxHp <= 0.10 }
  end
  Core.CommitMountMutation()
  return true
end

-- Use the same journal lookup as TRP3's CompanionProviderJournal. Unknown
-- mounts still suppress rider dodge, even if journal data is unavailable.
function Mounts.Sync()
  local s = Core.state
  if not s then return end
  local ok, mounted = pcall(function() return IsMounted and IsMounted() end)
  mounted = ok and not Shared.IsSecret(mounted) and mounted == true
  local id, name
  local journal = C_MountJournal
  if mounted and journal and journal.GetMountIDs and journal.GetMountInfoByID then
    local function active(mountID)
      local success, mountName, _, _, isActive = pcall(journal.GetMountInfoByID, mountID)
      if success and not Shared.IsSecret(isActive) and isActive == true then
        if not Shared.IsSecret(mountName) and type(mountName) == "string" then name = mountName end
        id = mountID
        return true
      end
    end
    if not s.activeMountID or s.activeMountID == 0 or not active(s.activeMountID) then
      local success, ids = pcall(journal.GetMountIDs)
      if success and type(ids) == "table" then
        for _, mountID in ipairs(ids) do
          if number(mountID, 1) == mountID and active(mountID) then break end
        end
      end
    end
  end
  if mounted then id = id or 0 end
  if s.mounted == mounted and s.activeMountID == id then return end
  s.mounted, s.activeMountID = mounted, id
  if mounted then
    ensureMount(s, id, name)
    selectedID = id
  end
  Core.RefreshMountState()
end

function Mounts.Initialize()
  if eventFrame then return end
  eventFrame = CreateFrame("Frame")
  for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_AURA", "NEW_MOUNT_ADDED" }) do
    eventFrame:RegisterEvent(event)
  end
  local pending = false
  eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    Mounts.Sync()
    -- Journal activity can settle a frame after the mount-display event.
    if not pending and C_Timer and C_Timer.After then
      pending = true
      C_Timer.After(0, function() pending = false; Mounts.Sync() end)
    end
  end)
  Mounts.Sync()
end
