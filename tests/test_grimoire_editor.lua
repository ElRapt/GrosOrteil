-- Registered by run_ui.lua after the actual addon and UI have been loaded.
return function(T, ns, frames)
  local UI, Core, Grimoire = ns.UI, ns.Core, ns.Grimoire

  local function button(text)
    for _, frame in ipairs(frames.frames) do
      if frame._kind == "Button" and frame:IsVisible() and frame:GetText() == text then return frame end
    end
    error("button missing: " .. text)
  end

  local function open(description)
    Core.ResetToDefaults()
    ns.UI_Show(true)
    UI.setSidebarSection(1)
    UI.setTab(UI.TAB_IDS.PLAYER_GRIMOIRE or 7)
    local technique = assert(Grimoire.CreateTechnique({
      title = "Flamme orange", description = description or "Une flamme orange dans la nuit.",
      damageHealing = 12, damageHealingMax = 24,
    }))
    UI.openGrimoireEditor(technique.id)
    frames.layout()
    return technique.id, UI.grimoireTitleEdit, UI.grimoireDescriptionEdit
  end

  T.describe("Grimoire native text editing", function()
    T.it("replaces only the selected words and preserves edits across refresh and focus changes", function()
      local id, title, description = open()
      for _, edit in ipairs({ title, description, UI.grimoireDamageHealingEdit }) do
        T.assertTrue(edit._callEnableMouse[1])
        T.assertFalse(edit._callSetPropagateMouseClicks[1])
      end
      title:HighlightText(7, 13)
      UI.refreshGrimoire(Core.state)
      title:Insert("bleue")
      T.assertEq(title:GetText(), "Flamme bleue")

      description:SetFocus()
      description:HighlightText(11, 17)
      Core.SetHP(61, 100)
      UI.refreshGrimoire(Core.state)
      description:Insert("bleue")
      T.assertEq(description:GetText(), "Une flamme bleue dans la nuit.")
      description:SetCursorPosition(10)
      title:SetFocus()
      description:SetFocus()
      description:Insert(" vive")
      T.assertEq(description:GetText(), "Une flamme vive bleue dans la nuit.")

      local damage = UI.grimoireDamageHealingEdit
      damage:SetFocus()
      damage:HighlightText(0, 2)
      damage:Insert("18")
      title:SetFocus()
      -- Unrelated selectors used to restore the saved damage text on blur.
      button("Illimité"):RunScript("OnClick")
      UI.refreshGrimoire(Core.state)
      T.assertEq(damage:GetText(), "18-24")
      button("Enregistrer"):RunScript("OnClick")
      local saved = Grimoire.GetTechniqueById(id)
      T.assertEq(saved.title, "Flamme bleue")
      T.assertEq(saved.description, "Une flamme vive bleue dans la nuit.")
      T.assertEq(saved.damageHealing, 18)
      T.assertEq(saved.damageHealingMax, 24)
      T.assertFalse(UI.grimoireEditorOpen)
    end)

    T.it("preserves unsaved cost and use counts after selector changes and validation errors", function()
      local id, title = open()
      Core.SetClassKey("MAGE")
      local costSelect = button("Aucun")
      costSelect:RunScript("OnClick")
      local amount, uses = UI.grimoireCostAmountEdit, UI.grimoireUsesEdit
      amount:SetFocus()
      amount:SetText("19")
      title:SetFocus()
      Core.SetHP(61, 100)
      UI.refreshGrimoire(Core.state)
      T.assertEq(amount:GetText(), "19")

      button("Illimité"):RunScript("OnClick")
      T.assertEq(amount:GetText(), "19")
      uses:SetFocus()
      uses:SetText("5")
      title:SetFocus()
      costSelect:RunScript("OnClick")
      UI.refreshGrimoire(Core.state)
      T.assertEq(amount:GetText(), "19")
      T.assertEq(uses:GetText(), "5")

      amount:SetText("")
      title:SetFocus()
      UI.refreshGrimoire(Core.state)
      T.assertEq(amount:GetText(), "")
      button("Enregistrer"):RunScript("OnClick")
      T.assertTrue(UI.grimoireEditorOpen)
      T.assertEq(uses:GetText(), "5")
      amount:SetText("19")
      button("Enregistrer"):RunScript("OnClick")
      local saved = Grimoire.GetTechniqueById(id)
      T.assertEq(saved.cost.amount, 19)
      T.assertEq(saved.usesPerMission, 5)
      T.assertFalse(UI.grimoireEditorOpen)
    end)

    T.it("keeps text undo and redo with the description instead of changing character history", function()
      local _, _, description = open()
      description:SetFocus()
      frames.ctrl, frames.mouseOver = true, UI.frame
      local undoDepth = Core.GetUndoDepth()
      for _, key in ipairs({ "z", "y" }) do
        UI.frame:RunScript("OnKeyDown", key)
        T.assertTrue(UI.frame._propagate)
        T.assertEq(Core.GetUndoDepth(), undoDepth)
      end
      frames.ctrl, frames.mouseOver = false, nil
      button("Annuler"):RunScript("OnClick")
    end)

    T.it("scrolls to the caret and bounds the editable hit area to the visible description", function()
      local _, _, description = open(string.rep("La flamme reste visible pendant trois tours.\n", 90))
      description:SetFocus()
      local scroll = description._scroll
      local range = scroll:GetVerticalScrollRange()
      T.assertTrue(range > 200)
      T.assertEq(scroll:GetVerticalScroll(), 0)
      description:RunScript("OnCursorChanged", 0, -210, 1, 12)
      T.assertEq(scroll:GetVerticalScroll(), 222 - scroll:GetHeight())
      T.assertEq(description._callSetHitRectInsets[3], scroll:GetVerticalScroll())
      T.assertEq(description._callSetHitRectInsets[4],
        description:GetHeight() - scroll:GetVerticalScroll() - scroll:GetHeight())
      description:RunScript("OnCursorChanged", 0, -4, 1, 12)
      T.assertEq(scroll:GetVerticalScroll(), 4)
      description:RunScript("OnMouseWheel", -10000)
      T.assertEq(scroll:GetVerticalScroll(), range)
      T.assertEq(description._callSetHitRectInsets[4], 0)
      description:RunScript("OnMouseWheel", 10000)
      T.assertEq(scroll:GetVerticalScroll(), 0)
      description:RunScript("OnCursorChanged", 0, -100000, 1, 12)
      T.assertEq(scroll:GetVerticalScroll(), range)
      description:SetText("Court")
      frames.layout()
      T.assertEq(scroll:GetVerticalScroll(), 0)
      T.assertEq(description._callSetHitRectInsets[3], 0)
      T.assertEq(description._callSetHitRectInsets[4], 0)
      button("Annuler"):RunScript("OnClick")
    end)

    T.it("opens another technique at its start and keeps select-all confined to manual copy", function()
      local id, title, description = open()
      description:SetFocus()
      description:SetText(string.rep("Une autre ligne.\n", 100))
      frames.layout()
      description:RunScript("OnMouseWheel", -10000)
      button("Annuler"):RunScript("OnClick")
      UI.openGrimoireEditor(id)
      T.assertEq(description:GetCursorPosition(), 0)
      T.assertEq(description._scroll:GetVerticalScroll(), 0)
      title:Insert("Petite ")
      T.assertEq(title:GetText(), "Petite Flamme orange")
      button("Annuler"):RunScript("OnClick")
      button("Copier"):RunScript("OnClick")
      local copy = UI.grimoireCopyDialog.editBox
      local text = Grimoire.FormatTechniqueForCopy(Grimoire.GetTechniqueById(id))
      T.assertEq(copy:GetText(), text)
      T.assertEq(copy._callHighlightText[1], 0)
      T.assertEq(copy._callHighlightText[2], -1)
      copy:Insert("accidental typing")
      T.assertEq(copy:GetText(), text)
      UI.grimoireCopyDialog:Hide()
      UI.setTab(1)
    end)
  end)
end
