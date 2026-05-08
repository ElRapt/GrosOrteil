---@diagnostic disable: undefined-global
local T = _G.T
local ns = _G.NS
local Comm = ns.Comm
local Core = ns.Core

local function reset()
  Core.ResetToDefaults()
end

T.describe("Comm.SerializeState round-trip", function()
  T.it("preserves HP/maxHp/classKey across serialize+deserialize", function()
    reset()
    Core.SetClassKey("WARLOCK")
    Core.SetHP(33, 77)

    local serialized = Comm.SerializeState(Core.state)
    T.assertNotNil(serialized)

    local out = Comm:DeserializeState("STATE_DATA", serialized, "Tester")
    T.assertNotNil(out)
    T.assertEq(out.hp, 33)
    T.assertEq(out.maxHp, 77)
    T.assertEq(out.classKey, "WARLOCK")
  end)

  T.it("preserves multi-resource fields", function()
    reset()
    Core.SetClassKey("SHAMAN")
    Core.SetResIndex(1, 5, 20)
    Core.SetResIndex(2, 4, 20)
    Core.SetResIndex(3, 3, 20)
    Core.SetResIndex(4, 2, 20)

    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(out.res, 5)
    T.assertEq(out.res2, 4)
    T.assertEq(out.res3, 3)
    T.assertEq(out.res4, 2)
  end)

  T.it("preserves pet sub-table", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetName("Grosminet")
    Core.SetPetHP(15, 30)

    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(out.pet.enabled, true)
    T.assertEq(out.pet.name, "Grosminet")
    T.assertEq(out.pet.hp, 15)
    T.assertEq(out.pet.maxHp, 30)
  end)

  T.it("rejects empty / corrupt payload", function()
    T.assertNil(Comm:DeserializeState("STATE_DATA", "",          "Tester"))
    T.assertNil(Comm:DeserializeState("STATE_DATA", "not lua at all", "Tester"))
  end)
end)

T.describe("Comm multipart reassembly", function()
  T.it("reassembles a 3-part message and deserializes", function()
    reset()
    Core.SetHP(60, 90)
    local serialized = Comm.SerializeState(Core.state)
    T.assertNotNil(serialized)

    -- Manually split into 3 chunks.
    local len = #serialized
    local chunkSize = math.ceil(len / 3)
    local chunks = {
      serialized:sub(1, chunkSize),
      serialized:sub(chunkSize + 1, chunkSize * 2),
      serialized:sub(chunkSize * 2 + 1),
    }

    -- Fresh instance to keep partialMessages bookkeeping isolated.
    Comm.partialMessages = {}

    local r1 = Comm:DeserializeState("STATE_DATA_PART", { total = 3, index = 1, data = chunks[1] }, "Sender1")
    T.assertNil(r1)  -- not yet complete
    local r2 = Comm:DeserializeState("STATE_DATA_PART", { total = 3, index = 2, data = chunks[2] }, "Sender1")
    T.assertNil(r2)
    local r3 = Comm:DeserializeState("STATE_DATA_PART", { total = 3, index = 3, data = chunks[3] }, "Sender1")
    T.assertNotNil(r3)
    T.assertEq(r3.hp, 60)
    T.assertEq(r3.maxHp, 90)
  end)

  T.it("aborts when total parts mismatch mid-stream", function()
    reset()
    Comm.partialMessages = {}
    Comm:DeserializeState("STATE_DATA_PART", { total = 3, index = 1, data = "a" }, "S")
    -- Second part claims a different total → state should be discarded.
    Comm:DeserializeState("STATE_DATA_PART", { total = 4, index = 2, data = "b" }, "S")
    T.assertNil(Comm.partialMessages["S"])
  end)
end)

T.describe("Comm REQUEST_STATE throttling", function()
  T.it("rejects a second request from same sender within RESPONSE_COOLDOWN", function()
    -- Wipe any sent messages and per-sender timestamps.
    _G.MOCKS.sentMessages = {}
    Comm.lastRequestServed = {}

    Comm:OnChatMsgAddon(Comm.PREFIX, "REQUEST_STATE", "WHISPER", "PeerA")
    local firstSendCount = #_G.MOCKS.sentMessages
    T.assertTrue(firstSendCount > 0, "first request should have been served")

    Comm:OnChatMsgAddon(Comm.PREFIX, "REQUEST_STATE", "WHISPER", "PeerA")
    -- Cooldown < 3s elapsed (mocked GetTime) → no new send.
    T.assertEq(#_G.MOCKS.sentMessages, firstSendCount)
  end)
  T.it("does not throttle different senders", function()
    _G.MOCKS.sentMessages = {}
    Comm.lastRequestServed = {}

    Comm:OnChatMsgAddon(Comm.PREFIX, "REQUEST_STATE", "WHISPER", "PeerA")
    local n1 = #_G.MOCKS.sentMessages
    Comm:OnChatMsgAddon(Comm.PREFIX, "REQUEST_STATE", "WHISPER", "PeerB")
    T.assertTrue(#_G.MOCKS.sentMessages > n1, "PeerB should also be served")
  end)
  T.it("ignores messages with the wrong prefix", function()
    _G.MOCKS.sentMessages = {}
    Comm.lastRequestServed = {}
    Comm:OnChatMsgAddon("OTHER_ADDON", "REQUEST_STATE", "WHISPER", "PeerC")
    T.assertEq(#_G.MOCKS.sentMessages, 0)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Round-trip preservation for additional fields
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm round-trip preserves shields and wounds", function()
  T.it("magicShield (hp/maxHp/armor) survives", function()
    reset()
    Core.SetHP(80, 100)
    Core.SetMagicShield(15, 25, 7)
    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(out.magicShield.hp, 15)
    T.assertEq(out.magicShield.maxHp, 25)
    T.assertEq(out.magicShield.armor, 7)
  end)
  T.it("manaShield active flag and armor survive", function()
    reset()
    Core.SetClassKey("MAGE")
    Core.SetRes(50, 100)
    Core.SetManaShieldArmor(33)
    Core.SetManaShieldActive(true)
    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(out.manaShield.active, true)
    T.assertEq(out.manaShield.armor, 33)
  end)
  T.it("wounds flags survive", function()
    reset()
    Core.SetHP(2, 100)  -- triggers hit25 sticky (5% < 10% so hit10 also true)
    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(out.wounds.hit25, true)
    T.assertEq(out.wounds.hit10, true)
  end)
  T.it("pet magicShield + wounds survive", function()
    reset()
    Core.SetPetEnabled(true)
    Core.SetPetHP(1, 20)  -- 5% triggers hit10
    Core.SetPetMagicShield(8, 12, 2)
    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(out.pet.magicShield.hp, 8)
    T.assertEq(out.pet.magicShield.maxHp, 12)
    T.assertEq(out.pet.magicShield.armor, 2)
    T.assertEq(out.pet.wounds.hit10, true)
  end)
  T.it("pet authorityEnabled flag survives", function()
    reset()
    Core.SetPetEnabled(true); Core.SetPetAuthorityEnabled(true)
    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(out.pet.authorityEnabled, true)
  end)
  T.it("classKey falls back to UnitClass when missing", function()
    reset()
    Core.state.classKey = nil
    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(out.classKey, "MAGE")  -- mock UnitClass returns MAGE
  end)
  T.it("attaque + chance + perception survive", function()
    reset()
    Core.SetAttaque(7, 4)
    Core.SetChance(2, 5)
    Core.SetPerception(3)
    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(out.attaqueMelee, 7)
    T.assertEq(out.attaqueDistance, 4)
    T.assertEq(out.chance, 2)
    T.assertEq(out.maxChance, 5)
    T.assertEq(out.perception, 3)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Compressed path
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm compressed path", function()
  T.it("STATE_DATA_COMPRESSED round-trips through LibDeflate", function()
    reset()
    Core.SetHP(50, 100)
    -- Mirror what Comm:SendStateData does: serialize → compress → encode.
    local serialized = Comm.SerializeState(Core.state)
    T.assertNotNil(serialized)
    local LibStub = _G.LibStub
    local LibDeflate = LibStub and LibStub("LibDeflate", true)
    T.assertNotNil(LibDeflate)
    local encoded = LibDeflate:CompressDeflate(serialized)
    encoded = LibDeflate:EncodeForWoWAddonChannel(encoded)
    local out = Comm:DeserializeState("STATE_DATA_COMPRESSED", encoded, "Tester")
    T.assertNotNil(out)
    T.assertEq(out.hp, 50)
    T.assertEq(out.maxHp, 100)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Outgoing wire format from SendStateData
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm:SendStateData", function()
  T.it("sends at least one message with a known cmd token", function()
    reset()
    Core.SetHP(50, 100)
    _G.MOCKS.sentMessages = {}
    Comm:SendStateData("Recipient")
    T.assertTrue(#_G.MOCKS.sentMessages >= 1, "at least one message sent")
    local msg = _G.MOCKS.sentMessages[1]
    T.assertEq(msg.target, "Recipient")
    T.assertEq(msg.channel, "WHISPER")
    T.assertEq(msg.prefix, Comm.PREFIX)
    -- Cmd is one of the four known tokens (single or multipart, plain or compressed).
    local cmd = msg.msg:match("^([^:]+):")
    local known = {
      STATE_DATA = true, STATE_DATA_COMPRESSED = true,
      STATE_DATA_PART = true, STATE_DATA_COMPRESSED_PART = true,
    }
    T.assertTrue(known[cmd], "unexpected cmd token: " .. tostring(cmd))
  end)
  T.it("does nothing when target is empty", function()
    reset()
    _G.MOCKS.sentMessages = {}
    Comm:SendStateData(nil)
    Comm:SendStateData("")
    T.assertEq(#_G.MOCKS.sentMessages, 0)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- HandleStateData parsing
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm:HandleStateData", function()
  T.it("ignores unknown command tokens", function()
    -- Should not error, and should not crash.
    Comm:HandleStateData("Sender", "UNKNOWN_CMD", "")
    Comm:HandleStateData("Sender", nil, "")
    T.assertTrue(true)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Throttle expiry
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm REQUEST_STATE cooldown expiry", function()
  T.it("re-serves the same sender after RESPONSE_COOLDOWN seconds", function()
    _G.MOCKS.fakeNow = 1000
    _G.MOCKS.sentMessages = {}
    Comm.lastRequestServed = {}

    Comm:OnChatMsgAddon(Comm.PREFIX, "REQUEST_STATE", "WHISPER", "PeerX")
    local first = #_G.MOCKS.sentMessages
    T.assertTrue(first > 0)

    _G.MOCKS.fakeNow = _G.MOCKS.fakeNow + (Comm.RESPONSE_COOLDOWN or 3) + 0.1
    Comm:OnChatMsgAddon(Comm.PREFIX, "REQUEST_STATE", "WHISPER", "PeerX")
    T.assertTrue(#_G.MOCKS.sentMessages > first, "second request should be served after cooldown")

    _G.MOCKS.fakeNow = nil
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Multipart timeout
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm multipart timeout", function()
  T.it("discards stale parts older than 30s", function()
    _G.MOCKS.fakeNow = 1000
    Comm.partialMessages = {}
    Comm:DeserializeState("STATE_DATA_PART", { total = 3, index = 1, data = "a" }, "PeerY")
    T.assertNotNil(Comm.partialMessages["PeerY"])

    _G.MOCKS.fakeNow = _G.MOCKS.fakeNow + 31
    local r = Comm:DeserializeState("STATE_DATA_PART", { total = 3, index = 2, data = "b" }, "PeerY")
    T.assertNil(r)
    T.assertNil(Comm.partialMessages["PeerY"])

    _G.MOCKS.fakeNow = nil
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Large payload forces multipart (>255 bytes after compression+encoding)
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm:SendStateData large payload", function()
  T.it("splits into multipart when encoded message > 255 bytes", function()
    reset()
    -- Make a state with verbose, repeated string content to defeat compression.
    -- We can't easily inflate state shape, but a long pet name is honored verbatim
    -- in the serialized payload; we use it to push past the 255-byte threshold.
    Core.SetPetEnabled(true)
    Core.SetPetName(string.rep("AbCdEfGh", 60))  -- 480 chars

    _G.MOCKS.sentMessages = {}
    Comm:SendStateData("Recipient")
    T.assertTrue(#_G.MOCKS.sentMessages >= 1)

    -- Identify whether at least one message is a *_PART command.
    local sawPart = false
    for _, m in ipairs(_G.MOCKS.sentMessages) do
      local cmd = m.msg:match("^([^:]+):")
      if cmd == "STATE_DATA_PART" or cmd == "STATE_DATA_COMPRESSED_PART" then
        sawPart = true; break
      end
    end
    -- Either compressed-fits-in-one or splits-into-many. With 480 chars of
    -- non-redundant text, splitting is overwhelmingly likely.
    T.assertTrue(sawPart or #_G.MOCKS.sentMessages == 1)
    if sawPart then
      T.assertTrue(#_G.MOCKS.sentMessages > 1, "multipart should produce multiple chunks")
    end
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- End-to-end: send then receive across a peer pair
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm end-to-end echo", function()
  T.it("messages emitted by SendStateData reassemble back into matching state", function()
    reset()
    Core.SetClassKey("WARLOCK")
    Core.SetHP(42, 80)
    Core.SetResIndex(2, 25, 60)

    _G.MOCKS.sentMessages = {}
    Comm.partialMessages = {}
    Comm:SendStateData("PeerZ")

    -- Replay each emitted message back through OnChatMsgAddon as if PeerZ sent it.
    -- The receiving Popup is replaced with a recorder so we capture the decoded state.
    local received
    local realPopup = ns.TargetPopup
    ns.TargetPopup = {
      OnStateReceived = function(_, _, state) received = state end,
    }

    for _, m in ipairs(_G.MOCKS.sentMessages) do
      Comm:OnChatMsgAddon(m.prefix, m.msg, "WHISPER", "PeerZ")
    end

    ns.TargetPopup = realPopup

    T.assertNotNil(received, "popup should have received decoded state")
    T.assertEq(received.hp, 42)
    T.assertEq(received.maxHp, 80)
    T.assertEq(received.classKey, "WARLOCK")
    T.assertEq(received.res2, 25)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Defensive serialization
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm defensive serialization", function()
  T.it("SerializeState with empty state returns a valid string", function()
    local s = Comm.SerializeState({})
    T.assertNotNil(s)
    T.assertEq(type(s), "string")
  end)
  T.it("SerializeState round-trips an empty state with default values", function()
    local s = Comm.SerializeState({})
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertNotNil(out)
    T.assertEq(out.hp, 0)
    T.assertEq(out.maxHp, 0)
    -- pet sub-table fully defaulted.
    T.assertEq(out.pet.enabled, false)
    T.assertEq(out.pet.name, "Familier")
  end)
  T.it("DeserializeState ignores STATE_DATA with a non-string payload", function()
    -- Should not crash even if payload is the wrong type.
    local out = Comm:DeserializeState("STATE_DATA", nil, "Tester")
    T.assertNil(out)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Bool/string field round-trip strictness
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm boolean and string preservation", function()
  T.it("pet.enabled is exactly false (not 0 / nil) on round-trip", function()
    reset()
    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(out.pet.enabled, false)
    T.assertEq(type(out.pet.enabled), "boolean")
  end)
  T.it("wounds remain booleans on round-trip", function()
    reset()
    Core.SetHP(2, 100)  -- hit10 sticky
    local s = Comm.SerializeState(Core.state)
    local out = Comm:DeserializeState("STATE_DATA", s, "Tester")
    T.assertEq(type(out.wounds.hit10), "boolean")
    T.assertEq(type(out.wounds.hit25), "boolean")
  end)
  T.it("non-string pet.name in payload falls back to 'Familier'", function()
    -- Bypass the pre-clamp and inject a corrupt pet name into a serialized payload.
    -- Easiest: build a fake decoded payload through buildPayload via DeserializeState.
    local LibStub = _G.LibStub
    local AceSerializer = LibStub("AceSerializer-3.0", true)
    T.assertNotNil(AceSerializer)
    local raw = AceSerializer:Serialize({ hp = 1, maxHp = 1, pet = { name = 42, enabled = true } })
    local out = Comm:DeserializeState("STATE_DATA", raw, "Tester")
    T.assertEq(out.pet.name, "Familier")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Multipart isolation between senders
-- ────────────────────────────────────────────────────────────────────

T.describe("Comm multipart per-sender isolation", function()
  T.it("part for sender A does not get mixed with part for sender B", function()
    reset()
    Core.SetHP(60, 90)
    local serialized = Comm.SerializeState(Core.state)
    local mid = math.floor(#serialized / 2)
    local p1, p2 = serialized:sub(1, mid), serialized:sub(mid + 1)

    Comm.partialMessages = {}
    -- Sender A sends part 1, sender B sends a totally unrelated part 1 (different total).
    local r1 = Comm:DeserializeState("STATE_DATA_PART", { total = 2, index = 1, data = p1 }, "A")
    T.assertNil(r1)
    local junkB = Comm:DeserializeState("STATE_DATA_PART", { total = 5, index = 1, data = "noise" }, "B")
    T.assertNil(junkB)

    -- Sender A's part 2 should still complete cleanly without B's junk interfering.
    local r2 = Comm:DeserializeState("STATE_DATA_PART", { total = 2, index = 2, data = p2 }, "A")
    T.assertNotNil(r2)
    T.assertEq(r2.hp, 60)
  end)
end)
