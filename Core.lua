local addonName, ns = ...

ns.ADDON_NAME = addonName
ns.CALLER_ID = addonName
ns.ORDER_TYPE_NPC = Enum.CraftingOrderType and Enum.CraftingOrderType.Npc or 3
ns.DEFAULT_SORT_KEY = "reward"

local eventFrame = CreateFrame("Frame")
local eventCallbacks = {}
ns.EventFrame = eventFrame
ns.Util = {}
local IsAddOnLoadedAPI = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
local GetAddOnMetadataAPI = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

local defaults = {
	pricingSource = "auctionator",
	dontBuyItems = {},
	dontBuyItemsByCharacter = {},
	dontBuyPerCharacter = false,
	openPatronOrderBehavior = "none",
	warnExpensiveIngredients = true,
	expensiveIngredientThresholdPercent = 10,
	greyUnknownRecipes = true,
	showRewardValue = true,
	showSilverCopperInList = false,
}

local function CopyDefaults(source, destination)
	for key, value in pairs(source) do
		if type(value) == "table" then
			local target = type(destination[key]) == "table" and destination[key] or {}
			destination[key] = target
			CopyDefaults(value, target)
		elseif destination[key] == nil then
			destination[key] = value
		end
	end
end

local function MigrateDatabase(db)
	if type(db) ~= "table" then
		return
	end

	if db.pricingSource == nil then
		local prefersAuctioneer = db.preferAuctioneer
			or (db.useAuctionator == false and db.useAuctioneer ~= false)
			or (db.enableAuctionator == false and db.enableAuctioneer ~= false)
		db.pricingSource = prefersAuctioneer and "auctioneer" or "auctionator"
	end
end

local function CopyBooleanMap(source, destination)
	if type(source) ~= "table" or type(destination) ~= "table" then
		return destination
	end

	for key, value in pairs(source) do
		if value then
			destination[key] = true
		end
	end

	return destination
end

local function GetCharacterKey()
	local name, realm = UnitFullName and UnitFullName("player")
	name = name or UnitName("player")
	realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
	if not name or name == "" then
		return nil
	end

	if realm and realm ~= "" then
		return ("%s-%s"):format(name, realm)
	end

	return name
end

local function GetItemLink(item)
	if type(item) == "string" and item ~= "" then
		return item
	elseif type(item) == "number" and item > 0 then
		return select(2, GetItemInfo(item))
	end
end

local function GetItemName(item)
	if type(item) == "string" and item ~= "" then
		local itemID = tonumber(item:match("item:(%d+)"))
		local itemName
		if itemID then
			itemName = GetItemInfo(itemID)
		end
		return itemName or item:match("%[(.-)%]")
	elseif type(item) == "number" and item > 0 then
		return GetItemInfo(item)
	end
end

local function CallGetItemCount(item, includeBank, includeUses, includeReagentBank, includeAccountBank)
	local ok, count = pcall(C_Item.GetItemCount, item, includeBank, includeUses, includeReagentBank, includeAccountBank)
	if ok and type(count) == "number" then
		return count
	end

	ok, count = pcall(C_Item.GetItemCount, item, includeBank, includeUses, includeReagentBank)
	if ok and type(count) == "number" then
		return count
	end

	return nil
end

local function GetItemCount(itemID)
	if not itemID or itemID == 0 or itemID == "" then
		return 0
	end

	local count = CallGetItemCount(itemID, true, false, nil, true)
	if type(count) == "number" then
		return count
	end

	if type(itemID) == "string" then
		local numericItemID = tonumber(itemID:match("item:(%d+)"))
		if numericItemID then
			count = CallGetItemCount(numericItemID, true, false, nil, true)
			if type(count) == "number" then
				return count
			end
		end
	end

	return 0
end

local GetProfessionItemQuality

local function GetQualityAwareItemCounts(itemID, itemLink)
	local totalCount = GetItemCount(itemID or itemLink)
	local selectedCount = totalCount
	local quality = GetProfessionItemQuality(itemLink)

	if quality and type(itemLink) == "string" and itemLink ~= "" then
		local exactCount = CallGetItemCount(itemLink, true, false, true, true)
		if type(exactCount) == "number" then
			selectedCount = exactCount
		end
	end

	selectedCount = math.max(0, math.min(totalCount, selectedCount or 0))
	return selectedCount, math.max(0, totalCount - selectedCount), totalCount
end

function GetProfessionItemQuality(item)
	if not item then
		return nil
	end

	if type(item) == "string" then
		local quality = tonumber(item:match("Professions%-ChatIcon%-Quality%-12%-Tier(%d+)"))
			or tonumber(item:match("Professions%-ChatIcon%-Quality%-Tier(%d+)"))
			or tonumber(item:match("Professions%-Icon%-Quality%-12%-Tier(%d+)"))
			or tonumber(item:match("Professions%-Icon%-Quality%-Tier(%d+)"))
		if quality and quality > 0 then
			return quality
		end
	end

	if not C_TradeSkillUI then
		return nil
	end

	if type(C_TradeSkillUI.GetItemReagentQualityByItemInfo) == "function" then
		local ok, quality = pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, item)
		if ok and type(quality) == "number" and quality > 0 then
			return quality
		end
	end

	if type(C_TradeSkillUI.GetItemReagentQualityInfo) == "function" then
		local ok, info = pcall(C_TradeSkillUI.GetItemReagentQualityInfo, item)
		if ok and type(info) == "table" and type(info.iconChat) == "string" then
			local quality = tonumber(info.iconChat:match("Quality%-12%-Tier(%d+)"))
				or tonumber(info.iconChat:match("Quality%-Tier(%d+)"))
			if quality and quality > 0 then
				return quality
			end
		end
	end

	if type(C_TradeSkillUI.GetItemCraftedQualityByItemInfo) == "function" then
		local ok, quality = pcall(C_TradeSkillUI.GetItemCraftedQualityByItemInfo, item)
		if ok and type(quality) == "number" and quality > 0 then
			return quality
		end
	end
end

local MARKETABLE_BIND_TYPES = {
	[(LE_ITEM_BIND_NONE or (Enum.ItemBind and Enum.ItemBind.None) or 0)] = true,
	[(LE_ITEM_BIND_ON_EQUIP or (Enum.ItemBind and Enum.ItemBind.OnEquip) or 2)] = true,
	[(LE_ITEM_BIND_ON_USE or (Enum.ItemBind and Enum.ItemBind.OnUse) or 3)] = true,
}

local function GetItemBindType(item)
	if not item or item == "" or item == 0 then
		return nil
	end

	return select(14, GetItemInfo(item))
end

local function IsItemMarketable(item)
	local bindType = GetItemBindType(item)
	if bindType == nil then
		return nil
	end

	return not not MARKETABLE_BIND_TYPES[bindType]
end

local function Clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end

local function FormatMoney(value)
	if not value or value <= 0 then
		return NONE
	end
	return GetMoneyString(math.floor(value), true)
end

local function GetLocalTimeStamp()
	return date("%Y-%m-%d %H:%M")
end

local function SafeCall(func, ...)
	if type(func) ~= "function" then
		return false
	end

	return pcall(func, ...)
end

local function Print(message)
	local title = (ns.L and ns.L.ADDON_TITLE) or addonName
	DEFAULT_CHAT_FRAME:AddMessage(("|cff4cc9f0%s|r: %s"):format(title, tostring(message)))
end

function ns.RegisterEvent(eventName, callback)
	eventFrame:RegisterEvent(eventName)
	eventCallbacks[eventName] = callback
end

function ns.Util.CreateArray()
	return {}
end

ns.Util.Clamp = Clamp
ns.Util.CopyDefaults = CopyDefaults
ns.Util.FormatMoney = FormatMoney
ns.Util.GetItemBindType = GetItemBindType
ns.Util.GetItemCount = GetItemCount
ns.Util.GetItemLink = GetItemLink
ns.Util.IsItemMarketable = IsItemMarketable
ns.Util.GetItemName = GetItemName
ns.Util.GetProfessionItemQuality = GetProfessionItemQuality
ns.Util.GetQualityAwareItemCounts = GetQualityAwareItemCounts
ns.Util.GetLocalTimeStamp = GetLocalTimeStamp
ns.Util.SafeCall = SafeCall
ns.Print = Print
ns.GetCharacterKey = GetCharacterKey

function ns.GetDatabase()
	return CraftingOrdersPlusPlusDB
end

function ns.GetConfig(key)
	return CraftingOrdersPlusPlusDB and CraftingOrdersPlusPlusDB[key]
end

function ns.SetConfig(key, value)
	if not CraftingOrdersPlusPlusDB then
		return
	end
	CraftingOrdersPlusPlusDB[key] = value
	if ns.Pricing and ns.Pricing.RefreshProviders then
		ns.Pricing:RefreshProviders()
	end
	if ns.Options and ns.Options.Refresh then
		ns.Options:Refresh()
	end
	if ns.BrowsePane and ns.BrowsePane.MarkDirty then
		ns.BrowsePane:MarkDirty("config")
	end
	if ns.BrowsePane and ns.BrowsePane.MarkDetailWarningDirty then
		ns.BrowsePane:MarkDetailWarningDirty()
	end
end

function ns.GetDontBuyList()
	local db = ns.GetDatabase()
	if type(db) ~= "table" then
		return nil
	end

	db.dontBuyItems = type(db.dontBuyItems) == "table" and db.dontBuyItems or {}
	db.dontBuyItemsByCharacter = type(db.dontBuyItemsByCharacter) == "table" and db.dontBuyItemsByCharacter or {}

	if not db.dontBuyPerCharacter then
		return db.dontBuyItems
	end

	local characterKey = GetCharacterKey()
	if not characterKey then
		return db.dontBuyItems
	end

	local characterList = db.dontBuyItemsByCharacter[characterKey]
	if type(characterList) ~= "table" then
		characterList = CopyBooleanMap(db.dontBuyItems, {})
		db.dontBuyItemsByCharacter[characterKey] = characterList
	end

	return characterList
end

function ns.SetDontBuyScopePerCharacter(enabled)
	local db = ns.GetDatabase()
	if type(db) ~= "table" then
		return
	end

	enabled = not not enabled
	db.dontBuyItems = type(db.dontBuyItems) == "table" and db.dontBuyItems or {}
	db.dontBuyItemsByCharacter = type(db.dontBuyItemsByCharacter) == "table" and db.dontBuyItemsByCharacter or {}

	local characterKey = GetCharacterKey()
	if enabled then
		if characterKey and type(db.dontBuyItemsByCharacter[characterKey]) ~= "table" then
			db.dontBuyItemsByCharacter[characterKey] = CopyBooleanMap(db.dontBuyItems, {})
		end
	elseif characterKey and next(db.dontBuyItems) == nil and type(db.dontBuyItemsByCharacter[characterKey]) == "table" then
		CopyBooleanMap(db.dontBuyItemsByCharacter[characterKey], db.dontBuyItems)
	end

	ns.SetConfig("dontBuyPerCharacter", enabled)
end

function ns.IsAddonLoaded(name)
	if not name or name == "" or type(IsAddOnLoadedAPI) ~= "function" then
		return false
	end

	local ok, isLoaded = pcall(IsAddOnLoadedAPI, name)
	return ok and not not isLoaded or false
end

function ns.GetAddonMetadata(name, field)
	if not name or name == "" or not field or field == "" or type(GetAddOnMetadataAPI) ~= "function" then
		return nil
	end

	local ok, value = pcall(GetAddOnMetadataAPI, name, field)
	return ok and value or nil
end

function ns.IsProfessionsReady()
	return type(ProfessionsFrame) == "table"
		and type(ProfessionsFrame.OrdersPage) == "table"
		and type(ProfessionsFrame.OrdersPage.BrowseFrame) == "table"
end

function ns.InitializeDatabase()
	CraftingOrdersPlusPlusDB = type(CraftingOrdersPlusPlusDB) == "table" and CraftingOrdersPlusPlusDB or {}
	MigrateDatabase(CraftingOrdersPlusPlusDB)
	CopyDefaults(defaults, CraftingOrdersPlusPlusDB)
end

local function SafeInitializeModule(module)
	if not (module and type(module.Initialize) == "function") then
		return
	end

	local errorHandler = geterrorhandler and geterrorhandler()
	if type(errorHandler) == "function" then
		xpcall(function()
			module:Initialize()
		end, errorHandler)
	else
		pcall(function()
			module:Initialize()
		end)
	end
end

function ns.InitializeCommonModules()
	if type(CraftingOrdersPlusPlusDB) ~= "table" then
		ns.InitializeDatabase()
	end

	SafeInitializeModule(ns.Pricing)
	SafeInitializeModule(ns.Options)
end

function ns.InitializeProfessionsModules()
	if type(CraftingOrdersPlusPlusDB) ~= "table" then
		ns.InitializeDatabase()
	end

	if not ns.IsProfessionsReady() then
		if ns.IsAddonLoaded("Blizzard_Professions") then
			C_Timer.After(0.1, ns.InitializeProfessionsModules)
		end
		return
	end

	SafeInitializeModule(ns.BrowsePane)
end

function ns.InitializeModules()
	ns.InitializeCommonModules()
	ns.InitializeProfessionsModules()
end

eventFrame:SetScript("OnEvent", function(_, eventName, ...)
	if eventName == "ADDON_LOADED" then
		local loadedAddonName = ...
		if loadedAddonName == addonName then
			ns.InitializeDatabase()
		elseif loadedAddonName == "Blizzard_Professions" then
			C_Timer.After(0, ns.InitializeProfessionsModules)
		end
	end

	if eventName == "PLAYER_LOGIN" then
		ns.InitializeModules()
	end

	local callback = eventCallbacks[eventName]
	if callback then
		callback(ns, ...)
	end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
