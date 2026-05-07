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
