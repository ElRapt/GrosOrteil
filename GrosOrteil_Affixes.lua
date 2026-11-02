-- Local custom-affix definitions. Core owns activation, turns and undo.
local _, ns = ...
local Affixes = {}
ns.Affixes = Affixes

Affixes.STATS = {
  { key = "maxHp", label = "PV maximum" },
  { key = "armor", label = "Armure" },
  { key = "trueArmor", label = "Armure véritable" },
  { key = "tempArmor", label = "Armure temporaire" },
  { key = "dodge", label = "Esquive" },
  { key = "attaqueMelee", label = "Attaque au corps à corps" },
  { key = "attaqueDistance", label = "Attaque à distance" },
  { key = "regenParTour", label = "Régénération par tour" },
  { key = "perception", label = "Perception", playerOnly = true },
}
Affixes.BY_STAT = {}
for _, stat in ipairs(Affixes.STATS) do Affixes.BY_STAT[stat.key] = stat end

local function finite(value, minimum, maximum)
  return type(value) == "number" and value == value and value >= minimum and value <= maximum
end

function Affixes.Validate(input, isPet)
  if type(input) ~= "table" then return nil, "Affixe invalide." end
  local name = type(input.name) == "string" and input.name:match("^%s*(.-)%s*$") or ""
  local _, letters = name:gsub("[^\128-\191]", "")
  if name == "" or letters > 80 or name:find("[%c|]") then
    return nil, "Saisissez un nom sans code de mise en forme (80 caractères maximum)."
  end
  local color = input.color
  if type(color) ~= "table" or not finite(color.r, 0, 1)
      or not finite(color.g, 0, 1) or not finite(color.b, 0, 1) then
    return nil, "Choisissez une couleur valide."
  end
  local duration = input.duration
  if duration ~= nil and (not finite(duration, 1, 9999) or duration ~= math.floor(duration)) then
    return nil, "La durée doit être un nombre entier de 1 à 9999 tours."
  end
  if type(input.effects) ~= "table" or #input.effects < 1 or #input.effects > #Affixes.STATS then
    return nil, "Ajoutez au moins une statistique."
  end
  local count = 0
  for index in pairs(input.effects) do
    if not finite(index, 1, #input.effects) or index ~= math.floor(index) then
      return nil, "Liste de statistiques invalide."
    end
    count = count + 1
  end
  if count ~= #input.effects then return nil, "Liste de statistiques invalide." end
  local out = { name = name, color = { r = color.r, g = color.g, b = color.b },
    duration = duration, effects = {} }
  local seen = {}
  for _, effect in ipairs(input.effects) do
    local stat = type(effect) == "table" and Affixes.BY_STAT[effect.stat]
    if not stat or (isPet and stat.playerOnly) then return nil, "Statistique invalide pour cette fiche." end
    if seen[stat.key] then return nil, "Chaque statistique ne peut apparaître qu'une fois." end
    if not finite(effect.value, -1e9, 1e9) or effect.value == 0 then
      return nil, "Chaque valeur doit être un nombre non nul entre -1 000 000 000 et 1 000 000 000."
    end
    seen[stat.key] = true
    out.effects[#out.effects + 1] = { stat = stat.key, value = effect.value }
  end
  return out
end

function Affixes.Find(holder, key)
  if type(holder) ~= "table" or type(holder.customAffixes) ~= "table" then return nil end
  for index, def in ipairs(holder.customAffixes) do
    if def.id == key then return def, index end
  end
end

function Affixes.Deltas(holder, key)
  local def = Affixes.Find(holder, key)
  if not def then return nil end
  local deltas = {}
  for _, effect in ipairs(def.effects) do deltas[effect.stat] = effect.value end
  -- Like Cambuse PV, increasing maximum health also increases current health.
  if deltas.maxHp then deltas.hp = deltas.maxHp end
  return deltas
end

function Affixes.Summary(def)
  local parts = {}
  for _, effect in ipairs(def.effects) do
    local stat = Affixes.BY_STAT[effect.stat]
    parts[#parts + 1] = string.format("%+g %s", effect.value, stat.label)
  end
  return table.concat(parts, "\n")
end
