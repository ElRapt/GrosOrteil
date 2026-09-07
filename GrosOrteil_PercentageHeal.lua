---@diagnostic disable: undefined-global
-- Signed percentage-based HP changes for the Fiche and pet action panels.
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
  if not percent or percent ~= percent or math.abs(percent) < 1 or math.abs(percent) > 100 then return nil end
  return percent
end

PercentageHeal.NormalizePercent = normalizePercent

local function percentageHP(target, percent)
  local maxHp = tonumber(target.maxHp)
  local before = tonumber(target.hp)
  -- Match the Core setters' supported HP range before recording history.
  if not maxHp or maxHp ~= maxHp or maxHp < 1 or maxHp > 1e9
      or not before or before ~= before or before < 0 or before > maxHp then
    return nil
  end
  local after = math.max(0, math.min(maxHp, before + (maxHp * percent / 100)))
  return before, after, maxHp
end

local function addPercentageHistory(state, percent, before, after, maxHp, subject)
  if not History or not History.Push then return end
  History.Push(state, {
    kind = percent < 0 and "PERCENT_DAMAGE" or "PERCENT_HEAL",
    subject = subject,
    percent = percent,
    applied = math.abs(after - before),
    hpBefore = before,
    hpAfter = after,
    maxHp = maxHp,
  })
end

function Core.PercentageHeal(value)
  local percent = normalizePercent(value)
  local state = Core.state
  if not state or not percent then return false end

  local before, after, maxHp = percentageHP(state, percent)
  if not before then return false end
  addPercentageHistory(state, percent, before, after, maxHp)
  Core.SetHP(after, maxHp)
  if after ~= before and Core.EmitCombatText then
    Core.EmitCombatText(percent < 0 and "DAMAGE" or "HEAL", math.abs(after - before), "CHAR")
  end
  return true
end

function Core.PetPercentageHeal(value)
  local percent = normalizePercent(value)
  local state = Core.state
  local pet = state and state.pet
  if not state or type(pet) ~= "table" or not pet.enabled or not percent then return false end

  local before, after, maxHp = percentageHP(pet, percent)
  if not before then return false end
  addPercentageHistory(state, percent, before, after, maxHp, "PET")
  Core.SetPetHP(after, maxHp)
  if after ~= before and Core.EmitCombatText then
    Core.EmitCombatText(percent < 0 and "DAMAGE" or "HEAL", math.abs(after - before), "PET")
  end
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
    if type(entry) == "table" and (entry.kind == "PERCENT_HEAL" or entry.kind == "PERCENT_DAMAGE") then
      local subject = entry.subject == "PET" and "[Familier] " or ""
      local damage = entry.kind == "PERCENT_DAMAGE"
      return string.format(
        "%s%s en pourcentage | Pourcentage %s%% | Résultat %d\n"
          .. "%s | Max effectif %d\nAvant %d | Après %d",
        subject,
        damage and "Dégâts" or "Soin",
        tostring(entry.percent or 0),
        fmtInt(entry.applied),
        damage and "Armure et boucliers ignorés" or "Plafond bypassé",
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
    printer("|cFF66CC66GrosOrteil|r Saisissez un pourcentage de -100 à -1 (dégâts) ou de 1 à 100 (soins).")
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
        and "Modifie les PV du familier selon un pourcentage de son maximum : 15 ou +15 soigne 15 %, -15 inflige 15 % de dégâts. Valeurs de -100 à -1 ou de 1 à 100. Les soins ignorent les plafonds de blessure ; les dégâts ignorent l'armure et les boucliers."
        or "Modifie les PV selon un pourcentage du maximum : 15 ou +15 soigne 15 %, -15 inflige 15 % de dégâts. Valeurs de -100 à -1 ou de 1 à 100. Les soins ignorent les plafonds de blessure ; les dégâts ignorent l'armure et les boucliers.",
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
        -- WoW's numeric EditBox mode filters the leading '+' and '-' keys.
        -- Keep signed input local to action values; Core validates each action.
        if edit.SetNumeric then edit:SetNumeric(false) end
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
