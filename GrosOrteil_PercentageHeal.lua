---@diagnostic disable: undefined-global
-- Percentage-based bypass healing for the Fiche and pet action panels.
-- Loaded after the existing modules so it can extend Core/History and adapt
-- the tab builders without duplicating their large UI implementations.
local _, ns = ...

local Core = ns.Core
local History = ns.History
local tonumber = tonumber
local tostring = tostring
local math = math
local string = string
local type = type
local rawget = rawget

local PercentageHeal = {}
ns.PercentageHeal = PercentageHeal

local function normalizePercent(value)
  local percent = tonumber(value)
  if not percent or percent < 1 or percent > 100 then return nil end
  return percent
end

PercentageHeal.NormalizePercent = normalizePercent

local function addPercentageHistory(state, percent, before, after, maxHp, subject)
  if not History or not History.Push then return end
  History.Push(state, {
    kind = "PERCENT_HEAL",
    subject = subject,
    percent = percent,
    applied = math.max(0, after - before),
    hpBefore = before,
    hpAfter = after,
    maxHp = maxHp,
  })
end

function Core.PercentageHeal(value)
  local percent = normalizePercent(value)
  local state = Core.state
  if not state or not percent then return false end

  local maxHp = tonumber(state.maxHp) or 0
  if maxHp <= 0 then return false end

  local before = tonumber(state.hp) or 0
  local after = math.min(maxHp, before + (maxHp * percent / 100))
  addPercentageHistory(state, percent, before, after, maxHp)
  Core.SetHP(after, maxHp)
  return true
end

function Core.PetPercentageHeal(value)
  local percent = normalizePercent(value)
  local state = Core.state
  local pet = state and state.pet
  if not state or type(pet) ~= "table" or not pet.enabled or not percent then return false end

  local maxHp = tonumber(pet.maxHp) or 0
  if maxHp <= 0 then return false end

  local before = tonumber(pet.hp) or 0
  local after = math.min(maxHp, before + (maxHp * percent / 100))
  addPercentageHistory(state, percent, before, after, maxHp, "PET")
  Core.SetPetHP(after, maxHp)
  return true
end

-- Keep new actions visible in the existing history panels while preserving
-- formatting support for legacy DIVINE_HEAL/SURGERY entries.
if History and History.FormatEntry then
  local originalFormatEntry = History.FormatEntry

  local function fmtInt(value)
    local n = tonumber(value) or 0
    if n >= 0 then return math.floor(n + 0.5) end
    return -math.floor((-n) + 0.5)
  end

  function History.FormatEntry(entry)
    if type(entry) == "table" and entry.kind == "PERCENT_HEAL" then
      local subject = entry.subject == "PET" and "[Familier] " or ""
      return string.format(
        "%sSoin en pourcentage | Pourcentage %s%% | Résultat %d\n"
          .. "Plafond bypassé | Max effectif %d\nAvant %d | Après %d",
        subject,
        tostring(entry.percent or 0),
        fmtInt(entry.applied),
        fmtInt(entry.maxHp),
        fmtInt(entry.hpBefore),
        fmtInt(entry.hpAfter)
      )
    end
    return originalFormatEntry(entry)
  end
end

local function invalidPercentMessage()
  local printer = rawget(_G, "print")
  if printer then
    printer("|cFF66CC66GrosOrteil|r Le pourcentage doit être compris entre 1 et 100.")
  end
end

local function setPercentageTooltip(button, pet)
  if not button or not button.SetScript then return end
  button:SetScript("OnEnter", function(self)
    local tooltip = rawget(_G, "GameTooltip")
    if not tooltip then return end
    tooltip:SetOwner(self, "ANCHOR_TOP")
    tooltip:ClearLines()
    tooltip:AddLine("Pourcentage", 1, 0.82, 0.22)
    tooltip:AddLine(
      pet
        and "Interprète Valeur comme un pourcentage (1 à 100) du maximum de PV du familier et le restaure en ignorant les plafonds de blessure."
        or "Interprète Valeur comme un pourcentage (1 à 100) du maximum de PV et le restaure en ignorant les plafonds de blessure.",
      1, 1, 1, true)
    tooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    local tooltip = rawget(_G, "GameTooltip")
    if tooltip then tooltip:Hide() end
  end)
end

-- UI_Tabs keeps the action value edit boxes and bypass-heal buttons local to
-- each builder. Wrap the widget factories before those builders capture them,
-- so the existing layout is reused without duplicating UI code.
local function wrapPercentageBuilder(builderName, buttonWidth)
  local originalBuilder = ns[builderName]
  if type(originalBuilder) ~= "function" then return end

  ns[builderName] = function(ctx)
    local originalMkLabel = ctx.mkLabel
    local originalMkEdit = ctx.mkEdit
    local originalMkButton = ctx.mkButton
    local pendingValue = false
    local valueEdit = nil
    local percentageButton = nil

    ctx.mkLabel = function(parent, text, ...)
      local label = originalMkLabel(parent, text, ...)
      if text == "Valeur" then pendingValue = true end
      return label
    end

    ctx.mkEdit = function(...)
      local edit = originalMkEdit(...)
      if pendingValue then
        valueEdit = edit
        pendingValue = false
      end
      return edit
    end

    ctx.mkButton = function(parent, text, width, height, x, y, onClick)
      if text == "Soins divins (75%)" then
        percentageButton = originalMkButton(parent, "Pourcentage", buttonWidth, height, x, y, function()
          local value = (valueEdit and ctx.getNumber) and ctx.getNumber(valueEdit) or nil
          local ok
          if builderName == "UI_BuildPetFicheTab" then
            ok = Core and Core.PetPercentageHeal and Core.PetPercentageHeal(value)
          else
            ok = Core and Core.PercentageHeal and Core.PercentageHeal(value)
          end
          if not ok then invalidPercentMessage() end
        end)
        return percentageButton
      end

      if text == "Chirurgie (50%)" then
        local button = originalMkButton(parent, text, width, height, x, y, onClick)
        if button.Hide then button:Hide() end
        if button.Disable then button:Disable() end
        return button
      end

      return originalMkButton(parent, text, width, height, x, y, onClick)
    end

    originalBuilder(ctx)

    ctx.mkLabel = originalMkLabel
    ctx.mkEdit = originalMkEdit
    ctx.mkButton = originalMkButton

    -- The original builder attaches the former Soins divins tooltip after
    -- mkButton returns; replace those scripts once construction is complete.
    setPercentageTooltip(percentageButton, builderName == "UI_BuildPetFicheTab")
  end
end

wrapPercentageBuilder("UI_BuildFicheTab", 440)
wrapPercentageBuilder("UI_BuildPetFicheTab", 380)
