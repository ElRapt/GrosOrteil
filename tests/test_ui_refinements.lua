-- Real TOC integration: new controls, layout and animation lifecycle.
return function(T, ns, frames)
  local UI, Core = ns.UI, ns.Core
  local function reset()
    Core.ResetToDefaults(); ns.UI_Show(true)
    UI.setSidebarSection(1); UI.setTab(1); frames.layout(); frames.finishAnimations()
  end
  local function floating()
    local result={}
    for _,g in ipairs(frames.animations) do
      local f=g.region
      if g:IsPlaying() and f._kind=="FontString" and f._parent and f._parent._parent==UI.hpBar then
        result[#result+1]=g
      end
    end
    return result
  end
  T.describe("UI refinements", function()
    T.it("insets Legacy header and footer controls inside the decorative border", function()
      reset(); UI.frame:SetSize(760,460); frames.layout()
      local inset=ns.Theme.GetName()=="legacy" and 26 or 8
      T.assertTrue(UI.iconRestoreHP:GetBottom()-UI.frame:GetBottom()>=inset)
      T.assertTrue(UI.themeButton:GetBottom()-UI.frame:GetBottom()>=inset)
      T.assertTrue(UI.crest:GetLeft()-UI.frame:GetLeft()>=inset)
      T.assertTrue(UI.title:GetLeft()>UI.crest:GetRight())
      T.assertTrue(UI.frame:GetTop()-UI.title:GetTop()>=inset)
      T.assertTrue(UI.body:GetBottom()>UI.iconRestoreHP:GetTop())
      T.assertTrue(UI.distanceButton:GetLeft()>UI.themeButton:GetRight())
      T.assertTrue(UI.distanceButton:GetRight()<UI.iconRegenRes:GetLeft())
      UI.frame:SetSize(940,580); frames.layout()
    end)
    T.it("drags from the header without registering drag on the text-editing body", function()
      reset()
      T.assertNil(UI.frame:GetScript("OnDragStart"))
      UI.plaque:RunScript("OnDragStart"); T.assertTrue(UI.frame._moving)
      UI.plaque:RunScript("OnDragStop"); T.assertFalse(UI.frame._moving)
      UI.plaque:RunScript("OnDragStart"); UI.frame:Hide()
      T.assertFalse(UI.frame._moving); ns.UI_Show(true)
    end)
    T.it("places full mystical restoration directly left of HP restoration and handles sheet changes", function()
      reset(); Core.SetClassKey("MAGE")
      Core.SetHP(12,100); Core.SetResIndex(1,0,20); Core.SetResIndex(2,0,8)
      T.assertTrue(UI.iconRestoreResources:GetRight()<UI.iconRestoreHP:GetLeft())
      T.assertTrue(UI.iconRegenHP:GetRight()<UI.iconRestoreResources:GetLeft())
      UI.iconRestoreResources:RunScript("OnClick")
      T.assertEq(Core.state.res,20); T.assertEq(Core.state.res2,8); T.assertEq(Core.state.hp,12)
      Core.SetPetEnabled(true); UI.setSidebarSection(2)
      T.assertFalse(UI.iconRestoreResources:IsShown()); T.assertFalse(UI.iconRegenRes:IsShown())
      local _,relative=UI.iconRegenHP:GetPoint(1); T.assertEq(relative,UI.iconRestoreHP)
      UI.setSidebarSection(1)
      T.assertTrue(UI.iconRestoreResources:IsShown())
      _,relative=UI.iconRegenHP:GetPoint(1); T.assertEq(relative,UI.iconRestoreResources)
    end)
    T.it("expands and collapses player ranged edits without overlapping following actions", function()
      reset(); Core.SetAttaque(20,50)
      if UI.rangedPanel:IsShown() then UI.rangedToggle:RunScript("OnClick") end
      local bottom=UI.ficheAfterRanged:GetTop()
      UI.rangedToggle:RunScript("OnClick"); frames.layout()
      T.assertTrue(UI.rangedPanel:IsShown()); T.assertEq(UI.ficheAfterRanged:GetTop(),bottom-84)
      local edit=UI.rangedPanel.inputs.courte
      edit:SetFocus(); edit:Insert("80"); edit:RunScript("OnEnterPressed")
      T.assertEq(Core.GetRangedAttack(Core.state,"courte"),80)
      T.assertEq(Core.GetRangedAttack(Core.state,"moyenne"),50)
      T.assertEq(UI.rangedPanel.inputs.longue:GetText(),"50")
      local lastRow=UI.rangedPanel.inputs.longue._parent
      T.assertTrue(lastRow:GetBottom()>UI.inputs.actionValue._parent:GetTop())
      UI.rangedToggle:RunScript("OnClick"); frames.layout()
      T.assertFalse(UI.rangedPanel:IsShown()); T.assertEq(UI.ficheAfterRanged:GetTop(),bottom)
      T.assertEq(Core.GetRangedAttack(Core.state,"courte"),80)
    end)
    T.it("edits pet ranges independently and retains values when collapsed", function()
      reset(); Core.SetPetEnabled(true); Core.SetPetAttaque(10,30)
      UI.setSidebarSection(2); UI.setTab(9)
      if UI.petRangedPanel:IsShown() then UI.petRangedToggle:RunScript("OnClick") end
      UI.petRangedToggle:RunScript("OnClick"); frames.layout()
      local edit=UI.petRangedPanel.inputs.longue
      edit:SetFocus(); edit:Insert("15"); edit:RunScript("OnEnterPressed")
      T.assertEq(Core.GetRangedAttack(Core.state.pet,"longue"),15)
      T.assertEq(Core.GetRangedAttack(Core.state.pet,"courte"),30)
      T.assertNil(Core.state.attaqueDistanceLongue)
      UI.petRangedToggle:RunScript("OnClick")
      T.assertFalse(UI.petRangedPanel:IsShown())
      T.assertEq(Core.GetRangedAttack(Core.state.pet,"longue"),15)
      UI.setSidebarSection(1); UI.setTab(1)
    end)
    T.it("preserves Auto on untouched range blur but commits an explicitly retyped value", function()
      reset(); Core.SetAttaque(20,40); Core.SetPetEnabled(true); Core.SetPetAttaque(10,30)
      for _, sheet in ipairs({{UI.rangedPanel, false, 40}, {UI.petRangedPanel, true, 30}}) do
        UI.setSidebarSection(sheet[2] and 2 or 1); UI.setTab(sheet[2] and 9 or 1)
        sheet[1]:Show()
        local edit = sheet[1].inputs.courte
        local target = sheet[2] and Core.state.pet or Core.state
        local rev = Core.state.rev
        edit:SetFocus(); edit:ClearFocus()
        T.assertNil(target.attaqueDistanceCourte); T.assertEq(Core.state.rev, rev)
        edit:SetFocus(); edit:Insert(tostring(sheet[3])); edit:RunScript("OnEnterPressed")
        T.assertEq(target.attaqueDistanceCourte, sheet[3]); T.assertEq(Core.state.rev, rev + 1)
        Core.Undo()
        target = sheet[2] and Core.state.pet or Core.state
        T.assertNil(target.attaqueDistanceCourte)
        Core.Redo()
        target = sheet[2] and Core.state.pet or Core.state
        T.assertEq(target.attaqueDistanceCourte, sheet[3])
      end
      UI.setSidebarSection(1); UI.setTab(1)
    end)
    T.it("keeps focused range drafts through bonus expiry and refreshes untouched values on blur", function()
      for _, isPet in ipairs({false, true}) do
        reset(); Core.SetAttaque(20,40); Core.SetPetEnabled(true); Core.SetPetAttaque(10,40)
        UI.setSidebarSection(isPet and 2 or 1); UI.setTab(isPet and 9 or 1)
        local panel = isPet and UI.petRangedPanel or UI.rangedPanel
        panel:Show()
        local toggle = isPet and Core.TogglePetAffix or Core.ToggleAffix
        local target = isPet and Core.state.pet or Core.state
        local edit = panel.inputs.courte
        toggle("ELIXIR_PUISSANCE")
        edit:SetFocus()
        Core.NextTurn(); Core.NextTurn(); Core.NextTurn()
        T.assertEq(edit:GetText(), "70")
        local rev = Core.state.rev
        edit:ClearFocus()
        T.assertNil(target.attaqueDistanceCourte); T.assertEq(Core.state.rev, rev)
        T.assertEq(edit:GetText(), "40")
        toggle("ELIXIR_PUISSANCE")
        edit:SetFocus(); edit:Insert("85")
        Core.NextTurn(); Core.NextTurn(); Core.NextTurn()
        T.assertEq(edit:GetText(), "85")
        edit:RunScript("OnEnterPressed")
        T.assertEq(Core.GetRangedAttack(target, "courte"), 85)
        T.assertEq(target.attaqueDistanceCourte, 85) -- bonuses at commit time
        toggle("ELIXIR_PUISSANCE")
        T.assertEq(edit:GetText(), "115")
      end
      UI.setSidebarSection(1); UI.setTab(1)
    end)
    T.it("Auto discards a focused range draft and remains inherited after reload", function()
      for _, isPet in ipairs({false, true}) do
        reset(); Core.SetAttaque(20,40); Core.SetPetEnabled(true); Core.SetPetAttaque(10,40)
        UI.setSidebarSection(isPet and 2 or 1); UI.setTab(isPet and 9 or 1)
        local panel = isPet and UI.petRangedPanel or UI.rangedPanel
        panel:Show()
        local edit, auto = panel.inputs.courte
        for _, f in ipairs(frames.frames) do
          if f._kind == "Button" and f._parent == panel and f:GetText() == "Auto" then auto = f; break end
        end
        Core.SetRangedAttack("courte", 65, isPet)
        edit:SetFocus(); edit:Insert("90")
        local rev = Core.state.rev
        assert(auto):RunScript("OnClick")
        T.assertFalse(edit:HasFocus()); T.assertEq(Core.state.rev, rev + 1)
        local target = isPet and Core.state.pet or Core.state
        T.assertNil(target.attaqueDistanceCourte); T.assertEq(edit:GetText(), "40")
        panel:Hide(); panel:Show(); ns.Core_Init()
        target = isPet and Core.state.pet or Core.state
        T.assertNil(target.attaqueDistanceCourte)
        if isPet then Core.SetPetAttaque(10,50) else Core.SetAttaque(20,50) end
        T.assertEq(edit:GetText(), "50")
        edit:SetFocus(); edit:Insert("invalid"); rev = Core.state.rev; edit:ClearFocus()
        T.assertEq(Core.state.rev, rev); T.assertNil(target.attaqueDistanceCourte)
        T.assertEq(edit:GetText(), "50")
      end
      UI.setSidebarSection(1); UI.setTab(1)
    end)
    T.it("expands target ranges, moves health below them and collapses on reopen", function()
      reset(); Core.SetAttaque(20,50); Core.SetRangedAttack("courte",70)
      local mocks=require("mocks")
      mocks.units={player={name="TestPlayer",realm="TestRealm",guid="Player-1-1",isPlayer=true},
        target={name="TargetPlayer",realm="TestRealm",guid="Player-1-2",isPlayer=true}}
      ns.TargetPopup.InjectState("TargetPlayer-TestRealm",Core.state); ns.TargetPopup:OnTargetChanged()
      local popup=_G.GrosOrteilTargetPopup
      T.assertFalse(popup.rangedPanel:IsShown())
      local height,healthOffset=popup:GetHeight(),popup:GetTop()-popup.hpRow.holder:GetTop()
      popup.rangedToggle:RunScript("OnClick"); frames.layout()
      T.assertTrue(popup.rangedPanel:IsShown()); T.assertEq(popup:GetHeight(),height+66)
      T.assertEq(popup:GetTop()-popup.hpRow.holder:GetTop(),healthOffset+66)
      T.assertTrue(popup.rangedLines[1]:GetText():find(": 70",1,true)~=nil)
      T.assertTrue(popup.rangedLines[3]:GetText():find(": 50",1,true)~=nil)
      T.assertTrue(popup.rangedPanel:GetBottom()>popup.hpRow.holder:GetTop())
      popup:Hide(); ns.TargetPopup:OnTargetChanged()
      T.assertFalse(popup.rangedPanel:IsShown()); T.assertEq(popup:GetHeight(),height)
      popup:Hide(); mocks.units=nil
    end)
    T.it("animates actual percentage losses and healing above the matching HP bar", function()
      reset(); Core.SetHP(70,100)
      UI.inputs.actionValue:SetText("-15")
      Core.PercentageHeal(-15)
      local effects=floating(); T.assertEq(#effects,1)
      T.assertEq(effects[1].region:GetText(),"-15")
      T.assertTrue(effects[1].region._textColor[1]>effects[1].region._textColor[2])
      T.assertTrue(effects[1].region:GetBottom()>UI.hpBar:GetTop())
      frames.finishAnimations(); Core.PercentageHeal(100)
      effects=floating(); T.assertEq(#effects,1); T.assertEq(effects[1].region:GetText(),"+45")
      T.assertTrue(effects[1].region._textColor[2]>effects[1].region._textColor[1])
      frames.finishAnimations(); Core.PercentageHeal(15); T.assertEq(#floating(),0)
      Core.SetPetEnabled(true); Core.SetPetHP(40,100)
      Core.PetPercentageHeal(15); T.assertEq(#floating(),0) -- player sheet is showing
      UI.setSidebarSection(2); UI.setTab(9); Core.PetPercentageHeal(-15)
      effects=floating(); T.assertEq(#effects,1); T.assertEq(effects[1].region:GetText(),"-15")
      UI.frame:Hide(); T.assertFalse(effects[1]:IsPlaying()); T.assertFalse(effects[1].region:IsShown())
      ns.UI_Show(true); T.assertEq(#floating(),0)
      UI.setSidebarSection(1); UI.setTab(1)
    end)
    T.it("opens the distance tool from its button and slash command with no hidden polling", function()
      reset(); UI.distanceButton:RunScript("OnClick")
      local frame=ns.Distance.frame
      T.assertTrue(frame:IsShown()); T.assertNotNil(frame:GetScript("OnUpdate"))
      frame.modeButtons.origin:RunScript("OnClick"); T.assertEq(ns.Distance.mode,"origin")
      T.assertEq(frame.result.reason,"no_origin")
      frames.combat=true; frame:RunScript("OnUpdate",0.3)
      T.assertEq(frame.result.reason,"combat")
      T.assertEq(frame.value:GetText(),"Indisponible")
      frames.combat=false; frame.modeButtons.target:RunScript("OnClick")
      frame:Hide(); T.assertNil(frame:GetScript("OnUpdate"))
      SlashCmdList.GROSORTEIL("distance"); T.assertTrue(frame:IsShown())
      SlashCmdList.GROSORTEIL("distance"); T.assertFalse(frame:IsShown())
      T.assertNil(frame:GetScript("OnUpdate"))
    end)
  end)
end
