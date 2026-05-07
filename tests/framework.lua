---@diagnostic disable: undefined-global, ambiguity-1
-- Tiny test framework: describe/it + assertions + run().
-- Lua 5.1 / 5.4 compatible. No dependencies.
-- Run from a standalone Lua interpreter, NOT from inside WoW.

local M = {}

local suites = {}
local currentSuite

function M.describe(name, fn)
  local s = { name = name, tests = {} }
  suites[#suites + 1] = s
  local prev = currentSuite
  currentSuite = s
  fn()
  currentSuite = prev
end

function M.it(name, fn)
  if not currentSuite then
    error("it() called outside describe()")
  end
  currentSuite.tests[#currentSuite.tests + 1] = { name = name, fn = fn }
end

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "table" then
    local parts = {}
    for k, vv in pairs(v) do
      parts[#parts + 1] = tostring(k) .. "=" .. tostring(vv)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(v)
end

function M.assertEq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "assertEq") .. ": expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
  end
end

function M.assertNeq(actual, unexpected, msg)
  if actual == unexpected then
    error((msg or "assertNeq") .. ": expected NOT " .. fmt(unexpected), 2)
  end
end

function M.assertTrue(v, msg)
  if not v then error(msg or "assertTrue: expected truthy, got " .. fmt(v), 2) end
end

function M.assertFalse(v, msg)
  if v then error(msg or "assertFalse: expected falsy, got " .. fmt(v), 2) end
end

function M.assertNil(v, msg)
  if v ~= nil then error((msg or "assertNil") .. ": got " .. fmt(v), 2) end
end

function M.assertNotNil(v, msg)
  if v == nil then error(msg or "assertNotNil: got nil", 2) end
end

function M.assertNear(actual, expected, eps, msg)
  eps = eps or 1e-6
  if type(actual) ~= "number" or type(expected) ~= "number" then
    error((msg or "assertNear") .. ": non-numeric", 2)
  end
  if math.abs(actual - expected) > eps then
    error((msg or "assertNear") .. ": expected " .. tostring(expected)
      .. " ±" .. tostring(eps) .. ", got " .. tostring(actual), 2)
  end
end

local function deepEq(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function M.assertDeepEq(actual, expected, msg)
  if not deepEq(actual, expected) then
    error((msg or "assertDeepEq") .. ": tables differ", 2)
  end
end

function M.assertError(fn, msg)
  local ok = pcall(fn)
  if ok then error(msg or "assertError: function did not error", 2) end
end

local function runOne(t)
  local ok, err = xpcall(t.fn, function(e)
    return tostring(e) .. "\n" .. debug.traceback("", 2)
  end)
  return ok, err
end

function M.run(opts)
  opts = opts or {}
  local verbose = opts.verbose
  local pass, fail = 0, 0
  local failures = {}
  local startTotal = os.clock()

  for _, s in ipairs(suites) do
    if verbose then print("[" .. s.name .. "]") end
    for _, t in ipairs(s.tests) do
      local ok, err = runOne(t)
      if ok then
        pass = pass + 1
        if verbose then print("  PASS  " .. t.name) end
      else
        fail = fail + 1
        failures[#failures + 1] = { suite = s.name, test = t.name, err = err }
        print("  FAIL  " .. s.name .. " :: " .. t.name)
        for line in tostring(err):gmatch("[^\n]+") do
          print("        " .. line)
        end
      end
    end
  end

  local elapsed = os.clock() - startTotal
  print(string.format("\n%d passed, %d failed (%.3fs)", pass, fail, elapsed))
  return fail == 0, pass, fail, failures
end

function M.reset()
  suites = {}
  currentSuite = nil
end

return M
