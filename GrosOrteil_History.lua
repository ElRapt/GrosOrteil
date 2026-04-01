local _, ns = ...

local History = {}
ns.History = History

History.MAX = 60

function History.NowTimestamp()
	local t = rawget(_G, "time")
	if type(t) == "function" then
		local ok, v = pcall(t)
		if ok and type(v) == "number" then return v end
	end
	local gt = rawget(_G, "GetTime")
	if type(gt) == "function" then
		local ok, v = pcall(gt)
		if ok and type(v) == "number" then return v end
	end
	return nil
end

function History.EnsureState(s)
	if not s then return end
	if type(s.history) ~= "table" then
		s.history = {}
	end
end

function History.Push(state, entry)
	if type(state) ~= "table" then return end
	if type(entry) ~= "table" then return end
	History.EnsureState(state)
	if entry.ts == nil then
		entry.ts = History.NowTimestamp()
	end
	table.insert(state.history, 1, entry)
	local max = History.MAX or 60
	while #state.history > max do
		table.remove(state.history)
	end
end

function History.Get(state)
	if type(state) ~= "table" then return {} end
	History.EnsureState(state)
	return state.history
end

function History.Clear(state)
	if type(state) ~= "table" then return end
	state.history = {}
end

local function fmtInt(x)
	if type(x) ~= "number" then return 0 end
	if x >= 0 then return math.floor(x + 0.5) end
	return -math.floor((-x) + 0.5)
end

local function fmtTime(ts)
	if type(ts) ~= "number" then return "" end
	local d = rawget(_G, "date")
	if type(d) == "function" then
		local ok, s = pcall(d, "%H:%M:%S", ts)
		if ok and type(s) == "string" then return s end
	end
	return ""
end

local function colorize(text, hex)
	if text == nil then return "" end
	if type(text) ~= "string" then text = tostring(text) end
	if type(hex) ~= "string" or hex == "" then return text end
	-- hex expected as "RRGGBB" or "AARRGGBB"
	if #hex == 6 then
		return "|cFF" .. hex .. text .. "|r"
	end
	if #hex == 8 then
		return "|c" .. hex .. text .. "|r"
	end
	return text
end

local COLORS = {
	DAMAGE = "E55353", -- red
	HEAL = "33CC66", -- green
	DIVINE = "33B5E5", -- cyan/blue
	BEFORE = "FFB347", -- orange
	RESULT = "FFFF00", -- very bright yellow (stands out strongly)
}

function History.FormatEntry(e)
	if type(e) ~= "table" then return nil end
	local t = fmtTime(e.ts)
	if t ~= "" then t = "[" .. t .. "]" end

	local function sep(parts)
		return table.concat(parts, " | ")
	end

	local function block(l1, l2, l3)
		return table.concat({ l1, l2, l3 }, "\n")
	end

	local function prefix(label, color)
		if e.subject == "PET" then
			label = "[Familier] " .. label
		end
		if t ~= "" then
			return t .. " " .. colorize(label, color)
		end
		return colorize(label, color)
	end

	if e.kind == "DAMAGE_ARMOR" then
		if e.dodged then
			return block(
				sep({
					prefix("Dégâts subis (armure)", COLORS.DAMAGE),
					"Valeur " .. fmtInt(e.input),
					"Résultat " .. colorize("ESQUIVÉ", COLORS.RESULT),
				}),
				sep({
					"Esquive " .. fmtInt(e.dodge),
					"Blocage -",
					"Blocage magique -",
				}),
				sep({
					"Avant " .. colorize(fmtInt(e.hpBefore), COLORS.BEFORE),
					"Après " .. colorize(fmtInt(e.hpAfter), COLORS.RESULT),
				})
			)
		end
		return block(
			sep({
				prefix("Dégâts subis (armure)", COLORS.DAMAGE),
				"Valeur " .. fmtInt(e.input),
				"Résultat " .. colorize(fmtInt(e.damage), COLORS.RESULT),
			}),
			sep({
				"Esquive " .. fmtInt(e.dodge or 0),
				"Blocage " .. fmtInt(e.absorbedBlock),
				"Blocage magique " .. fmtInt(e.absorbedMagic),
				"Réduction " .. fmtInt(e.mitigation),
			}),
			sep({
				"Avant " .. colorize(fmtInt(e.hpBefore), COLORS.BEFORE),
				"Après " .. colorize(fmtInt(e.hpAfter), COLORS.RESULT),
			})
		)
	elseif e.kind == "DAMAGE_TRUE" then
		if e.dodged then
			return block(
				sep({
					prefix("Dégâts subis (bruts)", COLORS.DAMAGE),
					"Valeur " .. fmtInt(e.input),
					"Résultat " .. colorize("ESQUIVÉ", COLORS.RESULT),
				}),
				sep({
					"Esquive " .. fmtInt(e.dodge),
					"Blocage magique -",
					"Réduction -",
				}),
				sep({
					"Avant " .. colorize(fmtInt(e.hpBefore), COLORS.BEFORE),
					"Après " .. colorize(fmtInt(e.hpAfter), COLORS.RESULT),
				})
			)
		end
		return block(
			sep({
				prefix("Dégâts subis (bruts)", COLORS.DAMAGE),
				"Valeur " .. fmtInt(e.input),
				"Résultat " .. colorize(fmtInt(e.damage), COLORS.RESULT),
			}),
			sep({
				"Esquive " .. fmtInt(e.dodge or 0),
				"Blocage magique " .. fmtInt(e.absorbedMagic),
				"Réduction " .. fmtInt(e.mitigation),
			}),
			sep({
				"Avant " .. colorize(fmtInt(e.hpBefore), COLORS.BEFORE),
				"Après " .. colorize(fmtInt(e.hpAfter), COLORS.RESULT),
			})
		)
	elseif e.kind == "HEAL" then
		return block(
			sep({
				prefix("Soins reçus", COLORS.HEAL),
				"Valeur " .. fmtInt(e.input),
			}),
			sep({
				"Plafond " .. fmtInt(e.capMax),
				"Max effectif " .. fmtInt(e.effMax),
				"Résultat " .. colorize(fmtInt(e.applied), COLORS.RESULT),
			}),
			sep({
				"Avant " .. colorize(fmtInt(e.hpBefore), COLORS.BEFORE),
				"Après " .. colorize(fmtInt(e.hpAfter), COLORS.RESULT),
			})
		)
	elseif e.kind == "DIVINE_HEAL" then
		return block(
			sep({
				prefix("Soins divins reçus", COLORS.DIVINE),
				"Valeur " .. fmtInt(e.gain),
			}),
			sep({
				"Plafond bypassé",
				"Max effectif " .. fmtInt((e.maxHp or 0) + (e.bonusHp or 0)),
				"Résultat " .. colorize(fmtInt(e.gain), COLORS.RESULT),
			}),
			sep({
				"Avant " .. colorize(fmtInt(e.hpBefore), COLORS.BEFORE),
				"Après " .. colorize(fmtInt(e.hpAfter), COLORS.RESULT),
			})
		)
	end

	return nil
end

-- subjectFilter: "CHAR" = only character entries, "PET" = only pet entries, nil = all
function History.FormatHistoryText(history, undoneCount, subjectFilter)
	if type(history) ~= "table" or #history == 0 then return nil end
	undoneCount = undoneCount or 0
	local lines = {}
	local actionsSeen = 0
	for i = 1, #history do
		local e = history[i]
		local isUndoRedo = (e.kind == "UNDO" or e.kind == "REDO")
		if not isUndoRedo then
			actionsSeen = actionsSeen + 1
		end
		if isUndoRedo or actionsSeen > undoneCount then
			local include = true
			if subjectFilter and not isUndoRedo then
				local eSub = e.subject
				if subjectFilter == "PET" then
					include = (eSub == "PET")
				elseif subjectFilter == "CHAR" then
					include = (eSub ~= "PET")
				end
			end
			if include then
				local line = History.FormatEntry(e)
				if line then lines[#lines + 1] = line end
			end
		end
	end
	if #lines == 0 then return nil end
	return table.concat(lines, "\n\n")
end

