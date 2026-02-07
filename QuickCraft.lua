local addonName, ns = ...

local Util = ns.Util
local Schematic = ns.Schematic

local QuickCraft = {}

function QuickCraft:Init()
	local professionSpells = Util:GetLearnedProfessionSpells()

	self.buttons = {}
	for spell, skillLine in pairs(professionSpells) do
		local buttons = Util:FindSpellButtons(spell)

		for _, button in ipairs(buttons) do
			self:CreateOverlayButton(button, skillLine)
		end
	end

	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
		local spellID = tooltip:GetPrimaryTooltipData().id

		if not professionSpells[spellID] then
			return
		end

		if tooltip:GetOwner() == nil then
			return
		end

		local button = tooltip:GetOwner().QuickCraftOverlay
		if button == nil then
			return
		end

		button:UpdateTooltip(tooltip)
	end)

	hooksecurefunc(C_TradeSkillUI, "CraftEnchant", function(recipeSpellID, numCasts, craftingReagents, itemTarget, applyConcentration)
		QuickCraft:SaveSchematic(recipeSpellID, craftingReagents, itemTarget, nil, applyConcentration)
	end)

	hooksecurefunc(C_TradeSkillUI, "CraftSalvage", function(recipeSpellID, numCasts, itemTarget, craftingReagents, applyConcentration)
		QuickCraft:SaveSchematic(recipeSpellID, craftingReagents, nil, itemTarget, applyConcentration)
	end)

	hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function(recipeSpellID, numCasts, craftingReagents, recipeLevel, orderID, applyConcentration)
		QuickCraft:SaveSchematic(recipeSpellID, craftingReagents, nil, nil, applyConcentration)
	end)
end

function QuickCraft:CreateOverlayButton(button, skillLine)
	if button.QuickCraftOverlay then
		Util:Debug("Error: Button has been initialized", button:GetName())
		return
	end

	local overlay = CreateFrame("Button", nil, button, "UIPanelButtonTemplate")

	overlay.skillLine = skillLine
	overlay.lastCraft = self:GetLastSchematic(skillLine, false)
	overlay.lastSalvage = self:GetLastSchematic(skillLine, true)
	Mixin(overlay, ns.QuickCraftButtonMixin)

	overlay:OnLoad()

	button.QuickCraftOverlay = overlay
	table.insert(self.buttons, overlay)
end

function QuickCraft:SaveSchematic(recipeSpellID, craftingReagents, enchantItem, salvageItem, applyConcentration)
	if ProfessionsFrame == nil or not ProfessionsFrame:IsVisible() then
		Util:Debug("Skip saving schematic: QuickCraft")
		return
	end

	local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, false)
	if not ProfessionsFrame.CraftingPage.SchematicForm:IsCurrentRecipe(recipeSchematic.recipeID) then
		Util:Debug("Skip saving schematic: no transation", recipeSpellID)
		return
	end

	Util:Debug("Saving schematic:", recipeSchematic.recipeID, #craftingReagents)
	local schematic = Schematic:Create(recipeSpellID, craftingReagents, enchantItem, salvageItem, applyConcentration)

	self.db.char.schematics[schematic.recipe] = schematic
	self.db.global.schematics[schematic.recipe] = schematic

	Util:Debug("Saved schematic:", schematic.recipe, self.db.char.lastSalvage, self.db.char.lastCraft)

	self:UpdateLastCraft(schematic.recipe, salvageItem ~= nil)
end

function QuickCraft:UpdateLastCraft(recipeID, isSalvage)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)

	local lastCraft = isSalvage and self.db.char.lastSalvage or self.db.char.lastCraft
	local skillLine = info.parentProfessionID or info.professionID

	lastCraft[skillLine] = { recipe = recipeID, skillLine = skillLine }
	lastCraft.updatedAt = GetServerTime()

	Util:Debug("Updated last craft:", recipeID, isSalvage, skillLine)
end

function QuickCraft:RestoreSchematic()
	local recipeID = ProfessionsFrame.CraftingPage.SchematicForm:GetTransaction():GetRecipeID()

	local schematic = self:GetSchematic(recipeID)
	if schematic == nil then
		Util:Debug("No saved schematic:", recipeID)
		return
	end

	schematic:Allocate()
end

function QuickCraft:GetSchematic(recipeID)
	local schematic = self.db.char.schematics[recipeID] or self.db.global.schematics[recipeID]

	if schematic then
		setmetatable(schematic, Schematic)
	end

	return schematic
end

function QuickCraft:GetLastSchematic(skillLine, isSalvage)
	local lastCraft = isSalvage and self.db.char.lastSalvage or self.db.char.lastCraft

	if lastCraft == nil or lastCraft[skillLine] == nil then
		return
	end

	return self:GetSchematic(lastCraft[skillLine].recipe)
end

function QuickCraft:Craft(recipeID)
	local schematic = self:GetSchematic(recipeID)

	if schematic then
		schematic:Craft()
	end
end

function QuickCraft:ExecuteChatCommands(command)
	if command == "debug" then
		-- Toggle Debug Mode
		self.db.global.debug = not self.db.global.debug
		Util.debug = self.db.global.debug
		print("Debug Mode:", self.db.global.debug)
		return
	end

	local action, recipe
	command:gsub("(%a+)%s*(%d*)", function(a, b)
		action, recipe = a, b
	end)

	if action == "craft" then
		QuickCraft:Craft(tonumber(recipe))
		return
	end

	print("Usage:")
	print("  /qc debug - Turn on/off debugging mode")
	print("  /qc craft <recipeID> - Craft the recipe with last-used reagents")
end

if _G["QuickCraft"] == nil then
	_G["QuickCraft"] = QuickCraft

	SLASH_QUICK_CRAFT1 = "/QuickCraft"
	SLASH_QUICK_CRAFT2 = "/qc"
	function SlashCmdList.QUICK_CRAFT(msg, editBox)
		QuickCraft:ExecuteChatCommands(msg)
	end

	local DefaultQuickCraftDB = { schematics = {}, lastCraft = {}, lastSalvage = {} }

	QuickCraft.frame = CreateFrame("Frame")

	QuickCraft.frame:SetScript("OnEvent", function(self, event, ...)
		QuickCraft.eventsHandler[event](event, ...)
	end)

	function QuickCraft:RegisterEvent(name, handler)
		if self.eventsHandler == nil then
			self.eventsHandler = {}
		end
		self.eventsHandler[name] = handler
		self.frame:RegisterEvent(name)
	end

	function QuickCraft:UnregisterEvent(name)
		self.eventsHandler[name] = nil
		self.frame:UnregisterEvent(name)
	end

	QuickCraft:RegisterEvent("PLAYER_ENTERING_WORLD", function(event, isInitialLogin, isReloadingUi)
		if isInitialLogin == false and isReloadingUi == false then
			return
		end

		QuickCraft:Init()
	end)

	QuickCraft:RegisterEvent("TRADE_SKILL_SHOW", function()
		hooksecurefunc(ProfessionsFrame.CraftingPage.SchematicForm, "Init", function()
			QuickCraft:RestoreSchematic()
		end)
		QuickCraft:UnregisterEvent("TRADE_SKILL_SHOW")
	end)

	QuickCraft:RegisterEvent("ADDON_LOADED", function(event, name)
		if name ~= addonName then
			return
		end

		QuickCraftDB = QuickCraftDB or DefaultQuickCraftDB
		QuickCraftPerCharacterDB = QuickCraftPerCharacterDB or DefaultQuickCraftDB

		Util.debug = QuickCraftDB.debug
		QuickCraft.db = { char = QuickCraftPerCharacterDB, global = QuickCraftDB }
	end)
end
