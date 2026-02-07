local _, ns = ...

local Util = ns.Util

local Schematic = {}
Schematic.__index = Schematic

function Schematic.__eq(a, b)
	if a == nil or b == nil then
		return false
	end

	return a.recipeID == b.recipeID and a.concentration == b.concentration and a.salvage == b.salvage and a.enchant == b.enchant
end

function Schematic:Create(recipeSpellID, craftingReagents, enchantItem, salvageItem, applyConcentration)
	local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, false)
	local o = {}

	o.reagents = {}
	for _, reagent in ipairs(craftingReagents or {}) do
		table.insert(o.reagents, { i = reagent.dataSlotIndex, item = reagent.reagent.itemID, v = reagent.quantity })
	end

	if enchantItem then
		o.enchant = C_Item.GetItemGUID(enchantItem)
	end

	if salvageItem then
		o.salvage = C_Item.GetItemGUID(salvageItem)
	end

	if applyConcentration then
		local ops = C_TradeSkillUI.GetCraftingOperationInfo(recipeSchematic.recipeID, craftingReagents, nil, true)
		o.concentration = ops.concentrationCost

		Util:Debug("Saved Concentration", o.concentration)
	end

	o.recipe = recipeSchematic.recipeID
	o.spell = recipeSpellID
	o.updatedAt = GetServerTime()

	setmetatable(o, self)

	return o
end

function Schematic:GetTargetItemLocation()
	local target = self.salvage or self.enchant
	if target == nil then
		return
	end

	local item = Item:CreateFromItemGUID(target)
	if item:HasItemLocation() then
		return item:GetItemLocation()
	end

	for _, target in ipairs(C_TradeSkillUI.GetCraftingTargetItems({ C_Item.GetItemIDByGUID(target) })) do
		local location = C_Item.GetItemLocation(target.itemGUID)

		if location and location:IsBagAndSlot() then
			return location
		end
	end

	Util:Debug("Cannot find any valid target", self.recipe)
end

function Schematic:Craft(numCasts)
	numCasts = numCasts or 1

	local reagents = {}
	for _, reagent in ipairs(self.reagents) do
		table.insert(reagents, { itemID = reagent.item, dataSlotIndex = reagent.i, quantity = reagent.v })
	end

	local location = self:GetTargetItemLocation()
	if self.enchant and location then
		C_TradeSkillUI.CraftEnchant(self.spell, numCasts, reagents, location, self.concentration ~= nil)
	elseif self.salvage and location then
		C_TradeSkillUI.CraftSalvage(self.spell, numCasts, location)
	else
		C_TradeSkillUI.CraftRecipe(self.spell, numCasts, reagents, nil, nil, self.concentration ~= nil)
	end
end

function Schematic:Allocate()
	local schematicForm = ProfessionsFrame.CraftingPage.SchematicForm
	local transaction = schematicForm:GetTransaction()

	if self.salvage then
		local item = Item:CreateFromItemGUID(self.salvage)

		Util:Debug("Allocating salvage:", self.salvage, item:GetItemLink())
		if item:GetItemID() then
			transaction:SetSalvageAllocation(item)
			schematicForm.salvageSlot:SetItem(item)
		end
	end

	if self.enchant then
		local item = Item:CreateFromItemGUID(self.enchant)

		Util:Debug("Allocating enchant:", self.enchant, item:GetItemLink())
		if item:GetItemID() then
			transaction:SetEnchantAllocation(item)
			schematicForm.enchantSlot:SetItem(item)
		end
	end

	self:AllocateReagents(schematicForm)

	transaction:SetApplyConcentration(self.concentration ~= nil)
	transaction:SetManuallyAllocated(true)

	return true
end

function Schematic:AllocateReagents(schematicForm)
	local transaction = schematicForm:GetTransaction()

	local slots = {}
	for _, reagentSlots in pairs(schematicForm.reagentSlots) do
		for _, slot in ipairs(reagentSlots) do
			local schematic = slot:GetReagentSlotSchematic()

			if schematic.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent then
				transaction:ClearAllocations(schematic.slotIndex)
			end

			slots[schematic.dataSlotIndex] = slot
		end
	end

	for _, reagent in ipairs(self.reagents or {}) do
		local slot = slots[reagent.i]
		local count = 0

		if reagent.item then
			count = C_Item.GetItemCount(reagent.item, true, true, true, true)
		end

		Util:Debug("Allocating", slot:GetSlotIndex(), reagent.i, reagent.item, reagent.v, count)

		if count >= reagent.v then
			transaction:GetAllocations(slot:GetSlotIndex()):Allocate({ itemID = reagent.item }, reagent.v)
			slot:SetReagent({ itemID = reagent.item })
		end
	end
end

ns.Schematic = Schematic
