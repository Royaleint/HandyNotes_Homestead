-- luacheck: push ignore 111 112 113
-- Locale file lint for WoW addons. Plain Lua 5.1, no requires, no network.
--
-- Run from the repo root:  lua tests/locale_lint.lua [<toc path>]
-- Without an argument the TOC is <package-as value>.toc from ./.pkgmeta.
-- `lua locale_lint.lua --form-lines <file>` only prints the Blizzard-backed
-- form lines it parses (FORM<TAB>line<TAB>key<TAB>GLOBAL<TAB>fallback).
--
-- Every failure prints "FAIL (<id>) <path>: <detail>" and the run exits 1.
-- A clean run prints "RESULT: OK" and exits 0.

-- The pattern must stay an ordinary quoted string: inside a long bracket the
-- escapes are not processed, "[ \t]" would match a backslash or "t", and a line
-- like tttL["x"] = X or "x" would parse.
local FORM = "^[ \t]*L%[\"([^\"\\]+)\"%][ \t]*=[ \t]*([A-Z][A-Z0-9_]*)[ \t]+or[ \t]+\"([^\"\\]*)\"[ \t]*(.*)$"
local LITERAL_DQ = "^L[ \t]*%[\"([^\"\\\n]*)\"%]"
local LITERAL_SQ = "^L[ \t]*%['([^'\\\n]*)'%]"
local L_USE = "%f[%w_]L[ \t]*[%[%.]"
local ASSIGN = "^[ \t]*L%[([\"'])(.-)%1%]%s*="

local STDLIB = {}
for _, name in ipairs({
	"assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget",
	"rawset", "select", "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
	"string", "table", "math",
}) do
	STDLIB[name] = true
end

local fails = {}

local function fail(id, path, detail)
	fails[#fails + 1] = "FAIL (" .. id .. ") " .. path .. ": " .. detail
end

local function finish()
	for i = 1, #fails do
		print(fails[i])
	end
	if #fails > 0 then
		os.exit(1)
	end
	print("RESULT: OK")
	os.exit(0)
end

local function readFile(path)
	local fh = io.open(path, "rb")
	if not fh then
		return nil
	end
	local text = fh:read("*a")
	fh:close()
	return text
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitLines(text)
	local lines = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = (line:gsub("\r$", ""))
	end
	return lines
end

local function parseForm(line)
	local key, global, fallback, rest = line:match(FORM)
	if key and (rest == "" or rest:sub(1, 2) == "--") then
		return key, global, fallback
	end
end

if arg[1] == "--form-lines" then
	local text = arg[2] and readFile(arg[2])
	if not text then
		print("FAIL (form) " .. tostring(arg[2]) .. ": cannot read file")
		os.exit(1)
	end
	for n, line in ipairs(splitLines(text)) do
		local key, global, fallback = parseForm(line)
		if key then
			print("FORM\t" .. n .. "\t" .. key .. "\t" .. global .. "\t" .. fallback)
		end
	end
	os.exit(0)
end

-- Placeholder and escape tokens, scanned left to right. Every "%" and "|"
-- belongs to some token, so a stray one becomes "%?" or "|?" and is compared too.
local function tokens(s)
	local out, i = {}, 1
	while i <= #s do
		local c = s:sub(i, i)
		if c == "%" then
			local tok = s:match("^%%[-+ #0]*%d*%.?%d*[%a%%]", i)
			if tok then
				out[#out + 1] = tok
				i = i + #tok
			else
				out[#out + 1] = "%?"
				i = i + 1
			end
		elseif c == "|" then
			local nxt = s:sub(i + 1, i + 1)
			if nxt ~= "" and ("crTtHhn|"):find(nxt, 1, true) then
				out[#out + 1] = "|" .. nxt
				i = i + 2
			else
				out[#out + 1] = "|?"
				i = i + 1
			end
		else
			i = i + 1
		end
	end
	return out
end

local function sameTokens(a, b)
	local ta, tb = tokens(a), tokens(b)
	if #ta ~= #tb then
		return false
	end
	for i = 1, #ta do
		if ta[i] ~= tb[i] then
			return false
		end
	end
	return true
end

-- TOC discovery.
local tocPath = arg[1]
if not tocPath then
	local pkg = readFile(".pkgmeta")
	local name = pkg and pkg:match("package%-as:[ \t]*([^\r\n]*)")
	if name then
		name = trim(name)
		if name ~= "" then
			tocPath = name .. ".toc"
		end
	end
end
local tocText = tocPath and readFile(tocPath)
if not tocText then
	fail("toc", tostring(tocPath or ".pkgmeta"), "cannot resolve a readable TOC")
	finish()
end

local tocDir = tocPath:match("^(.*)[/\\]") or ""
local tocBase = (tocPath:match("([^/\\]*)$")):gsub("%.toc$", "")
local function resolvePath(entry)
	if tocDir == "" then
		return entry
	end
	return tocDir .. "/" .. entry
end

local KNOWN_LOCALE = {}
for _, code in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
	KNOWN_LOCALE[code] = true
end

local localeFiles, codeFiles, enUSEntry = {}, {}, nil
for _, raw in ipairs(splitLines(tocText)) do
	local entry = trim(raw):gsub("\\", "/")
	-- A trailing load directive such as [AllowLoadGameType standard] is not part of the path.
	entry = entry:gsub("%s+%[[^%]]*%]$", "")
	if entry ~= "" and entry:sub(1, 1) ~= "#" and entry:match("%.lua$") then
		-- The prefix match ignores case: Windows resolves locale\deDE.lua to the same file.
		if entry:sub(1, 7):lower() == "locale/" then
			local loc = entry:sub(8):match("^(%a%a%a%a)%.lua$")
			if loc == "enUS" then
				enUSEntry = entry
			elseif loc and KNOWN_LOCALE[loc] then
				localeFiles[#localeFiles + 1] = { locale = loc, entry = entry }
			else
				fail("locale-name", entry, "a Locale/ entry must be <WoW locale code>.lua")
			end
		else
			codeFiles[#codeFiles + 1] = entry
		end
	end
end

if not enUSEntry then
	fail("vacuity", tocPath, "TOC lists no Locale/enUS.lua")
	finish()
end

local function loadText(entry)
	local text = readFile(resolvePath(entry))
	if not text then
		fail("a", entry, "cannot read file")
	end
	return text
end

-- Runs one chunk with a recording environment. Chunk global writes are discarded,
-- so a later read of the same name is still counted.
local state = { reads = {} }
local function runChunk(entry, text, locale, ns)
	local fn, err = loadstring(text, "@" .. entry)
	if not fn then
		fail("a", entry, tostring(err))
		return false
	end
	local env = setmetatable({}, {
		__index = function(_, k)
			state.reads[k] = (state.reads[k] or 0) + 1
			if k == "GetLocale" then
				return function()
					return locale
				end
			end
			if STDLIB[k] then
				return _G[k]
			end
		end,
		__newindex = function() end,
	})
	setfenv(fn, env)
	local ok, runErr = pcall(fn, tocBase, ns)
	if not ok then
		fail("a", entry, tostring(runErr))
		return false
	end
	return true
end

local function assignedKeys(text, marker)
	local keys = {}
	for _, line in ipairs(splitLines(text)) do
		local _, key = line:match(ASSIGN)
		if key and line:match("%-%-[ \t]*" .. marker .. "[ \t]*$") then
			keys[#keys + 1] = key
		end
	end
	return keys
end

-- (g) The leading comment region: blank lines, "--" comments and long comments.
local function leadingComments(text)
	local i, region = 1, {}
	while true do
		local s = text:find("%S", i)
		if not s then
			break
		end
		local level = text:match("^%-%-%[(=*)%[", s)
		if level then
			local _, closeEnd = text:find("]" .. level .. "]", s, true)
			region[#region + 1] = text:sub(s, closeEnd or #text)
			i = (closeEnd or #text) + 1
		elseif text:sub(s, s + 1) == "--" then
			local nl = text:find("\n", s, true) or #text
			region[#region + 1] = text:sub(s, nl)
			i = nl + 1
		else
			break
		end
	end
	return table.concat(region, "\n")
end

-- enUS: execute, then derive the form lines (B) and the allowlist from its text.
local enUSText = loadText(enUSEntry)
if not enUSText then
	finish()
end
local ns = {}
if not runChunk(enUSEntry, enUSText, "enUS", ns) then
	finish()
end
if type(ns.L) ~= "table" then
	fail("a", enUSEntry, "enUS did not define ns.L as a table")
	finish()
end
local enUSReads = state.reads
local snapshot = {}
for k, v in pairs(ns.L) do
	snapshot[k] = v
end

local B, formCount = {}, {}
for _, line in ipairs(splitLines(enUSText)) do
	local key, global, fallback = parseForm(line)
	if key then
		B[key] = { global = global, fallback = fallback }
		formCount[global] = (formCount[global] or 0) + 1
	end
end

local allowlist = {}
for _, key in ipairs(assignedKeys(enUSText, "untranslated")) do
	allowlist[key] = true
end

do
	local seen = {}
	for _, line in ipairs(splitLines(enUSText)) do
		local _, key = line:match(ASSIGN)
		if key then
			if seen[key] then
				fail("h", enUSEntry, 'key assigned twice: "' .. key .. '"')
			end
			seen[key] = true
		end
	end
end

for global, count in pairs(enUSReads) do
	local forms = formCount[global] or 0
	if global ~= "GetLocale" and count > forms then
		fail("j2a", enUSEntry, global .. " read " .. count .. " times, " .. forms .. " form lines")
	end
end
for global, forms in pairs(formCount) do
	local count = enUSReads[global] or 0
	if count < forms then
		fail("j2b", enUSEntry, global .. " read " .. count .. " times, " .. forms .. " form lines")
	end
end
for key, form in pairs(B) do
	if form.fallback:find("[%%|]") then
		fail("j4", enUSEntry, 'fallback of "' .. key .. '" holds a placeholder or escape')
	end
end

-- Each locale: a fresh ns, enUS first, then the locale file into the same ns.
for _, file in ipairs(localeFiles) do
	local entry, locale = file.entry, file.locale
	local text = loadText(entry)
	if text then
		if not leadingComments(text):find("Machine-translated", 1, true) then
			fail("g", entry, "no provenance header")
		end
		for _, key in ipairs(assignedKeys(text, "human%-translated")) do
			print("person-written: " .. locale .. ' "' .. key .. '"')
		end

		-- (b), (d) and (e) compare against the enUS snapshot taken before any locale file runs.
		local lns = {}
		state.reads = {}
		runChunk(enUSEntry, enUSText, "enUS", lns)
		state.reads = {}
		local under = lns.L
		local records = {}
		lns.L = setmetatable({}, {
			__index = under,
			__newindex = function(_, k, v)
				records[#records + 1] = { key = k, value = v, enUS = snapshot[k] }
				rawset(under, k, v)
			end,
		})

		if runChunk(entry, text, locale, lns) then
			local assigned = {}
			for _, rec in ipairs(records) do
				local key, value = rec.key, rec.value
				if assigned[key] then
					fail("h", entry, 'key assigned twice: "' .. tostring(key) .. '"')
				end
				assigned[key] = true
				if rec.enUS == nil then
					fail("b", entry, 'key not defined in enUS: "' .. tostring(key) .. '"')
				end
				if type(value) ~= "string" then
					fail("i", entry, 'value is not a string: "' .. tostring(key) .. '"')
				elseif B[key] then
					fail("j1", entry, 'Blizzard-backed key assigned: "' .. tostring(key) .. '"')
				elseif type(rec.enUS) == "string" then
					if not sameTokens(rec.enUS, value) then
						fail("d", entry, 'placeholder or escape mismatch: "' .. tostring(key) .. '"')
					end
					if value == rec.enUS and not allowlist[key] then
						fail("e", entry, 'value identical to English: "' .. tostring(key) .. '"')
					end
				end
			end
			for key in pairs(snapshot) do
				if not assigned[key] and not B[key] then
					fail("c", entry, 'key missing: "' .. tostring(key) .. '"')
				end
			end
			for global in pairs(state.reads) do
				if global ~= "GetLocale" then
					fail("j3", entry, "reads global " .. global)
				end
			end
		end
	end
end

-- (f) Addon code: every L use is a string-literal index of a key enUS defines.
for _, entry in ipairs(codeFiles) do
	local text = loadText(entry)
	if text then
		local init = 1
		while true do
			local s = text:find(L_USE, init)
			if not s then
				break
			end
			local key = text:match(LITERAL_DQ, s) or text:match(LITERAL_SQ, s)
			if not key then
				fail("f-index", entry, "L indexed with a non-literal near byte " .. s)
			elseif snapshot[key] == nil then
				fail("f", entry, 'key not defined in enUS: "' .. key .. '"')
			end
			init = s + 1
		end
	end
end

finish()
-- luacheck: pop
