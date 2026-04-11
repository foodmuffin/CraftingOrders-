local _, ns = ...

ns.Pricing = ns.Pricing or {}

local Pricing = ns.Pricing
local Util = ns.Util
local L = ns.L

local function LF(key, ...)
	if ns.LF then
		return ns.LF(key, ...)
	end

	local value = (L and L[key]) or key
	if select("#", ...) > 0 then
		return value:format(...)
	end

	return value
end

local function GetAuctioneerSnatch()
	return AucAdvanced
		and AucAdvanced.Modules
		and AucAdvanced.Modules.Util
		and AucAdvanced.Modules.Util.SearchUI
		and AucAdvanced.Modules.Util.SearchUI.Searchers
		and AucAdvanced.Modules.Util.SearchUI.Searchers.Snatch
end

local providers = {
	auctionator = {
		key = "auctionator",
		name = "Auctionator",
	},
	auctioneer = {
		key = "auctioneer",
		name = "Auctioneer",
	},
}

local function BuildShoppingSummary(entries)
	local summary = {
		entryCount = 0,
		totalQuantity = 0,
		estimatedCost = 0,
		pricedEntryCount = 0,
	}

	for _, entry in ipairs(entries or {}) do
		local quantity = math.max(0, entry and entry.quantity or 0)
		if quantity > 0 then
			summary.entryCount = summary.entryCount + 1
			summary.totalQuantity = summary.totalQuantity + quantity
			if type(entry.unitPrice) == "number" and entry.unitPrice > 0 then
				summary.estimatedCost = summary.estimatedCost + (entry.unitPrice * quantity)
				summary.pricedEntryCount = summary.pricedEntryCount + 1
			end
		end
	end

	summary.costKnown = summary.pricedEntryCount > 0
	summary.costComplete = summary.entryCount > 0 and summary.pricedEntryCount == summary.entryCount
	return summary
end

local function FormatShoppingSummary(summary)
	local itemCountText = LF("PRICING_ITEM_COUNT_FORMAT", summary and summary.totalQuantity or 0)
	if not (summary and summary.costKnown) then
		return LF("PRICING_EXPECTED_COST_UNKNOWN_FORMAT", itemCountText)
	end

	local costText = Util.FormatMoney(summary.estimatedCost)
	if not summary.costComplete then
		costText = LF("PRICING_PARTIAL_PRICING_FORMAT", costText)
	end

	return LF("PRICING_EXPECTED_COST_FORMAT", itemCountText, costText)
end

local function GetShoppingEntryTier(entry)
	local tier = entry and entry.reagentQuality
	if type(tier) == "number" and tier > 0 then
		return tier
	end

	if Util.GetProfessionItemQuality then
		local itemLink = entry and type(entry.itemLink) == "string" and entry.itemLink:find("item:") and entry.itemLink or nil
		local refreshedLink = entry and entry.itemID and Util.GetItemLink(entry.itemID) or nil
		local itemIdentity = itemLink or refreshedLink or (entry and entry.itemIdentity) or (entry and entry.itemID)
		tier = Util.GetProfessionItemQuality(entry and itemIdentity)
		if type(tier) == "number" and tier > 0 then
			return tier
		end
	end

	return nil
end

local function BuildPriceInfo(item, count, providerKey, state, unitPrice, isMarketable)
	local quantity = math.max(1, count or 1)
	local hasPrice = type(unitPrice) == "number" and unitPrice > 0

	return {
		item = item,
		count = quantity,
		providerKey = providerKey,
		state = state,
		isMarketable = isMarketable,
		unitPrice = hasPrice and unitPrice or nil,
		totalPrice = hasPrice and (unitPrice * quantity) or nil,
	}
end

local function GetAuctionatorPrice(item)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not api then
		return nil
	end

	if type(item) == "number" then
		local ok, value = pcall(api.GetAuctionPriceByItemID, ns.CALLER_ID, item)
		return ok and value or nil
	end

	local link = Util.GetItemLink(item)
	if not link then
		return nil
	end

	local ok, value = pcall(api.GetAuctionPriceByItemLink, ns.CALLER_ID, link)
	return ok and value or nil
end

local function GetAuctioneerPrice(item)
	if not (AucAdvanced and AucAdvanced.API and type(AucAdvanced.API.GetMarketValue) == "function") then
		return nil
	end

	local link = Util.GetItemLink(item)
	if not link then
		return nil
	end

	local ok, value = pcall(AucAdvanced.API.GetMarketValue, link)
	return ok and value or nil
end

function Pricing:RefreshProviders()
	local config = ns.GetDatabase() or {}
	local auctionatorDetected = ns.IsAddonLoaded("Auctionator")
		and Auctionator
		and Auctionator.API
		and Auctionator.API.v1
		and type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
	local auctioneerDetected = (ns.IsAddonLoaded("Auc-Advanced") or ns.IsAddonLoaded("Auctioneer"))
		and AucAdvanced
		and AucAdvanced.API
		and type(AucAdvanced.API.GetMarketValue) == "function"

	self.status = {
		auctionatorDetected = not not auctionatorDetected,
		auctioneerDetected = not not auctioneerDetected,
		detectedProviderKeys = {},
	}

	if auctionatorDetected then
		self.status.detectedProviderKeys[#self.status.detectedProviderKeys + 1] = providers.auctionator.key
	end
	if auctioneerDetected then
		self.status.detectedProviderKeys[#self.status.detectedProviderKeys + 1] = providers.auctioneer.key
	end

	self.status.auctioneerSnatchReady = self.status.auctioneerDetected
		and GetAuctioneerSnatch()
		and type(GetAuctioneerSnatch().AddSnatch) == "function"
		and GetAuctioneerSnatch().Private
		and GetAuctioneerSnatch().Private.frame
		and true
		or false

	local selectedProviderKey = config.pricingSource
	if selectedProviderKey ~= providers.auctionator.key and selectedProviderKey ~= providers.auctioneer.key then
		selectedProviderKey = nil
	end

	local selectedIsDetected = (selectedProviderKey == providers.auctionator.key and auctionatorDetected)
		or (selectedProviderKey == providers.auctioneer.key and auctioneerDetected)

	if not selectedIsDetected then
		selectedProviderKey = self.status.detectedProviderKeys[1]
	end

	self.activeProvider = selectedProviderKey and providers[selectedProviderKey] or nil
	self.status.activeProviderKey = self.activeProvider and self.activeProvider.key or nil
	self.status.selectedProviderKey = self.status.activeProviderKey
end

function Pricing:Initialize()
	if self.initialized then
		self:RefreshProviders()
		return
	end

	self.initialized = true
	self:RefreshProviders()

	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and type(api.RegisterForDBUpdate) == "function" then
		pcall(api.RegisterForDBUpdate, ns.CALLER_ID, function()
			if ns.BrowsePane and ns.BrowsePane.MarkDirty then
				ns.BrowsePane:MarkDirty("pricing-db")
			end
			if ns.BrowsePane and ns.BrowsePane.MarkDetailWarningDirty then
				ns.BrowsePane:MarkDetailWarningDirty()
			end
			if ns.Options and ns.Options.Refresh then
				ns.Options:Refresh()
			end
		end)
	end
end

function Pricing:GetActiveProvider()
	if not self.initialized then
		self:Initialize()
	end

	return self.activeProvider
end

function Pricing:GetProviderName()
	local provider = self:GetActiveProvider()
	return provider and provider.name or NONE
end

function Pricing:GetStatus()
	if not self.initialized then
		self:Initialize()
	end

	return self.status
end

function Pricing:GetPriceInfo(item, count)
	local provider = self:GetActiveProvider()
	local providerKey = provider and provider.key or nil
	local isMarketable = Util.IsItemMarketable(item)

	if isMarketable == false then
		return BuildPriceInfo(item, count, providerKey, "not_marketable", nil, false)
	end

	if not provider then
		return BuildPriceInfo(item, count, nil, "no_provider", nil, isMarketable)
	end

	local unitPrice
	if provider.key == "auctionator" then
		unitPrice = GetAuctionatorPrice(item)
	else
		unitPrice = GetAuctioneerPrice(item)
	end

	if unitPrice and unitPrice > 0 then
		return BuildPriceInfo(item, count, provider.key, "priced", unitPrice, isMarketable)
	end

	return BuildPriceInfo(item, count, provider.key, "no_data", nil, isMarketable)
end

function Pricing:GetUnitPrice(item)
	local priceInfo = self:GetPriceInfo(item, 1)
	return priceInfo.unitPrice, priceInfo.providerKey, priceInfo.state
end

function Pricing:GetTotalPrice(item, count)
	local priceInfo = self:GetPriceInfo(item, count)
	return priceInfo.totalPrice, priceInfo.providerKey, priceInfo.unitPrice, priceInfo.state
end

function Pricing:CreateAuctionatorShoppingList(entries, listName)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and type(api.ConvertToSearchString) == "function" and type(api.CreateShoppingList) == "function") then
		return false, L.ERR_AUCTIONATOR_API_UNAVAILABLE
	end

	local searchStrings = {}
	local exportedEntries = {}
	for _, entry in ipairs(entries) do
		if entry.isMarketable ~= false then
			local refreshedLink = entry.itemID and Util.GetItemLink(entry.itemID) or nil
			local itemIdentity = (type(entry.itemLink) == "string" and entry.itemLink:find("item:") and entry.itemLink) or refreshedLink or entry.itemIdentity or entry.itemID
			local searchName = entry.name or Util.GetItemName(itemIdentity)
			if searchName then
				local term = {
					searchString = searchName,
					isExact = true,
					quantity = entry.quantity,
					categoryKey = "",
				}

				local tier = GetShoppingEntryTier(entry)
				if tier then
					term.tier = tier
				end

				local ok, searchString = pcall(api.ConvertToSearchString, ns.CALLER_ID, term)
				if ok and searchString then
					searchStrings[#searchStrings + 1] = searchString
					exportedEntries[#exportedEntries + 1] = entry
				end
			end
		end
	end

	if #searchStrings == 0 then
		return false, L.ERR_NO_AUCTIONABLE_REAGENTS_AUCTIONATOR
	end

	local ok, errorMessage = pcall(api.CreateShoppingList, ns.CALLER_ID, listName, searchStrings)
	if not ok then
		return false, errorMessage
	end

	return true, LF("MSG_CREATED_AUCTIONATOR_LIST", listName, FormatShoppingSummary(BuildShoppingSummary(exportedEntries)))
end

function Pricing:CreateAuctioneerSnatchList(entries)
	local snatch = GetAuctioneerSnatch()
	if not (snatch and snatch.Private and snatch.Private.frame and type(snatch.AddSnatch) == "function") then
		return false, L.ERR_AUCTIONEER_SNATCH_NOT_READY
	end

	local addedCount = 0
	local exportedEntries = {}
	for _, entry in ipairs(entries) do
		local refreshedLink = entry.itemID and Util.GetItemLink(entry.itemID) or nil
		local itemIdentity = (type(entry.itemLink) == "string" and entry.itemLink:find("item:") and entry.itemLink) or refreshedLink or entry.itemIdentity or entry.itemID
		local priceInfo = self:GetPriceInfo(itemIdentity, 1)
		local link = Util.GetItemLink(itemIdentity)
		local limit = entry.unitPrice or priceInfo.unitPrice
		if priceInfo.isMarketable ~= false and link and limit and limit > 0 then
			local ok = pcall(snatch.AddSnatch, link, math.floor(limit))
			if ok then
				addedCount = addedCount + 1
				exportedEntries[#exportedEntries + 1] = entry
			end
		end
	end

	if addedCount == 0 then
		return false, L.ERR_AUCTIONEER_NO_EXPORTABLE
	end

	return true,
		LF(
			"MSG_ADDED_AUCTIONEER_SNATCH",
			addedCount,
			FormatShoppingSummary(BuildShoppingSummary(exportedEntries))
		)
end

function Pricing:ExportShoppingList(entries, listName)
	local provider = self:GetActiveProvider()
	if not provider then
		return false, L.ERR_NO_SUPPORTED_PRICING_ADDON
	end

	if provider.key == "auctionator" then
		return self:CreateAuctionatorShoppingList(entries, listName)
	end

	return self:CreateAuctioneerSnatchList(entries)
end
