-- Integration checks for field ownership, visible rendering and button states.
return function(T, ns, frames)
  local UI, Core, Grimoire, Theme = ns.UI, ns.Core, ns.Grimoire, ns.Theme
  local function button(text)
    for _, f in ipairs(frames.frames) do
      if f._kind == "Button" and f:IsVisible() and f:GetText() == text then return f end
    end
    error("button missing: " .. text)
  end
  local function reset()
    ns.UI_Show(true); UI.setSidebarSection(1); UI.setTab(7)
    if UI.grimoireEditorOpen then button("Annuler"):RunScript("OnClick") end
    Core.ResetToDefaults(); UI.setTab(1)
  end
  local function commit(edit, value)
    Core.BreakUndoCoalesce() -- Separate user interactions occur on separate frames.
    edit:SetFocus(); edit:HighlightText(); edit:Insert(tostring(value)); edit:RunScript("OnEnterPressed")
  end
  local function assertColor(actual, r, g, b, a)
    for i, v in ipairs({r, g, b, a}) do T.assertEq(actual[i], v) end
  end

  T.describe("Field ownership and visible rendering", function()
    T.it("pet edits notify once, preserve fractional siblings, and undo independently", function()
      local fields = {
        {"petName", "name", "Compagnon"}, {"petHpCur", "hp", 50.5}, {"petHpMax", "maxHp", 100.5},
        {"petArmor", "armor", 7.5}, {"petTrueArmor", "trueArmor", 3.5}, {"petDodge", "dodge", 2.5},
        {"petAttaqueMelee", "attaqueMelee", 6.5}, {"petAttaqueDistance", "attaqueDistance", 9.5},
        {"petTempArmor", "tempArmor", 1.5}, {"petMsHp", "hp", 12.5, true},
        {"petMsMaxHp", "maxHp", 20.5, true}, {"petMsArmor", "armor", 4.5, true},
      }
      for index, edited in ipairs(fields) do
        reset(); Core.SetPetEnabled(true); Core.SetPetName("Compagnon"); Core.SetPetHP(50.5,100.5)
        Core.SetPetArmor(7.5,3.5); Core.SetPetDodge(2.5); Core.SetPetAttaque(6.5,9.5)
        Core.SetPetTempArmor(1.5); Core.SetPetMagicShield(12.5,20.5,4.5)
        UI.setSidebarSection(2); UI.setTab(9)
        local value = index == 1 and "Fauve" or edited[3] + 1.5
        local rev, notifications = Core.state.rev, 0
        local unsubscribe = Core.OnChange(function() notifications = notifications + 1 end)
        notifications = 0
        commit(UI.inputs[edited[1]], value)
        unsubscribe()
        T.assertEq(notifications, 1, edited[1]); T.assertEq(Core.state.rev, rev + 1)
        for i, field in ipairs(fields) do
          local target = field[4] and Core.state.pet.magicShield or Core.state.pet
          T.assertEq(target[field[2]], i == index and value or field[3], field[1])
        end
        Core.Undo()
        local target = edited[4] and Core.state.pet.magicShield or Core.state.pet
        T.assertEq(target[edited[2]], edited[3])
        Core.Redo()
        target = edited[4] and Core.state.pet.magicShield or Core.state.pet
        T.assertEq(target[edited[2]], value)
      end
    end)
    T.it("player defense and attack edits preserve other fields and sticky wounds", function()
      reset(); Core.SetHP(5,100); Core.Heal(100)
      Core.SetArmor(7.5,3.5); Core.SetDodge(2.5); Core.SetTempArmor(1.5); Core.SetTempBlock(4.5)
      Core.SetAttaque(6.5,9.5)
      local rev = Core.state.rev
      commit(UI.inputs.armor, 10)
      T.assertEq(Core.state.rev, rev + 1)
      T.assertEq(Core.state.armor,10); T.assertEq(Core.state.trueArmor,3.5)
      T.assertEq(Core.state.dodge,2.5); T.assertEq(Core.state.tempArmor,1.5); T.assertEq(Core.state.tempBlock,4.5)
      T.assertTrue(Core.state.wounds.hit10)
      commit(UI.inputs.attaqueMelee,12)
      T.assertEq(Core.state.attaqueMelee,12); T.assertEq(Core.state.attaqueDistance,9.5)
      T.assertEq(Core.state.hp,25)
    end)
    T.it("current and maximum edits preserve fractional siblings and enforce existing caps", function()
      reset(); Core.SetHP(50.5,100.5); Core.SetMagicShield(12.5,20.5,4.5); Core.SetChance(8.5,10.5)
      commit(UI.inputs.hpCur,60); T.assertEq(Core.state.maxHp,100.5)
      commit(UI.inputs.hpMax,55); T.assertEq(Core.state.hp,55)
      commit(UI.inputs.msHp,14); T.assertEq(Core.state.magicShield.maxHp,20.5)
      commit(UI.inputs.msMaxHp,10); T.assertEq(Core.state.magicShield.hp,10)
      T.assertEq(Core.state.magicShield.armor,4.5)
      commit(UI.inputs.chanceMax,5); T.assertEq(Core.state.chance,5)
      Core.SetPetEnabled(true); Core.SetPetHP(50.5,100.5); Core.SetPetMagicShield(12.5,20.5,4.5)
      UI.setSidebarSection(2); UI.setTab(9)
      commit(UI.inputs.petHpMax,40); T.assertEq(Core.state.pet.hp,40)
      commit(UI.inputs.petMsMaxHp,10); T.assertEq(Core.state.pet.magicShield.hp,10)
      T.assertEq(Core.state.pet.magicShield.armor,4.5)
    end)
    T.it("resource edits notify once and leave the other displayed resources exact", function()
      reset(); Core.SetClassKey("SHAMAN")
      for i=1,4 do Core.SetResIndex(i, i + 0.5, 20.5) end
      local notifications = 0
      local unsubscribe = GrosOrteilAPI.OnChange(function() notifications = notifications + 1 end)
      notifications = 0
      commit(UI.resRowCur[1],7)
      unsubscribe()
      T.assertEq(notifications,1); T.assertEq(Core.state.res,7); T.assertEq(Core.state.maxRes,20.5)
      T.assertEq(Core.state.res2,2.5); T.assertEq(Core.state.res3,3.5); T.assertEq(Core.state.res4,4.5)
      commit(UI.resRowMax[1],5)
      T.assertEq(Core.state.res,5); T.assertEq(Core.state.maxRes,5)
      T.assertEq(Core.state.maxRes2,20.5); T.assertEq(Core.state.maxRes3,20.5); T.assertEq(Core.state.maxRes4,20.5)
      Core.Undo(); T.assertEq(Core.state.res,7); T.assertEq(Core.state.maxRes,20.5)
      for _, class in ipairs({"MAGE","WARLOCK","SHADOWPRIEST"}) do
        Core.SetClassKey(class); Core.SetResIndex(1,2.5,20.5); Core.SetResIndex(2,4.5,25)
        commit(UI.resRowCur[1],7)
        T.assertEq(Core.state.res2,4.5)
      end
    end)
    T.it("skips hidden grimoire painting and renders mutations, undo and reset on reopening", function()
      reset(); UI.setTab(7)
      local technique = assert(Grimoire.CreateTechnique({title="Avant",description="Description"}))
      local row, writes = UI.grimoireRows[1], 0
      local setText = row.title.SetText
      row.title.SetText = function(self, text) writes = writes + 1; return setText(self,text) end
      UI.setTab(1)
      Core.SetHP(61,100); Core.SetResIndex(1,5,20)
      Core.BreakUndoCoalesce()
      Grimoire.UpdateTechnique(technique.id,{title="Après"})
      T.assertEq(writes,0)
      UI.setTab(7); T.assertEq(row.title:GetText(),"Après"); T.assertTrue(row:IsVisible())
      Core.Undo(); T.assertEq(row.title:GetText(),"Avant")
      Core.Redo(); T.assertEq(row.title:GetText(),"Après")
      ns.UI_Show(false); writes = 0
      Grimoire.UpdateTechnique(technique.id,{title="Réouvert"}); Core.SetHP(60,100)
      T.assertEq(writes,0)
      ns.UI_Show(true); T.assertEq(row.title:GetText(),"Réouvert")
      UI.setTab(1); Core.ResetToDefaults(); UI.setTab(7)
      T.assertFalse(row:IsShown())
      row.title.SetText = setText
    end)
    T.it("refreshes visible editor class selectors without painting its hidden list or overwriting drafts", function()
      reset(); Core.SetClassKey("MAGE"); UI.setTab(7)
      local technique = assert(Grimoire.CreateTechnique({title="Technique",description="Texte",
        cost={classKey="MAGE",resourceIdx=1,amount=2}}))
      local row, writes = UI.grimoireRows[1], 0
      local setText = row.title.SetText
      row.title.SetText = function(self,text) writes=writes+1; return setText(self,text) end
      UI.openGrimoireEditor(technique.id)
      local selector = button("2 Mana")
      UI.grimoireDescriptionEdit:SetText("Brouillon"); UI.grimoireCostAmountEdit:SetText("")
      Core.SetClassKey("WARRIOR")
      T.assertTrue(selector:GetText():find("ancienne classe",1,true) ~= nil)
      T.assertEq(UI.grimoireDescriptionEdit:GetText(),"Brouillon")
      T.assertEq(UI.grimoireCostAmountEdit:GetText(),""); T.assertEq(writes,0)
      ns.UI_Show(false); Core.SetClassKey("MAGE"); ns.UI_Show(true)
      T.assertEq(selector:GetText(),"2 Mana")
      T.assertEq(UI.grimoireDescriptionEdit:GetText(),"Brouillon")
      T.assertEq(UI.grimoireCostAmountEdit:GetText(),""); T.assertEq(writes,0)
      button("Annuler"):RunScript("OnClick")
      T.assertTrue(row:IsVisible()); row.title.SetText=setText
    end)
    T.it("preserves themed roles, disabled colors and one hover surface without restyling unchanged buttons", function()
      reset(); UI.setTab(7)
      local add = button("Ajouter une technique")
      assertColor(add._fs._textColor,Theme.Colors.SUCCESS[1],Theme.Colors.SUCCESS[2],Theme.Colors.SUCCESS[3],1)
      add:RunScript("OnEnter"); T.assertTrue(add._goHover:IsShown())
      add:Disable(); T.assertFalse(add._goHover:IsShown())
      assertColor(add._fs._textColor,Theme.Colors.TEXT_DISABLED[1],Theme.Colors.TEXT_DISABLED[2],Theme.Colors.TEXT_DISABLED[3],1)
      add:Enable()
      assertColor(add._fs._textColor,Theme.Colors.SUCCESS[1],Theme.Colors.SUCCESS[2],Theme.Colors.SUCCESS[3],1)
      local color = add._borderColor
      add:Enable(); T.assertEq(add._borderColor,color)
      for _, f in ipairs(frames.frames) do
        if f._parent == add and f._kind == "Texture" then T.assertNeq(f._layer,"HIGHLIGHT") end
      end
      local style, calls = Theme.StyleButton, 0
      Theme.StyleButton=function(...) calls=calls+1; return style(...) end
      Core.SetHP(61,100)
      Theme.StyleButton=style; T.assertEq(calls,0)
    end)
    T.it("keeps selected affix and posture colors through disable, refresh and undo", function()
      reset(); Core.SetPetEnabled(true); Core.TogglePetAffix("CAMBUSE_ATTAQUE")
      local affix = UI.petAffixButtons[1]
      assertColor(affix._borderColor,1,0.35,0.10,1)
      Core.SetPetEnabled(false)
      T.assertFalse(affix:IsEnabled()); assertColor(affix._borderColor,1,0.35,0.10,1)
      Core.SetHP(61,100); assertColor(affix._borderColor,1,0.35,0.10,1)
      Core.SetPetEnabled(true); Core.BreakUndoCoalesce(); Core.TogglePetAffix("CAMBUSE_ATTAQUE")
      assertColor(affix._backdropColor,Theme.Colors.BROWN_DARK[1],Theme.Colors.BROWN_DARK[2],Theme.Colors.BROWN_DARK[3],0.90)
      Core.Undo(); assertColor(affix._borderColor,1,0.35,0.10,1)
      Core.SetClassKey("SHAMAN"); Core.SetResIndex(1,3,10); Core.SetShamanPosture("TERRE")
      local posture = UI.postureButtons[1]
      local border = posture._borderColor
      Core.SetResIndex(1,0,10); T.assertFalse(posture:IsEnabled())
      assertColor(posture._borderColor,border[1],border[2],border[3],border[4])
      Core.SetHP(60,100); assertColor(posture._borderColor,border[1],border[2],border[3],border[4])
    end)
    T.it("finishes refresh interactions without UI errors", function()
      local errors = require("mocks").errorHandlerCalls
      T.assertEq(#errors,0,table.concat(errors,"\n"))
    end)
  end)
end
