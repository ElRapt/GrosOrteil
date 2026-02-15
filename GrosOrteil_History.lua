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
	if type(text) ~= "string" then return text end
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
	RESULT = "FFFF00", -- very bright yellow (stands out strongly)
}

function History.FormatEntry(e)
	if type(e) ~= "table" then return nil end
	local t = fmtTime(e.ts)
	if t ~= "" then t = "[" .. t .. "] " end

	if e.kind == "DAMAGE_ARMOR" then
		if e.dodged then
			return table.concat({
				t,
				colorize("- Dégâts (armure)", COLORS.DAMAGE),
				" : ",
				tostring(fmtInt(e.input)),
				" - Esquive : ",
				tostring(fmtInt(e.dodge)),
				" - Résultat : ",
				colorize("ESQUIVÉ", COLORS.RESULT),
				" - Points de vie : avant ",
				tostring(fmtInt(e.hpBefore)),
				" - après ",
				colorize(tostring(fmtInt(e.hpAfter)), COLORS.RESULT),
			})
		end
		return table.concat({
			t,
			colorize("- Dégâts (armure)", COLORS.DAMAGE),
			" : ",
			tostring(fmtInt(e.input)),
			" - Blocage : ",
			tostring(fmtInt(e.absorbedBlock)),
			" - Blocage magique : ",
			tostring(fmtInt(e.absorbedMagic)),
			" - Réduction : ",
			tostring(fmtInt(e.mitigation)),
			" - TOTAL dégâts subis : ",
			colorize(tostring(fmtInt(e.damage)), COLORS.RESULT),
			" - Points de vie : avant ",
			tostring(fmtInt(e.hpBefore)),
			" - après ",
			colorize(tostring(fmtInt(e.hpAfter)), COLORS.RESULT),
		})
	elseif e.kind == "DAMAGE_TRUE" then
		if e.dodged then
			return table.concat({
				t,
				colorize("- Dégâts (bruts)", COLORS.DAMAGE),
				" : ",
				tostring(fmtInt(e.input)),
				" - Esquive : ",
				tostring(fmtInt(e.dodge)),
				" - Résultat : ",
				colorize("ESQUIVÉ", COLORS.RESULT),
				" - Points de vie : avant ",
				tostring(fmtInt(e.hpBefore)),
				" - après ",
				colorize(tostring(fmtInt(e.hpAfter)), COLORS.RESULT),
			})
		end
		return table.concat({
			t,
			colorize("- Dégâts (bruts)", COLORS.DAMAGE),
			" : ",
			tostring(fmtInt(e.input)),
			" - Blocage magique : ",
			tostring(fmtInt(e.absorbedMagic)),
			" - Réduction : ",
			tostring(fmtInt(e.mitigation)),
			" - TOTAL dégâts subis : ",
			colorize(tostring(fmtInt(e.damage)), COLORS.RESULT),
			" - Points de vie : avant ",
			tostring(fmtInt(e.hpBefore)),
			" - après ",
			colorize(tostring(fmtInt(e.hpAfter)), COLORS.RESULT),
		})
	elseif e.kind == "HEAL" then
		return table.concat({
			t,
			colorize("- Soins", COLORS.HEAL),
			" : ",
			tostring(fmtInt(e.input)),
			" - Plafond : ",
			tostring(fmtInt(e.capMax)),
			" - Maximum effectif : ",
			tostring(fmtInt(e.effMax)),
			" - TOTAL soins appliqués : ",
			colorize(tostring(fmtInt(e.applied)), COLORS.RESULT),
			" - Points de vie : avant ",
			tostring(fmtInt(e.hpBefore)),
			" - après ",
			colorize(tostring(fmtInt(e.hpAfter)), COLORS.RESULT),
		})
	elseif e.kind == "DIVINE_HEAL" then
		return table.concat({
			t,
			colorize("- Soins divins", COLORS.DIVINE),
			" : ",
			colorize(tostring(fmtInt(e.gain)), COLORS.RESULT),
			" - Points de vie : avant ",
			tostring(fmtInt(e.hpBefore)),
			" - après ",
			colorize(tostring(fmtInt(e.hpAfter)), COLORS.RESULT),
		})
	end

	return nil
end

function History.FormatHistoryText(history)
	if type(history) ~= "table" or #history == 0 then return nil end
	local lines = {}
	for i = 1, #history do
		local line = History.FormatEntry(history[i])
		if line then
			lines[#lines + 1] = line
		end
	end
	if #lines == 0 then return nil end
	return table.concat(lines, "\n")
end

