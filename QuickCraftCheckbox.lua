local _, ns = ...

local Util = ns.Util

local QuickCraftCheckboxMixin = {}

function QuickCraftCheckboxMixin:OnLoad()
	self:SetChecked(QuickCraft.db.char.enabled)

	self:SetScript("OnEnter", self.OnEnter)
	self:SetScript("OnLeave", GameTooltip_Hide)
	self:SetScript("OnClick", self.OnClick)

	hooksecurefunc(ProfessionsFrame.CraftingPage.SchematicForm, "Init", GenerateClosure(self.Update, self))
	hooksecurefunc(C_TradeSkillUI, "CraftEnchant", GenerateClosure(self.Update, self))
	hooksecurefunc(C_TradeSkillUI, "CraftSalvage", GenerateClosure(self.Update, self))
	hooksecurefunc(C_TradeSkillUI, "CraftRecipe", GenerateClosure(self.Update, self))
end

function QuickCraftCheckboxMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self:GetChecked() then
		GameTooltip_AddNormalLine(GameTooltip, "Uncheck to always use the highest quality reagents available.")
	else
		GameTooltip_AddNormalLine(GameTooltip, "Check to always use the reagents from the last craft.")
	end
	GameTooltip:Show()
end

function QuickCraftCheckboxMixin:OnClick()
	Util:Debug("Checkbox OnClick:", self:IsVisible())
	local form = ProfessionsFrame.CraftingPage.SchematicForm
	local checked = self:GetChecked()

	Professions.SetShouldAllocateBestQualityReagents(not checked)
	QuickCraft.db.char.enabled = checked

	if checked then
		self:Update()
	else
		form:TriggerEvent(ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified, true)
		form:UpdateAllSlots()
		self.lastRecipe = nil
	end

	-- Trick to re-fire the OnEnter script to update the tooltip.
	self:Hide()
	self:Show()
	PlaySound(SOUNDKIT.UI_PROFESSION_USE_BEST_REAGENTS_CHECKBOX)
end

function QuickCraftCheckboxMixin:Update()
	Util:Debug("Checkbox Update:", self:IsVisible())
	if not self:IsVisible() then
		return
	end

	local recipe = ProfessionsFrame.CraftingPage.SchematicForm:GetRecipeInfo()
	local schematic = QuickCraft.db.char.schematics[recipe.recipeID]

	local text = "Use Previous Reagents"
	if not schematic then
		text = text .. format(" (|cnRED_FONT_COLOR:%s|r)", "No Saved Reagents")
	elseif QuickCraft.db.char.enabled and self.lastRecipe ~= recipe then
		Util:Debug("Allocating recipe:", recipe.recipeID)

		QuickCraft:RestoreSchematic()
		self.lastRecipe = recipe
	end

	self.text:SetText(LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(text))
end

ns.QuickCraftCheckboxMixin = QuickCraftCheckboxMixin
