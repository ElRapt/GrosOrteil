---@diagnostic disable: undefined-global
-- End-to-end scenario: simulates a full play session walking through every
-- major feature in sequence. Each step asserts the state we expect AND
-- verifies the Comm round-trip still produces an identical decoded state.
--
-- This is intentionally one giant linear test rather than many small ones —
-- it catches *cross-feature* regressions (e.g. "switching class after a heal
-- subtly invalidates the magic shield") that small unit tests can miss.

local T = _G.T
local ns = _G.NS
local Core = ns.Core
local Comm = ns.Comm
local History = ns.History
local Shared = ns.Shared

local function reset() Core.ResetToDefaults() end

-- Helper: serialize current state and deserialize it back; assert key fields match.
local function roundtripCheck(stepName)
  local s = Comm.SerializeState(Core.state)
  if not s then error("[" .. stepName .. "] SerializeState returned nil", 2) end
  local out = Comm:DeserializeState("STATE_DATA", s, "EchoPeer")
  if not out then error("[" .. stepName .. "] DeserializeState returned nil", 2) end
  if out.hp ~= Core.state.hp then
    error(("[%s] hp mismatch: got %s, want %s"):format(stepName, tostring(out.hp), tostring(Core.state.hp)), 2)
  end
  if out.maxHp ~= Core.state.maxHp then
    error(("[%s] maxHp mismatch: %s vs %s"):format(stepName, tostring(out.maxHp), tostring(Core.state.maxHp)), 2)
  end
  if out.classKey ~= Core.state.classKey then
    error(("[%s] classKey mismatch: %s vs %s"):format(stepName, tostring(out.classKey), tostring(Core.state.classKey)), 2)
  end
  if out.pet.enabled ~= Core.state.pet.enabled then
    error(("[%s] pet.enabled mismatch"):format(stepName), 2)
  end
  return out
end

T.describe("E2E play session", function()
  T.it("walks through MAGE → SHAMAN → WARLOCK with full combat and recovery", function()
    -- ─── Step 0: cold start ────────────────────────────────────────
    reset()
    T.assertEq(Core.state.hp, 50, "default hp")
    T.assertEq(Core.state.maxHp, 50, "default maxHp")
    T.assertEq(#Core.state.history, 0, "history starts empty")
    T.assertFalse(Core.CanUndo(), "no undo at fresh init")
    T.assertFalse(Core.CanRedo(), "no redo at fresh init")
    roundtripCheck("step0")

    -- ─── Step 1: set up MAGE with full HP and resources ────────────
    Core.SetClassKey("ROGUE")  -- away from default MAGE so the next call triggers idx-2 clamp
    Core.SetClassKey("MAGE")
    Core.SetHP(100, 100)
    Core.SetRes(80, 100)
    Core.SetArmor(8, 2)
    Core.SetDodge(10)
    T.assertEq(Core.state.classKey, "MAGE")
    T.assertEq(Core.state.maxRes2, 8, "MAGE arcane charge max")
    roundtripCheck("step1-mage-setup")

    -- ─── Step 2: take a series of hits exercising all mitigation layers
    Core.SetTempBlock(15)
    Core.SetMagicShield(20, 20, 0)
    Core.SetManaShieldArmor(0); Core.SetManaShieldActive(true)
    -- Dodged hit: dodge=10 ≥ damage=10
    Core.DamageWithArmor(10)
    T.assertEq(Core.state.hp, 100, "dodged hit at threshold")
    -- Big hit: 60 → block 15 → magic 20 → armor 10 → mana 15
    Core.DamageWithArmor(60)
    T.assertEq(Core.state.tempBlock, 0, "block fully consumed")
    T.assertEq(Core.state.magicShield.hp, 0, "magic shield fully consumed")
    T.assertEq(Core.state.res, 65, "mana drained by 15 (80 - 15)")
    T.assertEq(Core.state.hp, 100, "HP intact through full chain")
    -- Verify history records both hits.
    local h1 = Core.state.history[1]
    T.assertEq(h1.kind, "DAMAGE_ARMOR")
    T.assertEq(h1.absorbedBlock, 15)
    T.assertTrue((h1.absorbedMagic or 0) > 0)
    roundtripCheck("step2-combat")

    -- ─── Step 3: heal back through wound cap ──────────────────────
    -- Disable mana shield so the next hit reaches HP cleanly.
    Core.SetManaShieldActive(false)
    Core.DamageTrue(85)  -- mit = trueArmor 2 + tempArmor 0 = 2 → 83 dmg → hp = 17
    T.assertTrue(Core.state.hp <= 25, "hp dropped below 25%")
    T.assertTrue(Core.state.wounds.hit25, "hit25 sticky after low HP")
    Core.Heal(999)  -- wound cap = 50% = 50
    T.assertEq(Core.state.hp, 50, "Heal capped at wound threshold")
    Core.DivineHeal()  -- bypass cap: +75% maxHp
    T.assertEq(Core.state.hp, 100, "DivineHeal bypasses cap, clamped to maxHp")
    roundtripCheck("step3-heal")

    -- ─── Step 4: enable pet + pet combat ──────────────────────────
    Core.SetPetEnabled(true)
    Core.SetPetName("Magma")
    Core.SetPetHP(30, 30)
    Core.SetPetArmor(3, 1)
    Core.SetPetMagicShield(5, 5, 1)  -- pet shield armor 1
    Core.SetPetAuthorityEnabled(true)
    T.assertEq(Core.state.pet.name, "Magma")
    -- Pet authority should appear in resource profile.
    local prof = Shared.GetResProfile(Core.state)
    local hasAuth = false
    for _, p in ipairs(prof) do if p.idx == 5 then hasAuth = true end end
    T.assertTrue(hasAuth, "pet authority slot present")

    -- Pet takes a hit: 12 → shield armor 1 = 11 → shield hp 5 (break) → 6 leaks → pet armor 4 → 2 to HP
    Core.PetDamageWithArmor(12)
    T.assertEq(Core.state.pet.magicShield.hp, 0, "pet shield broken")
    T.assertEq(Core.state.pet.hp, 28, "pet HP after layered absorption")
    -- Pet history entry has subject=PET.
    local petH = Core.state.history[1]
    T.assertEq(petH.subject, "PET")
    roundtripCheck("step4-pet-combat")

    -- ─── Step 5: class transition MAGE → SHAMAN drops mana shield ─
    -- Re-activate mana shield to verify the transition tears it down.
    Core.SetRes(50, 100)
    Core.SetManaShieldActive(true)
    T.assertTrue(Core.state.manaShield.active, "mana shield re-activated for transition test")
    Core.SetClassKey("SHAMAN")
    T.assertFalse(Core.state.manaShield.active, "leaving MAGE drops mana shield")
    -- Set up shaman resources.
    for i = 1, 4 do Core.SetResIndex(i, 5, 20) end
    Core.SetShamanPosture("FEU")
    T.assertEq(Core.state.shamanPosture, "FEU")
    T.assertEq(Core.state.shamanPostureDmgBonus, 10)
    -- FEU adds +10 to incoming damage. 5 damage becomes 15.
    Core.DamageTrue(5)
    -- HP was 100; DamageTrue ignores `armor`. trueArmor=2, tempArmor=0 → mit=2. dmg = 15 - 2 = 13.
    T.assertEq(Core.state.hp, 87, "FEU bonus through trueArmor mitigation")
    roundtripCheck("step5-shaman")

    -- ─── Step 6: class transition SHAMAN(active posture) → WARLOCK
    Core.SetClassKey("WARLOCK")
    T.assertNil(Core.state.shamanPosture, "posture torn down on class change")
    T.assertEq(Core.state.maxRes2, 60, "WARLOCK corruption max")
    Core.SetResIndex(2, 999, 999)  -- corruption capped
    T.assertEq(Core.state.res2, 60)
    roundtripCheck("step6-warlock")

    -- ─── Step 7: undo all the way back through transitions ───────
    local startUndoCount = 0
    while Core.CanUndo() do
      Core.Undo()
      startUndoCount = startUndoCount + 1
      if startUndoCount > 200 then break end  -- safety
    end
    T.assertTrue(startUndoCount > 0, "at least one undo happened")
    -- After fully unwinding, state.classKey should be at its earliest snapshot.
    -- We don't assert exact start because the undoStack cap is 50 — earliest
    -- tracked state may not be the absolute initial. But the state should be
    -- internally consistent.
    T.assertNotNil(Core.state.classKey)
    T.assertTrue(Core.state.hp >= 0 and Core.state.hp <= Core.state.maxHp)

    -- ─── Step 8: redo all the way forward ────────────────────────
    while Core.CanRedo() do Core.Redo() end
    T.assertEq(Core.state.classKey, "WARLOCK", "redo lands back at final class")
    T.assertEq(Core.state.maxRes2, 60)
    T.assertEq(Core.state.res2, 60)
    roundtripCheck("step8-redo-forward")

    -- ─── Step 9: stabilise / death-spiral / surgery revive ───────
    Core.SetHP(0, Core.state.maxHp)
    Core.SetStabilise(true)
    T.assertTrue(Core.state.stabilise)
    Core.DamageTrue(50)  -- damage at hp=0 with stabilise: hp stays 0, stab stays
    T.assertEq(Core.state.hp, 0)
    T.assertEq(Core.state.stabilise, true)
    Core.Surgery()  -- 50% maxHp revive, clears stabilise
    T.assertTrue(Core.state.hp > 0)
    T.assertNil(Core.state.stabilise)
    roundtripCheck("step9-revive")

    -- ─── Step 10: clear history then daily regen sequence ─────────
    Core.ClearHistory()
    T.assertEq(#Core.state.history, 0)
    Core.SetHP(0, Core.state.maxHp)
    Core.DailyRegenHP(); Core.DailyRegenHP(); Core.DailyRegenHP()
    T.assertTrue(Core.state.hp > 0)
    -- Player regen does not log to history.
    T.assertEq(#Core.state.history, 0, "DailyRegenHP does not log history")
    roundtripCheck("step10-regen")

    -- ─── Step 11: full-frame popup echo across the wire ──────────
    -- The peer receives our payload and decodes it; we shadow the popup
    -- module to capture the result.
    _G.MOCKS.sentMessages = {}
    Comm.partialMessages = {}
    Comm:SendStateData("PeerEcho")
    T.assertTrue(#_G.MOCKS.sentMessages >= 1)

    local received
    local realPopup = ns.TargetPopup
    ns.TargetPopup = { OnStateReceived = function(_, _, state) received = state end }
    for _, m in ipairs(_G.MOCKS.sentMessages) do
      Comm:OnChatMsgAddon(m.prefix, m.msg, "WHISPER", "PeerEcho")
    end
    ns.TargetPopup = realPopup

    T.assertNotNil(received, "popup received echoed state")
    T.assertEq(received.classKey, "WARLOCK")
    T.assertEq(received.pet.enabled, true)
    T.assertEq(received.pet.name, "Magma")
    T.assertEq(received.pet.authorityEnabled, true)
    T.assertEq(received.maxRes2, 60)

    -- ─── Step 12: ResetToDefaults clears EVERYTHING ──────────────
    Core.ResetToDefaults()
    T.assertEq(Core.state.hp, 50)
    T.assertEq(Core.state.maxHp, 50)
    T.assertEq(Core.state.classKey, "MAGE")  -- mock UnitClass
    T.assertEq(Core.state.pet.enabled, false)
    T.assertEq(Core.state.pet.name, "Familier")
    T.assertNil(Core.state.shamanPosture)
    T.assertFalse(Core.state.manaShield.active)
    T.assertEq(Core.state.magicShield.hp, 0)
    T.assertEq(#Core.state.history, 0)
    T.assertFalse(Core.CanUndo())
    T.assertFalse(Core.CanRedo())
    roundtripCheck("step12-reset")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- E2E: many-peer Comm scenario (4 peers, multipart + compressed mix)
-- ────────────────────────────────────────────────────────────────────

T.describe("E2E Comm: many peers in flight simultaneously", function()
  T.it("multipart messages from 4 peers reassemble independently", function()
    Core.ResetToDefaults()
    Comm.partialMessages = {}

    -- Build 4 different states; capture each peer's serialized payload.
    local payloads = {}
    for i, classKey in ipairs({ "MAGE", "WARLOCK", "SHAMAN", "ROGUE" }) do
      Core.ResetToDefaults()
      Core.SetClassKey("ROGUE")
      Core.SetClassKey(classKey)
      Core.SetHP(10 + i, 50 + i * 10)
      payloads[i] = {
        sender = "Peer" .. i,
        classKey = classKey,
        hp = 10 + i,
        maxHp = 50 + i * 10,
        bytes = Comm.SerializeState(Core.state),
      }
    end

    -- Helper to chunk a payload into N pieces.
    local function chunks(s, n)
      local out, w = {}, math.ceil(#s / n)
      for i = 1, n do out[i] = s:sub((i - 1) * w + 1, i * w) end
      return out
    end

    -- Interleave parts so each peer's state arrives out-of-order.
    local sequenced = {}
    for i = 1, 4 do
      local p = payloads[i]
      local cks = chunks(p.bytes, 3)
      for j, c in ipairs(cks) do
        sequenced[#sequenced + 1] = { sender = p.sender, total = 3, index = j, data = c }
      end
    end

    -- Shuffle deterministically so this test is stable.
    math.randomseed(7)
    for i = #sequenced, 2, -1 do
      local j = math.random(1, i)
      sequenced[i], sequenced[j] = sequenced[j], sequenced[i]
    end

    -- Replay; the LAST part for any sender returns the decoded state.
    local decoded = {}
    for _, ev in ipairs(sequenced) do
      local r = Comm:DeserializeState("STATE_DATA_PART",
        { total = ev.total, index = ev.index, data = ev.data }, ev.sender)
      if r then decoded[ev.sender] = r end
    end

    -- Every peer's state should have decoded exactly once.
    for i = 1, 4 do
      local d = decoded["Peer" .. i]
      T.assertNotNil(d, "Peer" .. i .. " should have decoded")
      T.assertEq(d.classKey, payloads[i].classKey)
      T.assertEq(d.hp, payloads[i].hp)
      T.assertEq(d.maxHp, payloads[i].maxHp)
    end
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- E2E: TargetPopup cache flow under realistic name traffic
-- ────────────────────────────────────────────────────────────────────

T.describe("E2E Popup: cache flow under traffic", function()
  T.it("cache populates on receive, expires on TTL, evicts under pressure", function()
    local Popup = ns.TargetPopup
    local h = Popup._test
    -- Wipe cache.
    for k in pairs(h.cache) do h.cache[k] = nil end
    _G.MOCKS.fakeNow = 0

    -- Receive states from 5 peers in rapid succession.
    for i = 1, 5 do
      _G.MOCKS.fakeNow = i
      Popup:OnStateReceived("Peer" .. i, { hp = i, maxHp = 10, classKey = "MAGE" })
    end
    for i = 1, 5 do T.assertNotNil(h.getCached("peer" .. i)) end

    -- Advance time past TTL → all entries expire.
    _G.MOCKS.fakeNow = h.CACHE_TTL + 100
    for i = 1, 5 do T.assertNil(h.getCached("peer" .. i)) end

    -- Re-fill above CACHE_MAX; verify oldest entry gets dropped.
    for k in pairs(h.cache) do h.cache[k] = nil end
    for i = 1, h.CACHE_MAX do
      _G.MOCKS.fakeNow = 1000 + i
      h.setCached("k" .. i, { hp = i })
    end
    _G.MOCKS.fakeNow = 9999
    h.setCached("kBeyond", { hp = 0 })
    T.assertNil(h.cache["k1"], "oldest evicted")
    T.assertNotNil(h.cache["kBeyond"])

    -- Cleanup.
    for k in pairs(h.cache) do h.cache[k] = nil end
    _G.MOCKS.fakeNow = nil
  end)
end)
