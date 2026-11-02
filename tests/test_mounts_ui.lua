return function(ns, frames, mocks, T)
  local Core, UI, Mounts = ns.Core, ns.UI, ns.Mounts
  local riding
  local function setup()
    riding = nil
    _G.IsMounted = function() return riding ~= nil end
    _G.C_MountJournal = {
      GetMountIDs = function() return {101,202} end,
      GetMountInfoByID = function(id) return "Monture " .. id, id, 1, riding == id end,
    }
    Core.ResetToDefaults()
    UI.setSidebarSection(2); UI.setTab(UI.TAB_IDS.MOUNTS)
  end
  local function mount(id)
    riding = id
    frames.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
  end
  local function flush()
    local pending = frames.timers or {}; frames.timers = {}
    for _,fn in ipairs(pending) do fn() end
  end
  T.describe("Mount UI and TRP tooltips", function()
    T.it("edits mounts, routes footer actions and shares pet health through the real controls", function()
      setup(); mount(101)
      T.assertTrue(UI.pages[UI.TAB_IDS.MOUNTS]:IsShown())
      T.assertEq(UI.title:GetText(),"Monture 101")
      local function edit(key, value)
        local input=UI.mountInputs[key]
        input:SetFocus(); input:SetText(tostring(value)); input:RunScript("OnEnterPressed")
      end
      edit("maxHp",100); edit("hp",80); edit("armor",5); edit("dodge",10)
      UI.mountInputs.value:SetText("20"); UI.mountActionButtons[1]:RunScript("OnClick")
      T.assertEq(Mounts.GetSelected().hp,65)
      UI.iconRegenHP:RunScript("OnClick"); T.assertEq(Mounts.GetSelected().hp,75)
      UI.iconRestoreHP:RunScript("OnClick"); T.assertEq(Mounts.GetSelected().hp,100)
      Core.SetPetEnabled(true); Core.SetPetHP(30,40)
      UI.mountPetToggle:RunScript("OnClick")
      T.assertEq(UI.mountInputs.hp:GetText(),"30")
      edit("hp",25); T.assertEq(Core.state.pet.hp,25)
      UI.setTab(UI.TAB_IDS.PET_MAIN); T.assertEq(UI.inputs.petHpCur:GetText(),"25")
      UI.setTab(UI.TAB_IDS.MOUNTS)
      mount(202); T.assertEq(UI.mountInputs.hp:GetText(),"20")
      UI.mountPrevious:RunScript("OnClick"); T.assertEq(UI.mountInputs.hp:GetText(),"25")
      UI.mountCurrent:RunScript("OnClick"); T.assertEq(Mounts.GetSelectedID(),202)
      UI.mountInputs.armor:SetFocus(); UI.mountInputs.armor:SetText("13")
      mount(101)
      T.assertEq(Core.state.mounts[202].armor,13)
      T.assertEq(UI.mountInputs.armor:GetText(),tostring(Core.state.pet.armor))
      mount(nil); T.assertFalse(UI.mountCurrent:IsEnabled())
      UI.setSidebarSection(1)
      T.assertEq(#mocks.errorHandlerCalls,0)
    end)
    T.it("keeps the fifth affix and turn controls separate and applies pet regeneration",function()
      setup(); Core.SetPetEnabled(true); Core.SetPetHP(10,20)
      UI.setTab(UI.TAB_IDS.PET_AFFIXES)
      UI.petAffixButtons[3]:RunScript("OnClick")
      T.assertEq(Core.state.pet.regenParTour,2)
      UI.setTab(UI.TAB_IDS.PET_MAIN); UI.petRegenButton:RunScript("OnClick")
      T.assertEq(Core.state.pet.hp,12)
      frames.layout()
      T.assertTrue(UI.petAffixButtons[5]:GetBottom()>UI.petAffixNextTurnButton:GetTop())
      mount(nil); UI.setSidebarSection(1)
    end)
    T.it("stacks mount stats above the matching TRP mount profile and handles hide/dismount/fallback",function()
      setup()
      mocks.units={player={name="TestPlayer",realm="TestRealm",isPlayer=true},mouseover={name="Rider",realm="TestRealm",isPlayer=true}}
      local charTip = CreateFrame("Frame","TRP3_CharacterTooltip",UIParent)
      charTip:SetSize(220,140); charTip:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",300,200)
      local mountTip = CreateFrame("Frame","TRP3_CompanionTooltip",UIParent)
      mountTip:SetSize(220,80); mountTip:SetPoint("BOTTOMLEFT",charTip,"TOPLEFT",0,0)
      charTip:Hide(); mountTip:Hide()
      charTip.target="Rider-TestRealm"; mountTip.target="Rider-TestRealm"
      frames.fire("ADDON_LOADED","totalRP3")
      local state={hp=50,maxHp=50,classKey="MAGE",mounted=true,dodge=30,
        mount={name="Cheval",hp=30,maxHp=40,armor=5,dodge=8},pet={enabled=false}}
      ns.TargetPopup:OnStateReceived("Rider-TestRealm",state)
      charTip:Show(); mountTip:Show(); flush()
      local popup=_G.GrosOrteilMountHoverPopup
      T.assertTrue(popup:IsShown()); T.assertEq(popup.hp.bar:GetValue(),30)
      local _,anchor=popup:GetPoint(1); T.assertEq(anchor,mountTip)
      local _,ownerAnchor,point=_G.GrosOrteilHoverPopup:GetPoint(1)
      T.assertEq(ownerAnchor,charTip); T.assertEq(point,"BOTTOMRIGHT")
      frames.layout(); T.assertTrue(popup:GetBottom()>mountTip:GetTop())
      -- An unrelated companion profile must never anchor this rider's stats.
      mountTip.target="Other-TestRealm"; ns.TargetPopup:OnStateReceived("Rider-TestRealm",state)
      _,anchor=popup:GetPoint(1); T.assertEq(anchor,_G.GrosOrteilHoverPopup)
      mountTip.target="Rider-TestRealm"
      mountTip:Hide(); flush()
      _,anchor=popup:GetPoint(1); T.assertEq(anchor,_G.GrosOrteilHoverPopup)
      state.mounted=false; ns.TargetPopup:OnStateReceived("Rider-TestRealm",state)
      T.assertFalse(popup:IsShown())
      state.mounted=true; ns.TargetPopup:OnStateReceived("Rider-TestRealm",state)
      T.assertTrue(popup:IsShown())
      ns.GetDB().settings.popupOnTarget=false
      ns.TargetPopup:OnStateReceived("Rider-TestRealm",state); T.assertFalse(popup:IsShown())
      ns.GetDB().settings.popupOnTarget=true
      mocks.units={player={name="TestPlayer",realm="TestRealm",isPlayer=true}}
      GameTooltip:Hide(); charTip:Hide(); mountTip:Hide(); flush(); frames.finishAnimations()
      T.assertFalse(popup:IsShown()); T.assertFalse(_G.GrosOrteilHoverPopup:IsShown())
      mocks.units=nil; UI.setSidebarSection(1)
      T.assertEq(#mocks.errorHandlerCalls,0)
    end)
  end)
end
