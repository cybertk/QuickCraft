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
		table.insert(o.reagents, { i = reagent.dataSlotIndex, item = reagent.itemID, v = reagent.quantity })
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
	end
end

local allocated = nil
function Schematic:Allocate()
	local schematicForm = ProfessionsFrame.CraftingPage.SchematicForm
	local transaction = schematicForm:GetTransaction()

	if allocated == transaction then
		return
	end

	transaction:SetApplyConcentration(self.concentration ~= nil)

	local target = self.salvage or self.enchant
	if target then
		local item = Item:CreateFromItemGUID(target)
		if not item:HasItemLocation() then
		end
	end

	if self.salvage then
		local item

		if type(self.salvage == "string") then
			item = Item:CreateFromItemGUID(self.salvage)
		else
			local items = C_TradeSkillUI.GetCraftingTargetItems({ self.salvage })
		end

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

	local indexToReagentSlot = {}
	local reagentSlotToFinishingSlot = {}
	local finishingSlot = 0
	for slot, slotSchematic in ipairs(transaction:GetRecipeSchematic().reagentSlotSchematics) do
		if slotSchematic.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent then
			indexToReagentSlot[slotSchematic.dataSlotIndex] = slot
			transaction:ClearAllocations(slot)
		end

		if slotSchematic.reagentType == Enum.CraftingReagentType.Finishing then
			finishingSlot = finishingSlot + 1
			reagentSlotToFinishingSlot[slot] = finishingSlot
		end
	end

	for _, reagent in ipairs(self.reagents) do
		local count = C_Item.GetItemCount(reagent.item, true, true, true, true)
		local slot = indexToReagentSlot[reagent.i]
		local finishingSlot = reagentSlotToFinishingSlot[slot]

		Util:Debug("Allocating", slot, reagent.i, reagent.item, reagent.v, count, finishingSlot)

		if count >= reagent.v then
			transaction:GetAllocations(slot):Allocate({ itemID = reagent.item }, reagent.v)

			if finishingSlot then
				local item = Item:CreateFromItemID(reagent.item)

				schematicForm.reagentSlots[Enum.CraftingReagentType.Finishing][finishingSlot]:SetItem(item)
			end
		end
	end

	schematicForm:UpdateAllSlots()

	transaction:SetManuallyAllocated(true)
	allocated = transaction
end

ns.Schematic = Schematic
