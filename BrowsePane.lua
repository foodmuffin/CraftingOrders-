local _, ns = ...

ns.BrowsePane = ns.BrowsePane or {}

local Pane = ns.BrowsePane
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

local ROW_HEIGHT = 62
local HEADER_HEIGHT = 20
local SELECT_WIDTH = 28
local ORDER_WIDTH = 340
local COST_WIDTH = 96
local REWARD_WIDTH = 124
local PROFIT_WIDTH = 92
local PATRON_WIDTH = 28
local PRODUCT_ICON_SIZE = 50
local PRODUCT_ICON_LEFT_OFFSET = 4
local PRODUCT_ICON_TOP_OFFSET = -6
local PRODUCT_TEXT_GAP = 8
local REAGENT_ICON_SIZE = 28
local ICON_GROUP_SPACER = 8
local MUTABLE_SLOT_TYPE = Enum.TradeskillSlotDataType and Enum.TradeskillSlotDataType.ModifiedReagent
local CONTENT_WIDTH = SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + REWARD_WIDTH + PROFIT_WIDTH + PATRON_WIDTH + 24
local ROOT_WIDTH = 800
local ROOT_HEIGHT = 542.5
local ROOT_RIGHT_OFFSET = -2
local ROOT_BOTTOM_OFFSET = 3
local BACKGROUND_TOP_OFFSET = -0.5
local HEADER_TOP_OFFSET = 19
local SCROLL_TOP_OFFSET = -2
local ROW_ICON_Y_OFFSET = -28
local CREATE_LIST_BUTTON_WIDTH = 22
local CREATE_LIST_BUTTON_HEIGHT = 18
local CREATE_LIST_BUTTON_LEFT_OFFSET = 4
local CREATE_LIST_BUTTON_TOP_OFFSET = 19
local FILTER_BUTTON_WIDTH = 88
local FILTER_BUTTON_HEIGHT = HEADER_HEIGHT
local FILTER_BUTTON_RIGHT_OFFSET = -2
local FILTER_BUTTON_TOP_OFFSET = HEADER_TOP_OFFSET
local FILTER_PANEL_WIDTH = 188
local FILTER_PANEL_HEIGHT = 122
local REQUEST_COOLDOWN = 0.75
local REQUEST_TIMEOUT = 12
local REQUEST_SETTLE_DELAY = 0.25
local REQUEST_READINESS_RETRY_DELAY = 0.15
local REQUEST_READINESS_RETRY_LIMIT = 20
local ITEM_DATA_REFRESH_DELAY = 0.75
local INITIALIZE_RETRY_DELAY = 0.1
local DONT_BUY_OVERLAY_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local DETAIL_WARNING_ICON_TEXTURE = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
local DETAIL_WARNING_UPDATE_DELAY = 0.05
local RECIPE_FILTER_ALL = "all"
local RECIPE_FILTER_KNOWN = "known"
local RECIPE_FILTER_UNKNOWN = "unknown"
local CONCENTRATION_FILTER_ALL = "all"
local CONCENTRATION_FILTER_NEEDS = "needs"
local CONCENTRATION_FILTER_NONE = "none"

local BORDER_BY_ITEM_QUALITY = {
	[0] = "Professions-Slot-Frame",
	"Professions-Slot-Frame",
	"Professions-Slot-Frame-Green",
	"Professions-Slot-Frame-Blue",
	"Professions-Slot-Frame-Epic",
	"Professions-Slot-Frame-Legendary",
}

local REWARD_KNOWLEDGE_ITEMS = {
	[228724] = 1,
	[228725] = 2,
	[228726] = 1,
	[228727] = 2,
	[228728] = 1,
	[228729] = 2,
	[228730] = 1,
	[228731] = 2,
	[228732] = 1,
	[228733] = 2,
	[228734] = 1,
	[228735] = 2,
	[228736] = 1,
	[228737] = 2,
	[228738] = 1,
	[228739] = 2,
	[246320] = 1,
	[246321] = 2,
	[246322] = 1,
	[246323] = 2,
	[246324] = 1,
	[246325] = 2,
	[246326] = 1,
	[246327] = 2,
	[246328] = 1,
	[246329] = 2,
	[246330] = 1,
	[246331] = 2,
	[246332] = 1,
	[246333] = 2,
	[246334] = 1,
	[246335] = 2,
}

local ACUITY_ITEM_ID = 210814
local ACUITY_CURRENCY_IDS = {
	[3256] = true,
	[3257] = true,
	[3258] = true,
	[3259] = true,
	[3261] = true,
	[3262] = true,
	[3263] = true,
	[3266] = true,
}

local QUALITY_TICK_GREEN = "common-icon-checkmark"
local QUALITY_TICK_AMBER = "common-icon-checkmark-yellow"
local QUALITY_WEIGHT_BASE = 1000
local EMPTY_STATE_LOADING_TEXT = L.EMPTY_STATE_LOADING
local EMPTY_STATE_EMPTY_TEXT = L.EMPTY_STATE_EMPTY
local EMPTY_STATE_FILTERED_TEXT = L.EMPTY_STATE_FILTERED

local EXPIRE_THRESHOLDS = {
	{"|cffa0a0a0", 6 * 3600},
	{"|cffe8e800", 3600},
	{"|cffd84000", -math.huge},
}

Pane.sortKey = ns.DEFAULT_SORT_KEY
Pane.sortAscending = false
Pane.allOrders = {}
Pane.rows = {}
Pane.orders = {}
Pane.selectedOrderIDs = {}
Pane.preparedOrderCache = {}
Pane.rebuildGeneration = 0
Pane.ordersGeneration = 0
Pane.hasUnresolvedItemData = false
Pane.unresolvedItemIDs = {}
Pane.needsRequest = false
Pane.needsRebuild = false
Pane.needsRender = false
Pane.pendingReason = nil
Pane.pendingDueAt = nil
Pane.visibleSessionId = 0
Pane.requestReadinessRetryCount = 0
Pane.recipeFilter = RECIPE_FILTER_ALL
Pane.concentrationFilter = CONCENTRATION_FILTER_ALL

local function FormatCount(count, alwaysShow)
	if count and (count > 1 or (alwaysShow and count > 0)) then
		return count
	end
	return ""
end

local function FormatItemCountLabel(quantity, label)
	return LF("ITEM_COUNT_FORMAT", quantity or 0, label or UNKNOWN)
end

local function GetDontBuyKey(itemID)
	if type(itemID) ~= "number" or itemID <= 0 then
		return nil
	end

	return tostring(itemID)
end

local function GetExpensiveIngredientThresholdPercent()
	local value = tonumber(ns.GetConfig("expensiveIngredientThresholdPercent")) or 10
	return math.max(0, math.min(100, math.floor(value + 0.5)))
end

local function NormalizeReagentGroupName(name)
	if type(name) ~= "string" then
		return nil
	end

	name = name:gsub("|A.-|a", "")
	name = name:gsub("%s+", " ")
	name = name:match("^%s*(.-)%s*$")
	if not name or name == "" then
		return nil
	end

	return name:lower()
end

local function GetExpensiveIngredientGroupKey(option)
	if not option or (option.reagentQuality or 0) <= 0 then
		return nil
	end

	return NormalizeReagentGroupName(option.name or Util.GetItemName(option.itemLink or option.itemID))
end

local function IsPricedMarketOption(option)
	return option
		and option.priceState ~= "not_marketable"
		and type(option.unitPrice) == "number"
		and option.unitPrice > 0
end

local function IsCheaperWarningOption(left, right)
	if not left then
		return false
	end
	if not right then
		return true
	end
	if (left.unitPrice or math.huge) ~= (right.unitPrice or math.huge) then
		return (left.unitPrice or math.huge) < (right.unitPrice or math.huge)
	end

	return (left.reagentQuality or math.huge) < (right.reagentQuality or math.huge)
end

local function GetWarningColor()
	return WARNING_FONT_COLOR or NORMAL_FONT_COLOR or { r = 1, g = 0.82, b = 0 }
end

local function GetSavingsColor()
	return GREEN_FONT_COLOR or HIGHLIGHT_FONT_COLOR or { r = 0.25, g = 0.9, b = 0.35 }
end

local function GetMutedTooltipColor()
	return HIGHLIGHT_FONT_COLOR or { r = 0.9, g = 0.9, b = 0.9 }
end

local function GetDontBuyMap()
	if ns.GetDontBuyList then
		return ns.GetDontBuyList()
	end

	local db = ns.GetDatabase()
	if type(db) ~= "table" then
		return nil
	end

	db.dontBuyItems = type(db.dontBuyItems) == "table" and db.dontBuyItems or {}
	return db.dontBuyItems
end

function Pane:IsDontBuyItem(itemID)
	local key = GetDontBuyKey(itemID)
	local map = GetDontBuyMap()
	return key and map and not not map[key] or false
end

function Pane:SetDontBuyItem(itemID, value)
	local key = GetDontBuyKey(itemID)
	local map = GetDontBuyMap()
	if not (key and map) then
		return
	end

	if value then
		map[key] = true
	else
		map[key] = nil
	end
end

function Pane:ToggleDontBuyItem(itemID)
	if not itemID then
		return false
	end

	local isIgnored = not self:IsDontBuyItem(itemID)
	self:SetDontBuyItem(itemID, isIgnored)
	if self.root and self.root:IsShown() then
		self:RenderRows()
	end
	return isIgnored
end

local function LinkHasDisplayName(link)
	return type(link) == "string" and link ~= "" and not link:find("%[%]")
end

local function GetReagentItemIdentity(itemID, itemLink)
	if LinkHasDisplayName(itemLink) then
		return itemLink
	end

	if itemID and itemID > 0 then
		return itemID
	end

	return itemLink
end

local function GetShoppingEntryGroupKey(entry)
	local itemKey = entry and (entry.itemID or entry.itemLink) or "?"
	local reagentQuality = entry and entry.reagentQuality or 0
	return ("%s:%s"):format(tostring(itemKey), tostring(reagentQuality))
end

local function FormatSignedMoney(value)
	if value == nil then
		return NONE
	end

	local amount = math.floor(math.abs(value))
	local formatted = GetMoneyString(amount, true)
	if value < 0 then
		return "-" .. formatted
	end

	return formatted
end

local function NumericSortValue(value)
	return type(value) == "number" and value or 0
end

local function IsExcludedFromMarketValue(priceState)
	return priceState == "not_marketable"
end

local function GetPriceDisplayText(totalPrice, priceState)
	if totalPrice then
		return Util.FormatMoney(totalPrice)
	end

	if IsExcludedFromMarketValue(priceState) then
		return L.PRICE_NOT_MARKETABLE
	end

	return L.PRICE_NO_MARKET_DATA
end

local function GetMarketPreferenceRank(priceState, unitPrice)
	if IsExcludedFromMarketValue(priceState) then
		return 2
	end

	if type(unitPrice) == "number" and unitPrice > 0 then
		return 0
	end

	return 1
end

local function GetGoldIconMarkup()
	if type(CreateTextureMarkup) == "function" then
		return CreateTextureMarkup("Interface\\MoneyFrame\\UI-GoldIcon", 16, 16, 14, 14, 0, 1, 0, 1, 2, 0)
	end

	return "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t"
end

local function FormatGoldOnly(value, signed)
	local goldValue = math.floor(math.abs(value) / 10000)
	local amountText = type(BreakUpLargeNumbers) == "function" and BreakUpLargeNumbers(goldValue) or tostring(goldValue)
	local formatted = amountText .. GetGoldIconMarkup()
	if signed and value < 0 then
		return "-" .. formatted
	end

	return formatted
end

local function FormatListMoney(value, signed)
	if value == nil then
		return NONE
	end

	if ns.GetConfig("showSilverCopperInList") then
		return signed and FormatSignedMoney(value) or Util.FormatMoney(value)
	end

	return FormatGoldOnly(value, signed)
end

local function FormatTimeRemaining(secondsRemaining)
	if secondsRemaining >= 86400 then
		return LF("TIME_SHORT_DAYS_FORMAT", math.max(1, math.ceil(secondsRemaining / 86400)))
	elseif secondsRemaining >= 3600 then
		return LF("TIME_SHORT_HOURS_FORMAT", math.max(1, math.ceil(secondsRemaining / 3600)))
	end

	return LF("TIME_SHORT_MINUTES_FORMAT", math.max(1, math.ceil(secondsRemaining / 60)))
end

local function GetTimeColorCode(secondsRemaining)
	for _, thresholdInfo in ipairs(EXPIRE_THRESHOLDS) do
		if secondsRemaining > thresholdInfo[2] then
			return thresholdInfo[1]
		end
	end

	return EXPIRE_THRESHOLDS[#EXPIRE_THRESHOLDS][1]
end

local function GetTimeColor(secondsRemaining)
	local colorCode = GetTimeColorCode(secondsRemaining)
	local red, green, blue = colorCode:match("(%x%x)(%x%x)(%x%x)$")
	if red and green and blue then
		return tonumber(red, 16) / 255, tonumber(green, 16) / 255, tonumber(blue, 16) / 255
	end

	return 0.63, 0.63, 0.63
end

local function GetTimeHeaderText()
	if type(CreateAtlasMarkup) == "function" then
		return CreateAtlasMarkup("auctionhouse-icon-clock", 14, 14, 0, -1)
	end

	return L.TIME_HEADER
end

local function GetAtlasMarkup(atlas, width, height, offsetX, offsetY)
	if not atlas or atlas == "" then
		return ""
	end

	if type(CreateAtlasMarkup) == "function" then
		return CreateAtlasMarkup(atlas, width, height, offsetX or 0, offsetY or 0)
	end

	return ("|A:%s:%d:%d:%d:%d|a"):format(atlas, width or 0, height or 0, offsetX or 0, offsetY or 0)
end

local function GetAtlasInfoData(atlas)
	if not atlas or atlas == "" then
		return nil
	end

	if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
		return C_Texture.GetAtlasInfo(atlas)
	end

	if type(GetAtlasInfo) == "function" then
		return GetAtlasInfo(atlas)
	end

	return nil
end

local function GetAspectCorrectAtlasMarkup(atlas, width, height, offsetX, offsetY)
	local resolvedWidth = tonumber(width) or 0
	local resolvedHeight = tonumber(height) or 0
	local atlasInfo = GetAtlasInfoData(atlas)

	if atlasInfo and atlasInfo.width and atlasInfo.height and atlasInfo.height > 0 and resolvedHeight > 0 then
		local aspect = atlasInfo.width / atlasInfo.height
		resolvedWidth = math.max(1, math.floor((resolvedHeight * aspect) + 0.5))
	end

	return GetAtlasMarkup(atlas, resolvedWidth, resolvedHeight, tonumber(offsetX) or 0, tonumber(offsetY) or 0)
end

local function NormalizeProfessionQualityMarkup(text)
	if type(text) ~= "string" or text == "" or not text:find("|A:Professions%-ChatIcon%-Quality") then
		return text
	end

	return text:gsub("|A:(Professions%-ChatIcon%-Quality[^:|]*):(%d+):(%d+):?(-?%d*):?(-?%d*)[^|]*|a", function(atlas, width, height, offsetX, offsetY)
		return GetAspectCorrectAtlasMarkup(atlas, width, height, offsetX, offsetY)
	end)
end

local function StripProfessionQualityMarkup(text)
	if type(text) ~= "string" or text == "" or not text:find("|A:Professions%-ChatIcon%-Quality") then
		return text
	end

	text = text:gsub("|A:Professions%-ChatIcon%-Quality[^|]*|a", "")
	text = text:gsub("%s%s+", " ")
	text = text:gsub("%s+|h", "|h")
	text = text:gsub("|h%s+", "|h ")
	return strtrim(text)
end

local function GetRefreshDelay(reason)
	if reason == "show" or reason == "order-type" then
		return 0.01
	elseif reason == "sort" or reason == "filter" then
		return 0
	elseif reason == "pricing-db" or reason == "trade-skill-source" or (type(reason) == "string" and reason:match("^config:")) then
		return 0.1
	elseif reason == "request-success" then
		return REQUEST_SETTLE_DELAY
	elseif reason == "order-count" or reason == "rewards" or reason == "can-request" or reason == "request-timeout" then
		return 0.15
	elseif reason == "item-data" then
		return ITEM_DATA_REFRESH_DELAY
	end

	return 0.05
end

local function GetBorderAtlas(itemID, quality)
	local itemQuality = quality
	if itemQuality == nil and itemID then
		itemQuality = select(3, GetItemInfo(itemID))
	end
	return BORDER_BY_ITEM_QUALITY[itemQuality or 1] or BORDER_BY_ITEM_QUALITY[1]
end

local function GetCurrencyQuantity(currencyID)
	if not currencyID then
		return 0
	end
	local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
	return info and info.quantity or 0
end

local function GetCurrencyLink(currencyID, count)
	if not currencyID then
		return nil
	end
	return C_CurrencyInfo.GetCurrencyLink(currencyID, count or 1)
end

local function FormatConcentrationValue(value)
	if value == nil then
		return UNKNOWN
	elseif value == math.huge then
		return UNAVAILABLE
	end
	return tostring(value)
end

local function BuildConcentrationExtraLines(concentration)
	if type(concentration) ~= "table" then
		return nil
	end

	local lines = {}
	if concentration.lowestFillCost ~= nil then
		lines[#lines + 1] = LF("CONCENTRATION_LOWEST_MATERIALS_FORMAT", FormatConcentrationValue(concentration.lowestFillCost))
	end
	if concentration.ownedFillCost ~= nil then
		lines[#lines + 1] = LF("CONCENTRATION_WITH_OWNED_FORMAT", FormatConcentrationValue(concentration.ownedFillCost))
	end
	if concentration.bestOwnedCost ~= nil then
		lines[#lines + 1] = LF("CONCENTRATION_BEST_OWNED_FORMAT", FormatConcentrationValue(concentration.bestOwnedCost))
	end
	if concentration.bestMarketCost ~= nil then
		lines[#lines + 1] = LF("CONCENTRATION_BEST_MARKET_FORMAT", FormatConcentrationValue(concentration.bestMarketCost))
	end

	return #lines > 0 and lines or nil
end

local function CreateHeaderButton(parent, text, sortKey, width, xOffset)
	local button = CreateFrame("Button", nil, parent, "ColumnDisplayButtonShortTemplate")
	button:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, HEADER_TOP_OFFSET)
	button:SetSize(width, HEADER_HEIGHT)
	button:SetText(text)
	button.sortKey = sortKey
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	return button
end

local function CreateBlizzardFilterButton(parent)
	return CreateFrame("Button", nil, parent)
end

local function SetFallbackFilterButtonLabel(button, text)
	if not button then
		return
	end

	if button.fallbackText and type(button.fallbackText.SetText) == "function" then
		button.fallbackText:SetText(text)
	end
end

local function CreateFallbackFilterButtonVisuals(button, text)
	if not button or button.fallbackVisualsCreated then
		SetFallbackFilterButtonLabel(button, text)
		return
	end

	button.fallbackVisualsCreated = true
	button.fallbackBackground = button:CreateTexture(nil, "BACKGROUND")
	button.fallbackBackground:SetAllPoints()
	button.fallbackBackground:SetColorTexture(0.08, 0.08, 0.075, 0.95)
	button.fallbackBorder = button:CreateTexture(nil, "BORDER")
	button.fallbackBorder:SetAllPoints()
	button.fallbackBorder:SetColorTexture(0.32, 0.32, 0.3, 0.75)
	button.fallbackInset = button:CreateTexture(nil, "ARTWORK")
	button.fallbackInset:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
	button.fallbackInset:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
	button.fallbackInset:SetColorTexture(0.03, 0.03, 0.028, 0.95)
	button.fallbackText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.fallbackText:SetPoint("LEFT", button, "LEFT", 8, 0)
	button.fallbackText:SetPoint("RIGHT", button, "RIGHT", -17, 0)
	button.fallbackText:SetJustifyH("CENTER")
	button.fallbackArrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.fallbackArrow:SetPoint("RIGHT", button, "RIGHT", -7, 0)
	button.fallbackArrow:SetText(">")
	SetFallbackFilterButtonLabel(button, text)
end

local function SetFallbackFilterButtonVisualsShown(button, shown)
	if not button then
		return
	end

	for _, key in ipairs({ "fallbackBackground", "fallbackBorder", "fallbackInset", "fallbackText", "fallbackArrow" }) do
		local region = button[key]
		if region then
			region:SetShown(shown)
		end
	end
end

local function IsDescendantOf(frame, ancestor)
	local parent = frame
	while parent do
		if parent == ancestor then
			return true
		end
		parent = type(parent.GetParent) == "function" and parent:GetParent() or nil
	end

	return false
end

local function GetFrameLabelText(frame)
	if not frame then
		return nil
	end

	if type(frame.GetText) == "function" then
		local text = frame:GetText()
		if type(text) == "string" and text ~= "" then
			return text
		end
	end

	for _, key in ipairs({ "Text", "Label", "text" }) do
		local region = frame[key]
		if region and type(region.GetText) == "function" then
			local text = region:GetText()
			if type(text) == "string" and text ~= "" then
				return text
			end
		end
	end

	local regionCount = type(frame.GetRegions) == "function" and select("#", frame:GetRegions()) or 0
	for index = 1, regionCount do
		local region = select(index, frame:GetRegions())
		if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" and type(region.GetText) == "function" then
			local text = region:GetText()
			if type(text) == "string" and text ~= "" then
				return text
			end
		end
	end

	return nil
end

local function FindLeftRecipeFilterButton(root)
	local expectedText = (L and L.TOOLBAR_FILTER_BUTTON) or FILTER or "Filter"
	local bestButton
	local bestScore = math.huge
	local rootLeft = root and type(root.GetLeft) == "function" and root:GetLeft()
	local rootTop = root and type(root.GetTop) == "function" and root:GetTop()

	local function visit(frame, depth)
		if not frame or depth > 12 then
			return
		end

		if frame ~= root and not IsDescendantOf(frame, root) and type(frame.GetObjectType) == "function" then
			local objectType = frame:GetObjectType()
			local text = GetFrameLabelText(frame)
			if (objectType == "Button" or objectType == "DropdownButton") and text == expectedText then
				local width = type(frame.GetWidth) == "function" and frame:GetWidth() or 0
				local height = type(frame.GetHeight) == "function" and frame:GetHeight() or 0
				if width >= 40 and width <= 180 and height >= 14 and height <= 40 then
					local score = 1000
					local left = type(frame.GetLeft) == "function" and frame:GetLeft()
					local right = type(frame.GetRight) == "function" and frame:GetRight()
					local top = type(frame.GetTop) == "function" and frame:GetTop()
					if rootLeft and right and right <= rootLeft + 12 then
						score = score - 600 + math.abs((rootLeft or 0) - right)
					end
					if rootTop and top then
						score = score + math.abs(rootTop - top)
					end
					if score < bestScore then
						bestScore = score
						bestButton = frame
					end
				end
			end
		end

		local childCount = type(frame.GetChildren) == "function" and select("#", frame:GetChildren()) or 0
		for index = 1, childCount do
			visit(select(index, frame:GetChildren()), depth + 1)
		end
	end

	visit(ProfessionsFrame, 0)
	return bestButton
end

local function CopyRegionAnchors(source, target, sourceRoot, targetRoot, scaleX, scaleY)
	target:ClearAllPoints()
	local pointCount = type(source.GetNumPoints) == "function" and source:GetNumPoints() or 0
	if pointCount == 0 then
		target:SetAllPoints(targetRoot)
		return
	end

	for index = 1, pointCount do
		local point, relativeTo, relativePoint, xOffset, yOffset = source:GetPoint(index)
		if point then
			local relative = relativeTo == sourceRoot and targetRoot or targetRoot
			target:SetPoint(point, relative, relativePoint or point, (xOffset or 0) * scaleX, (yOffset or 0) * scaleY)
		end
	end
end

local function CopyTextureRegion(source, targetRoot, sourceRoot, scaleX, scaleY)
	local layer, sublevel = source:GetDrawLayer()
	local copy = targetRoot:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
	local atlas = type(source.GetAtlas) == "function" and source:GetAtlas()
	if atlas then
		copy:SetAtlas(atlas, false)
	else
		copy:SetTexture(source:GetTexture())
	end
	copy:SetTexCoord(source:GetTexCoord())
	copy:SetVertexColor(source:GetVertexColor())
	if type(source.IsDesaturated) == "function" and type(copy.SetDesaturated) == "function" then
		copy:SetDesaturated(source:IsDesaturated())
	end
	if type(source.GetBlendMode) == "function" and type(copy.SetBlendMode) == "function" then
		copy:SetBlendMode(source:GetBlendMode())
	end
	if type(source.GetAlpha) == "function" then
		copy:SetAlpha(source:GetAlpha())
	end
	local width, height = source:GetSize()
	copy:SetSize((width or 0) * scaleX, (height or 0) * scaleY)
	CopyRegionAnchors(source, copy, sourceRoot, targetRoot, scaleX, scaleY)
	return copy
end

local function CopyFontStringRegion(source, targetRoot, sourceRoot, scaleX, scaleY)
	local layer, sublevel = source:GetDrawLayer()
	local copy = targetRoot:CreateFontString(nil, layer or "ARTWORK", nil)
	local fontObject = type(source.GetFontObject) == "function" and source:GetFontObject()
	if fontObject then
		copy:SetFontObject(fontObject)
	end
	local font, size, flags = source:GetFont()
	if font and size then
		copy:SetFont(font, math.max(8, size * math.min(scaleX, scaleY)), flags)
	end
	copy:SetText(source:GetText() or "")
	copy:SetTextColor(source:GetTextColor())
	copy:SetJustifyH(source:GetJustifyH())
	copy:SetJustifyV(source:GetJustifyV())
	copy:SetShadowColor(source:GetShadowColor())
	local shadowX, shadowY = source:GetShadowOffset()
	copy:SetShadowOffset((shadowX or 0) * scaleX, (shadowY or 0) * scaleY)
	if type(source.GetAlpha) == "function" then
		copy:SetAlpha(source:GetAlpha())
	end
	local width, height = source:GetSize()
	copy:SetSize((width or 0) * scaleX, (height or 0) * scaleY)
	CopyRegionAnchors(source, copy, sourceRoot, targetRoot, scaleX, scaleY)
	return copy
end

local function CopyFilterFrameVisuals(sourceFrame, targetFrame, sourceRoot, targetRoot, scaleX, scaleY, visuals, depth)
	if not sourceFrame or not targetFrame or depth > 3 then
		return
	end

	local regionCount = type(sourceFrame.GetRegions) == "function" and select("#", sourceFrame:GetRegions()) or 0
	for index = 1, regionCount do
		local region = select(index, sourceFrame:GetRegions())
		if region and type(region.GetObjectType) == "function" and (type(region.IsShown) ~= "function" or region:IsShown()) then
			local objectType = region:GetObjectType()
			local copy
			if objectType == "Texture" then
				copy = CopyTextureRegion(region, targetFrame, sourceFrame, scaleX, scaleY)
			elseif objectType == "FontString" then
				copy = CopyFontStringRegion(region, targetFrame, sourceFrame, scaleX, scaleY)
			end
			if copy then
				visuals[#visuals + 1] = copy
			end
		end
	end

	local childCount = type(sourceFrame.GetChildren) == "function" and select("#", sourceFrame:GetChildren()) or 0
	for index = 1, childCount do
		local child = select(index, sourceFrame:GetChildren())
		if child and child:IsShown() and type(child.GetSize) == "function" then
			local childWidth, childHeight = child:GetSize()
			if childWidth and childHeight and childWidth > 0 and childHeight > 0 and childWidth <= 220 and childHeight <= 80 then
				local childCopy = CreateFrame("Frame", nil, targetFrame)
				childCopy:SetSize(childWidth * scaleX, childHeight * scaleY)
				CopyRegionAnchors(child, childCopy, sourceRoot, targetRoot, scaleX, scaleY)
				visuals[#visuals + 1] = childCopy
				CopyFilterFrameVisuals(child, childCopy, child, childCopy, scaleX, scaleY, visuals, depth + 1)
			end
		end
	end
end

local function ClearCopiedFilterButtonVisuals(button)
	if not button or not button.copiedFilterVisuals then
		return
	end

	for _, visual in ipairs(button.copiedFilterVisuals) do
		visual:Hide()
	end
	button.copiedFilterVisuals = nil
	button.copiedFilterVisualSource = nil
end

local function CopyFilterButtonVisuals(source, target)
	if not source or not target then
		return false
	end

	ClearCopiedFilterButtonVisuals(target)
	target.copiedFilterVisuals = {}

	local sourceWidth, sourceHeight = source:GetSize()
	local targetWidth, targetHeight = target:GetSize()
	local scaleX = sourceWidth and sourceWidth > 0 and targetWidth / sourceWidth or 1
	local scaleY = sourceHeight and sourceHeight > 0 and targetHeight / sourceHeight or 1

	CopyFilterFrameVisuals(source, target, source, target, scaleX, scaleY, target.copiedFilterVisuals, 0)

	target.copiedFilterVisualSource = source
	SetFallbackFilterButtonVisualsShown(target, false)
	return #target.copiedFilterVisuals > 0
end

local function NormalizeRecipeFilter(filterKey)
	if filterKey == RECIPE_FILTER_KNOWN or filterKey == RECIPE_FILTER_UNKNOWN then
		return filterKey
	end

	return RECIPE_FILTER_ALL
end

local function NormalizeConcentrationFilter(filterKey)
	if filterKey == CONCENTRATION_FILTER_NEEDS or filterKey == CONCENTRATION_FILTER_NONE then
		return filterKey
	end

	return CONCENTRATION_FILTER_ALL
end

local function NormalizeSortKey(sortKey)
	if sortKey == "order"
		or sortKey == "cost"
		or sortKey == "reward"
		or sortKey == "profit"
		or sortKey == "time" then
		return sortKey
	end

	return ns.DEFAULT_SORT_KEY or "profit"
end

local function DoesOrderNeedConcentration(orderData)
	local concentration = orderData and orderData.concentration
	return type(concentration) == "table"
		and (tonumber(concentration.currentCost) or 0) > 0
end

local function CreateFilterMenuToggle(parent, text, anchor, offsetY)
	local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	button:SetSize(22, 22)
	button:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, offsetY)
	button.text = button.text or button.Text
	if not button.text then
		button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	end
	if button.text then
		button.text:ClearAllPoints()
		button.text:SetPoint("LEFT", button, "RIGHT", 9, 0)
		button.text:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
		button.text:SetHeight(22)
		button.text:SetText(text)
		button.text:SetFontObject(GameFontHighlight)
		button.text:SetJustifyH("LEFT")
		button.text:SetTextColor(1, 1, 1)
	end
	if type(button.SetHitRectInsets) == "function" then
		button:SetHitRectInsets(0, -(FILTER_PANEL_WIDTH - 46), -2, -2)
	end
	return button
end

local function SetFilterMenuToggleChecked(button, checked)
	if not button then
		return
	end

	button:SetChecked(checked)
	if button.text then
		button.text:SetTextColor(1, 1, 1)
	end
end

local function GetCraftingReagentDescriptor(reagentInfo)
	if type(reagentInfo) ~= "table" then
		return nil
	end

	local reagent = type(reagentInfo.reagent) == "table" and reagentInfo.reagent or reagentInfo
	local itemID = reagent.itemID or reagentInfo.itemID
	local currencyID = reagent.currencyID or reagentInfo.currencyID
	if not itemID and not currencyID then
		return nil
	end

	return {
		itemID = itemID,
		currencyID = currencyID,
	}
end

local function AddMutableOperationReagent(target, reagentInfo, dataSlotIndex, quantity)
	local reagent = GetCraftingReagentDescriptor(reagentInfo)
	if not reagent then
		return
	end

	local entry = {
		reagent = reagent,
		quantity = quantity or reagentInfo.quantity or 0,
		dataSlotIndex = reagentInfo.dataSlotIndex or dataSlotIndex,
		itemID = reagent.itemID,
		currencyID = reagent.currencyID,
	}
	target[#target + 1] = entry
end

local function CopyOperationReagents(reagents)
	local copy = {}
	for index, reagent in ipairs(reagents or {}) do
		local descriptor = GetCraftingReagentDescriptor(reagent)
		if descriptor then
			copy[index] = {
				reagent = descriptor,
				itemID = descriptor.itemID,
				currencyID = descriptor.currencyID,
				quantity = reagent.quantity,
				dataSlotIndex = reagent.dataSlotIndex,
			}
		end
	end
	return copy
end

local function GetOrderQuality(order)
	return order.minQuality or 0
end

local function GetRecipeInfo(order)
	if not order.skillLineAbilityID then
		return nil
	end

	local skillLineRecipeInfo = C_TradeSkillUI.GetRecipeInfoForSkillLineAbility(order.skillLineAbilityID, 2)
	if not (skillLineRecipeInfo and skillLineRecipeInfo.recipeID and type(C_TradeSkillUI.GetRecipeInfo) == "function") then
		return skillLineRecipeInfo
	end

	local recipeInfo = securecall(C_TradeSkillUI.GetRecipeInfo, skillLineRecipeInfo.recipeID)
	if type(recipeInfo) ~= "table" then
		return skillLineRecipeInfo
	end

	local merged = {}
	for key, value in pairs(skillLineRecipeInfo) do
		merged[key] = value
	end
	for key, value in pairs(recipeInfo) do
		merged[key] = value
	end
	return merged
end

local function GetRecipeSchematic(recipeInfo)
	if not recipeInfo or not recipeInfo.recipeID then
		return nil
	end

	return C_TradeSkillUI.GetRecipeSchematic(recipeInfo.recipeID, false)
end

local function GetOperationInfo(orderData, reagents, applyConcentration)
	if not (orderData and orderData.recipeInfo and orderData.recipeInfo.recipeID and C_TradeSkillUI) then
		return nil
	end

	if orderData.orderID and type(C_TradeSkillUI.GetCraftingOperationInfoForOrder) == "function" then
		return securecall(
			C_TradeSkillUI.GetCraftingOperationInfoForOrder,
			orderData.recipeInfo.recipeID,
			reagents or {},
			orderData.orderID,
			not not applyConcentration
		)
	end

	if type(C_TradeSkillUI.GetCraftingOperationInfo) ~= "function" then
		return nil
	end

	return securecall(
		C_TradeSkillUI.GetCraftingOperationInfo,
		orderData.recipeInfo.recipeID,
		reagents or {},
		nil,
		not not applyConcentration
	)
end

local RECIPE_REQUIREMENT_LABELS = {
	[(Enum.RecipeRequirementType and Enum.RecipeRequirementType.SpellFocus) or 0] = L.RECIPE_REQ_SPELL_FOCUS,
	[(Enum.RecipeRequirementType and Enum.RecipeRequirementType.Totem) or 1] = L.RECIPE_REQ_TOTEM,
	[(Enum.RecipeRequirementType and Enum.RecipeRequirementType.Area) or 2] = L.RECIPE_REQ_AREA,
}

local function AddUniqueTooltipLine(lines, seen, text)
	if type(text) ~= "string" then
		return
	end

	text = strtrim(text)
	if text == "" or seen[text] then
		return
	end

	seen[text] = true
	lines[#lines + 1] = text
end

local function AddTooltipTextBlock(lines, seen, text)
	if type(text) ~= "string" or text == "" then
		return
	end

	text = text:gsub("|n", "\n")
	for line in text:gmatch("([^\n]+)") do
		AddUniqueTooltipLine(lines, seen, line)
	end
end

local function GetRecipeSourceText(recipeID)
	if not (recipeID and C_TradeSkillUI.GetRecipeSourceText) then
		return nil
	end

	return securecall(C_TradeSkillUI.GetRecipeSourceText, recipeID)
end

local function BuildUnknownRecipeTooltip(recipeInfo)
	if not (recipeInfo and recipeInfo.recipeID) then
		return nil
	end

	local lines = {}
	local seen = {}
	local professionName = recipeInfo.skillLineAbilityID
		and C_TradeSkillUI.GetProfessionNameForSkillLineAbility
		and securecall(C_TradeSkillUI.GetProfessionNameForSkillLineAbility, recipeInfo.skillLineAbilityID)
	local sourceText = GetRecipeSourceText(recipeInfo.recipeID)
	local requirements = C_TradeSkillUI.GetRecipeRequirements and securecall(C_TradeSkillUI.GetRecipeRequirements, recipeInfo.recipeID)

	AddUniqueTooltipLine(lines, seen, ("|cffffd100%s|r"):format(L.UNKNOWN_RECIPE_HEADER))
	if professionName then
		AddUniqueTooltipLine(lines, seen, LF("UNKNOWN_RECIPE_PROFESSION_FORMAT", professionName))
	end

	if sourceText then
		AddUniqueTooltipLine(lines, seen, ("|cffffd100%s|r"):format(L.UNKNOWN_RECIPE_LEARN_HEADER))
		AddTooltipTextBlock(lines, seen, sourceText)
	end

	if type(requirements) == "table" and #requirements > 0 then
		AddUniqueTooltipLine(lines, seen, ("|cffffd100%s|r"):format(L.UNKNOWN_RECIPE_REQUIREMENTS_HEADER))
		for _, requirement in ipairs(requirements) do
			local requirementName = requirement and requirement.name
			if requirementName and requirementName ~= "" then
				local label = RECIPE_REQUIREMENT_LABELS[requirement.type] or L.RECIPE_REQ_GENERIC
				local suffix = requirement.met and "" or L.RECIPE_REQ_NOT_MET_SUFFIX
				AddUniqueTooltipLine(lines, seen, LF("UNKNOWN_RECIPE_REQUIREMENT_FORMAT", label, requirementName, suffix))
			end
		end
	end

	if #lines <= 1 then
		AddUniqueTooltipLine(lines, seen, L.UNKNOWN_RECIPE_NO_SOURCE)
	end

	return lines
end

local function AppendTooltipLines(target, source)
	if type(source) ~= "table" then
		return target
	end

	target = target or {}
	for _, line in ipairs(source) do
		target[#target + 1] = line
	end
	return target
end

local function GetRecipeInfoByID(recipeID)
	if not (recipeID and type(C_TradeSkillUI.GetRecipeInfo) == "function") then
		return nil
	end

	local info = securecall(C_TradeSkillUI.GetRecipeInfo, recipeID)
	return type(info) == "table" and info or nil
end

local function IsRecipeKnown(recipeInfo)
	if type(recipeInfo) ~= "table" then
		return false
	end

	local info = recipeInfo.recipeID and GetRecipeInfoByID(recipeInfo.recipeID) or recipeInfo
	if info and info.learned then
		return true
	end

	local seen = {}
	while info and info.previousRecipeID and not seen[info.previousRecipeID] do
		seen[info.recipeID or info.previousRecipeID] = true
		info = GetRecipeInfoByID(info.previousRecipeID)
		if info and info.learned then
			return true
		end
	end

	while info and info.nextRecipeID and not seen[info.nextRecipeID] do
		seen[info.recipeID or info.nextRecipeID] = true
		info = GetRecipeInfoByID(info.nextRecipeID)
		if info and info.learned then
			return true
		end
	end

	return false
end

local function GetMinimumRequiredQuality(recipeInfo)
	local qualityIDs = recipeInfo and recipeInfo.qualityIDs
	if type(qualityIDs) == "table" then
		local minimumQuality
		for qualityIndex, qualityID in pairs(qualityIDs) do
			if type(qualityIndex) == "number" and qualityIndex > 0 and qualityID ~= nil then
				minimumQuality = minimumQuality and math.min(minimumQuality, qualityIndex) or qualityIndex
			end
		end

		if minimumQuality then
			return minimumQuality
		end
	end

	return 0
end

local function MeetsRequiredQuality(operationInfo, requiredQuality)
	if requiredQuality <= 0 then
		return true
	end

	return operationInfo and (operationInfo.craftingQuality or 0) >= requiredQuality
end

local function CanReachRequiredQuality(operationInfo, requiredQuality)
	if MeetsRequiredQuality(operationInfo, requiredQuality) then
		return true
	end

	if not (operationInfo and requiredQuality > 0) then
		return false
	end

	local currentQuality = operationInfo.craftingQuality or 0
	return currentQuality + 1 >= requiredQuality and operationInfo.concentrationCost ~= nil
end

local function SortFillOptions(strategy, left, right)
	if strategy == "lowest" then
		local leftQuality = left.reagentQuality or 0
		local rightQuality = right.reagentQuality or 0
		if leftQuality ~= rightQuality then
			return leftQuality < rightQuality
		end

		local leftRank = GetMarketPreferenceRank(left.priceState, left.unitPrice)
		local rightRank = GetMarketPreferenceRank(right.priceState, right.unitPrice)
		if leftRank ~= rightRank then
			return leftRank < rightRank
		end

		local leftPrice = left.unitPrice or math.huge
		local rightPrice = right.unitPrice or math.huge
		if leftPrice ~= rightPrice then
			return leftPrice < rightPrice
		end

		return (left.score or 0) < (right.score or 0)
	elseif strategy == "best" then
		if (left.score or 0) ~= (right.score or 0) then
			return (left.score or 0) > (right.score or 0)
		end

		local leftRank = GetMarketPreferenceRank(left.priceState, left.unitPrice)
		local rightRank = GetMarketPreferenceRank(right.priceState, right.unitPrice)
		if leftRank ~= rightRank then
			return leftRank < rightRank
		end

		local leftPrice = left.unitPrice or math.huge
		local rightPrice = right.unitPrice or math.huge
		if leftPrice ~= rightPrice then
			return leftPrice < rightPrice
		end

		return (left.reagentQuality or 0) > (right.reagentQuality or 0)
	end

	local leftRank = GetMarketPreferenceRank(left.priceState, left.unitPrice)
	local rightRank = GetMarketPreferenceRank(right.priceState, right.unitPrice)
	if leftRank ~= rightRank then
		return leftRank < rightRank
	end

	local leftPrice = left.unitPrice or math.huge
	local rightPrice = right.unitPrice or math.huge
	if leftPrice ~= rightPrice then
		return leftPrice < rightPrice
	end

	return (left.score or 0) > (right.score or 0)
end

local function BuildStrategizedOperation(orderData, inventoryOnly, strategy)
	if not (orderData.recipeInfo and orderData.recipeInfo.recipeID) then
		return nil
	end

	local workingReagents = CopyOperationReagents(orderData.operationReagents)
	local inventory = {}
	local includeOptional = strategy == "best"

	for _, slotData in ipairs(orderData.mutableSlots or {}) do
		if slotData.dataSlotType == MUTABLE_SLOT_TYPE and not slotData.covered and not slotData.locked and (slotData.required or includeOptional) then
			local remaining = slotData.quantityRequired
			local options = {}

			for index, option in ipairs(slotData.options) do
				options[index] = option
				if inventoryOnly and option.itemID and inventory[option.itemID] == nil then
					inventory[option.itemID] = Util.GetItemCount(option.itemID)
				end
			end

			table.sort(options, function(left, right)
				return SortFillOptions(strategy, left, right)
			end)

			for _, option in ipairs(options) do
				local available = inventoryOnly and (inventory[option.itemID] or 0) or remaining
				if available > 0 then
					local quantity = math.min(remaining, available)
					AddMutableOperationReagent(workingReagents, option, slotData.dataSlotIndex, quantity)
					remaining = remaining - quantity
					if inventoryOnly then
						inventory[option.itemID] = available - quantity
					end
					if remaining == 0 then
						break
					end
				end
			end
		end
	end

	return GetOperationInfo(orderData, workingReagents, false), workingReagents
end

local function GetComparableUnitPrice(option)
	local unitPrice = option and option.unitPrice
	if type(unitPrice) == "number" and unitPrice > 0 then
		return unitPrice
	end

	return math.huge
end

local function CompareLowestMaterialOptions(left, right)
	local leftQuality = left and left.reagentQuality or 0
	local rightQuality = right and right.reagentQuality or 0
	if leftQuality ~= rightQuality then
		return leftQuality < rightQuality
	end

	local leftRank = GetMarketPreferenceRank(left and left.priceState, left and left.unitPrice)
	local rightRank = GetMarketPreferenceRank(right and right.priceState, right and right.unitPrice)
	if leftRank ~= rightRank then
		return leftRank < rightRank
	end

	local leftPrice = GetComparableUnitPrice(left)
	local rightPrice = GetComparableUnitPrice(right)
	if leftPrice ~= rightPrice then
		return leftPrice < rightPrice
	end

	if (left.score or 0) ~= (right.score or 0) then
		return (left.score or 0) > (right.score or 0)
	end

	return (left.itemID or 0) < (right.itemID or 0)
end

local function BuildMaterialEntry(slotData, option, quantity)
	if not (slotData and option and quantity and quantity > 0) then
		return nil
	end

	local totalPrice = type(option.unitPrice) == "number" and option.unitPrice > 0 and option.unitPrice * quantity or nil
	local availableTotal = option.ownedCount or 0
	return {
		slotData = slotData,
		option = option,
		quantity = quantity,
		required = slotData.required,
		availableTotal = availableTotal,
		selectedQualityOwnedCount = option.ownedCount or 0,
		otherQualityOwnedCount = option.otherQualityOwnedCount or 0,
		totalOwnedCount = option.totalOwnedCount or option.ownedCount or 0,
		shortage = math.max(0, quantity - availableTotal),
		totalPrice = totalPrice,
		priceState = option.priceState,
		marketValueExcluded = IsExcludedFromMarketValue(option.priceState),
	}
end

local EMPTY_LIST = {}

local function GetMaterialPlanEntries(orderData)
	local materialPlan = orderData and orderData.materialPlan
	return materialPlan and materialPlan.entries or EMPTY_LIST
end

local function CreatePendingSlotAllocation(slotAllocations, slotIndex, itemID, currencyID, quantity)
	if not slotIndex or not quantity or quantity <= 0 then
		return
	end

	local bucket = slotAllocations[slotIndex]
	if not bucket then
		bucket = {}
		slotAllocations[slotIndex] = bucket
	end

	for _, allocation in ipairs(bucket) do
		if allocation.itemID == itemID and allocation.currencyID == currencyID then
			allocation.quantity = (allocation.quantity or 0) + quantity
			return
		end
	end

	bucket[#bucket + 1] = {
		itemID = itemID,
		currencyID = currencyID,
		quantity = quantity,
	}
end

local function SelectDefaultSlotOption(slotData)
	local options = {}
	for index, option in ipairs(slotData and slotData.options or {}) do
		options[index] = option
	end

	if #options == 0 then
		return nil
	end

	table.sort(options, CompareLowestMaterialOptions)
	return options[1]
end

local function CreateMaterialVariant(slotData, components)
	local variant = {
		slotData = slotData,
		entries = {},
		qualityWeight = 0,
		scoreTotal = 0,
		marketCost = 0,
		marketCostKnown = true,
		excludedEntryCount = 0,
	}

	for _, component in ipairs(components or {}) do
		local entry = BuildMaterialEntry(slotData, component.option, component.quantity)
		if entry then
			variant.entries[#variant.entries + 1] = entry
			variant.qualityWeight = variant.qualityWeight
				+ ((QUALITY_WEIGHT_BASE ^ math.max(0, entry.option.reagentQuality or 0)) * (entry.quantity or 0))
			variant.scoreTotal = variant.scoreTotal + ((entry.option.score or 0) * (entry.quantity or 0))
			if entry.marketValueExcluded then
				variant.excludedEntryCount = variant.excludedEntryCount + 1
			elseif entry.totalPrice then
				variant.marketCost = variant.marketCost + entry.totalPrice
			else
				variant.marketCostKnown = false
			end
		end
	end

	return variant
end

local function CompareMaterialPlanPreference(left, right)
	local leftWeight = left and left.qualityWeight or math.huge
	local rightWeight = right and right.qualityWeight or math.huge
	if leftWeight ~= rightWeight then
		return leftWeight < rightWeight
	end

	if (left.excludedEntryCount or 0) ~= (right.excludedEntryCount or 0) then
		return (left.excludedEntryCount or 0) < (right.excludedEntryCount or 0)
	end

	if left.marketCostKnown ~= right.marketCostKnown then
		return left.marketCostKnown
	end

	local leftCost = left.marketCost or math.huge
	local rightCost = right.marketCost or math.huge
	if leftCost ~= rightCost then
		return leftCost < rightCost
	end

	if (left.scoreTotal or 0) ~= (right.scoreTotal or 0) then
		return (left.scoreTotal or 0) > (right.scoreTotal or 0)
	end

	return false
end

local function BuildSlotFillVariants(slotData, allowEmpty)
	local variants = {}
	local options = {}

	for index, option in ipairs(slotData.options or {}) do
		options[index] = option
	end

	table.sort(options, CompareLowestMaterialOptions)

	if allowEmpty then
		variants[#variants + 1] = CreateMaterialVariant(slotData)
	end

	if #options == 0 then
		return variants
	end

	local components = {}
	local function Visit(optionIndex, remaining)
		local option = options[optionIndex]
		if remaining == 0 then
			variants[#variants + 1] = CreateMaterialVariant(slotData, components)
			return
		end

		if not option then
			return
		end

		if optionIndex == #options then
			components[#components + 1] = {
				option = option,
				quantity = remaining,
			}
			variants[#variants + 1] = CreateMaterialVariant(slotData, components)
			components[#components] = nil
			return
		end

		for quantity = remaining, 0, -1 do
			if quantity > 0 then
				components[#components + 1] = {
					option = option,
					quantity = quantity,
				}
			end

			Visit(optionIndex + 1, remaining - quantity)

			if quantity > 0 then
				components[#components] = nil
			end
		end
	end

	Visit(1, slotData.quantityRequired or 0)
	table.sort(variants, CompareMaterialPlanPreference)
	return variants
end

local function ShouldConsiderOptionalSlot(slotData)
	if not slotData then
		return false
	end

	if slotData.required then
		return true
	end

	for _, option in ipairs(slotData.options or {}) do
		if (option.score or 0) > 0 then
			return true
		end
	end

	return false
end

local function BuildPlannedMaterialCombination(orderData, selections, missingRequiredSlots)
	local workingReagents = CopyOperationReagents(orderData.operationReagents)
	local entries = {}
	local qualityWeight = 0
	local scoreTotal = 0
	local marketCost = 0
	local marketCostKnown = true
	local excludedEntryCount = 0
	local requiredMissing = (missingRequiredSlots or 0) + (orderData.staticMissingRequiredSlots or 0)

	for _, entry in ipairs(orderData.staticMaterialEntries or {}) do
		entries[#entries + 1] = entry
		if entry.marketValueExcluded then
			excludedEntryCount = excludedEntryCount + 1
		elseif entry.totalPrice then
			marketCost = marketCost + entry.totalPrice
		else
			marketCostKnown = false
		end
	end

	for _, selection in ipairs(selections or {}) do
		local hasEntries = false
		for _, entry in ipairs(selection.entries or {}) do
			hasEntries = true
			entries[#entries + 1] = entry
			AddMutableOperationReagent(workingReagents, entry.option, entry.slotData.dataSlotIndex, entry.quantity)
			qualityWeight = qualityWeight
				+ ((QUALITY_WEIGHT_BASE ^ math.max(0, entry.option.reagentQuality or 0)) * (entry.quantity or 0))
			scoreTotal = scoreTotal + ((entry.option.score or 0) * (entry.quantity or 0))
			if entry.marketValueExcluded then
				excludedEntryCount = excludedEntryCount + 1
			elseif entry.totalPrice then
				marketCost = marketCost + entry.totalPrice
			else
				marketCostKnown = false
			end
		end

		if selection.slotData and selection.slotData.required and not hasEntries then
			requiredMissing = requiredMissing + 1
		end
	end

	return {
		entries = entries,
		reagents = workingReagents,
		operationInfo = requiredMissing == 0 and GetOperationInfo(orderData, workingReagents, false) or nil,
		missingRequiredSlots = requiredMissing,
		qualityWeight = qualityWeight,
		scoreTotal = scoreTotal,
		marketCost = marketCost,
		marketCostKnown = marketCostKnown,
		excludedEntryCount = excludedEntryCount,
	}
end

local function BuildLowestMaterialPlan(orderData)
	local selections = {}
	local missingRequiredSlots = 0

	for _, slotData in ipairs(orderData.mutableSlots or {}) do
		if slotData.dataSlotType == MUTABLE_SLOT_TYPE and not slotData.covered and not slotData.locked and slotData.required then
			local variants = BuildSlotFillVariants(slotData, false)
			if variants[1] then
				selections[#selections + 1] = variants[1]
			else
				missingRequiredSlots = missingRequiredSlots + 1
			end
		end
	end

	return BuildPlannedMaterialCombination(orderData, selections, missingRequiredSlots)
end

local function FindReachableMaterialPlan(orderData, requiredQuality)
	local planningSlots = {}
	local missingRequiredSlots = 0

	for _, slotData in ipairs(orderData.mutableSlots or {}) do
		if slotData.dataSlotType == MUTABLE_SLOT_TYPE
			and not slotData.covered
			and not slotData.locked
			and ShouldConsiderOptionalSlot(slotData) then
			local variants = BuildSlotFillVariants(slotData, not slotData.required)
			if variants[1] then
				planningSlots[#planningSlots + 1] = {
					slotData = slotData,
					variants = variants,
				}
			elseif slotData.required then
				missingRequiredSlots = missingRequiredSlots + 1
			end
		end
	end

	if missingRequiredSlots > 0 then
		return nil
	end

	if #planningSlots == 0 then
		local fallback = BuildPlannedMaterialCombination(orderData, {}, 0)
		return CanReachRequiredQuality(fallback.operationInfo, requiredQuality) and fallback or nil
	end

	local suffixMinQualityWeight = {
		[#planningSlots + 1] = 0,
	}

	for index = #planningSlots, 1, -1 do
		local firstVariant = planningSlots[index].variants[1]
		suffixMinQualityWeight[index] = suffixMinQualityWeight[index + 1] + (firstVariant and firstVariant.qualityWeight or 0)
	end

	local bestPlan
	local selections = {}

	local function Search(slotIndex, currentQualityWeight)
		if slotIndex > #planningSlots then
			local candidate = BuildPlannedMaterialCombination(orderData, selections, 0)
			if CanReachRequiredQuality(candidate.operationInfo, requiredQuality)
				and (not bestPlan or CompareMaterialPlanPreference(candidate, bestPlan)) then
				bestPlan = candidate
			end
			return
		end

		if bestPlan and currentQualityWeight + suffixMinQualityWeight[slotIndex] > (bestPlan.qualityWeight or math.huge) then
			return
		end

		for _, variant in ipairs(planningSlots[slotIndex].variants) do
			local candidateWeight = currentQualityWeight + (variant.qualityWeight or 0)
			if bestPlan
				and candidateWeight + suffixMinQualityWeight[slotIndex + 1] > (bestPlan.qualityWeight or math.huge) then
				break
			end

			selections[#selections + 1] = variant
			Search(slotIndex + 1, candidateWeight)
			selections[#selections] = nil
		end
	end

	Search(1, 0)
	return bestPlan
end

local function EvaluateQualityRequirement(orderData)
	local requiredQuality = orderData.requiredQuality or 0
	local minimumQuality = GetMinimumRequiredQuality(orderData.recipeInfo)
	local lowestPlan = BuildLowestMaterialPlan(orderData)
	local lowestOperation = lowestPlan and lowestPlan.operationInfo
	if requiredQuality <= minimumQuality then
		return {
			showInList = false,
			minimumQuality = minimumQuality,
			requiredQuality = requiredQuality,
			lowestPlan = lowestPlan,
			activePlan = lowestPlan,
		}
	end

	if MeetsRequiredQuality(lowestOperation, requiredQuality) then
		return {
			showInList = true,
			minimumQuality = minimumQuality,
			requiredQuality = requiredQuality,
			state = "green",
			lowestPlan = lowestPlan,
			reachablePlan = lowestPlan,
			activePlan = lowestPlan,
		}
	end

	if CanReachRequiredQuality(lowestOperation, requiredQuality) then
		return {
			showInList = true,
			minimumQuality = minimumQuality,
			requiredQuality = requiredQuality,
			state = "amber",
			lowestPlan = lowestPlan,
			reachablePlan = lowestPlan,
			activePlan = lowestPlan,
		}
	end

	local reachablePlan = FindReachableMaterialPlan(orderData, requiredQuality)
	if reachablePlan then
		return {
			showInList = true,
			minimumQuality = minimumQuality,
			requiredQuality = requiredQuality,
			state = "amber",
			lowestPlan = lowestPlan,
			reachablePlan = reachablePlan,
			activePlan = reachablePlan,
		}
	end

	return {
		showInList = true,
		minimumQuality = minimumQuality,
		requiredQuality = requiredQuality,
		state = "none",
		lowestPlan = lowestPlan,
		activePlan = lowestPlan,
	}
end

local function BuildQualityTooltip(orderData)
	local qualityRequirement = orderData.qualityRequirement
	if not (qualityRequirement and qualityRequirement.showInList) then
		return nil
	end

	local lines = {
		LF("QUALITY_TOOLTIP_REQUESTED_FORMAT", qualityRequirement.requiredQuality or 0),
	}

	if qualityRequirement.state == "green" then
		lines[#lines + 1] = L.QUALITY_TOOLTIP_GREEN
	elseif qualityRequirement.state == "amber" then
		local reachableOperation = qualityRequirement.reachablePlan and qualityRequirement.reachablePlan.operationInfo
		if qualityRequirement.reachablePlan == qualityRequirement.lowestPlan then
			lines[#lines + 1] = L.QUALITY_TOOLTIP_AMBER_CONCENTRATION
		elseif MeetsRequiredQuality(reachableOperation, orderData.requiredQuality or 0) then
			lines[#lines + 1] = L.QUALITY_TOOLTIP_AMBER_STRONGER_MATERIALS
		else
			lines[#lines + 1] = L.QUALITY_TOOLTIP_AMBER_STRONGER_OR_CONCENTRATION
		end
	else
		lines[#lines + 1] = L.QUALITY_TOOLTIP_UNREACHABLE
	end

	return lines
end

local function BuildProductTooltipLines(orderData)
	return BuildQualityTooltip(orderData)
end

local function CompactQualityRequirement(qualityRequirement)
	if not qualityRequirement then
		return nil
	end

	return {
		showInList = qualityRequirement.showInList,
		minimumQuality = qualityRequirement.minimumQuality,
		requiredQuality = qualityRequirement.requiredQuality,
		state = qualityRequirement.state,
	}
end

local function GetQualityIndicatorText(orderData)
	local qualityRequirement = orderData.qualityRequirement
	if not (qualityRequirement and qualityRequirement.showInList) then
		return ""
	end

	if qualityRequirement.state == "green" then
		return " " .. GetAtlasMarkup(QUALITY_TICK_GREEN, 14, 14, 0, -1)
	elseif qualityRequirement.state == "amber" then
		return " " .. GetAtlasMarkup(QUALITY_TICK_AMBER, 14, 14, 0, -1)
	end

	return ""
end

local function GetOutputPresentation(order, recipeInfo)
	local qualityIndex = GetOrderQuality(order)
	local minimumQuality = GetMinimumRequiredQuality(recipeInfo)
	local itemID = order.itemID
	local itemLink

	if recipeInfo and recipeInfo.recipeID and qualityIndex > 0 and recipeInfo.qualityIDs then
		local operationReagents = {}
		for _, suppliedReagent in ipairs(order.reagents or {}) do
			if suppliedReagent.reagentInfo then
				operationReagents[#operationReagents + 1] = suppliedReagent.reagentInfo
			end
		end

		local output = C_TradeSkillUI.GetRecipeOutputItemData(
			recipeInfo.recipeID,
			operationReagents,
			nil,
			recipeInfo.qualityIDs[qualityIndex]
		)

		if output then
			itemID = output.itemID or itemID
			itemLink = output.hyperlink or Util.GetItemLink(itemID)
		end
	end

	if not itemLink and itemID then
		itemLink = Util.GetItemLink(itemID)
	end

	local label = itemLink and itemLink:gsub("|h%[(.*)%]|h", "|h%1|h") or C_Spell.GetSpellName(order.spellID or 0) or UNKNOWN
	if qualityIndex > minimumQuality then
		label = NormalizeProfessionQualityMarkup(label)
	else
		label = StripProfessionQualityMarkup(label)
	end
	local icon = itemID and select(5, C_Item.GetItemInfoInstant(itemID)) or C_Spell.GetSpellTexture(order.spellID or 0) or 134400

	return {
		itemID = itemID,
		itemLink = itemLink,
		icon = icon,
		label = label,
		plainLabel = C_StringUtil.StripHyperlinks(label),
	}
end

local function EvaluateRewardValue(order)
	local rewardGold = math.max(0, (order.tipAmount or 0) - (order.consortiumCut or 0))
	local rewardItemValue = 0
	local rewardIcons = {}
	local rewardKnowledge = 0
	local rewardAcuity = 0
	local pricedRewardCount = 0
	local marketableRewardCount = 0
	local excludedRewardCount = 0

	for _, reward in ipairs(order.npcOrderRewards or {}) do
		local count = reward.count or reward.quantity or 1
		local itemLink = reward.itemLink
		local itemID = itemLink and tonumber(itemLink:match("item:(%d+)")) or nil
		local currencyID = reward.currencyType
		local iconTexture
		local borderAtlas
		local unitPrice
		local totalPrice
		local priceState
		local knowledgeContribution = 0
		local extraLines
		local itemName

		if itemLink or itemID then
			local priceInfo = Pricing:GetPriceInfo(itemLink or itemID, count)
			unitPrice = priceInfo.unitPrice
			totalPrice = priceInfo.totalPrice
			priceState = priceInfo.state
			if priceInfo.isMarketable == false then
				excludedRewardCount = excludedRewardCount + 1
			else
				marketableRewardCount = marketableRewardCount + 1
				if totalPrice then
					pricedRewardCount = pricedRewardCount + 1
					rewardItemValue = rewardItemValue + totalPrice
				end
			end

			local instantID = itemID or tonumber((itemLink or ""):match("item:(%d+)"))
			itemID = instantID or itemID
			if instantID then
				itemLink = LinkHasDisplayName(itemLink) and itemLink or Util.GetItemLink(instantID) or itemLink
				itemName = Util.GetItemName(instantID) or reward.name or reward.itemName
			end
			iconTexture = instantID and select(5, C_Item.GetItemInfoInstant(instantID))
			borderAtlas = GetBorderAtlas(instantID)

			if instantID then
				local acuityCount = instantID == ACUITY_ITEM_ID and count or 0
				knowledgeContribution = (REWARD_KNOWLEDGE_ITEMS[instantID] or 0) * count
				rewardKnowledge = rewardKnowledge + knowledgeContribution
				rewardAcuity = rewardAcuity + acuityCount
				if knowledgeContribution > 0 then
					extraLines = {
						LF("KNOWLEDGE_REWARD_FORMAT", knowledgeContribution),
					}
				end
			end
		elseif currencyID then
			local basic = C_CurrencyInfo.GetBasicCurrencyInfo(currencyID, count)
			iconTexture = basic and basic.icon
			borderAtlas = GetBorderAtlas(nil, basic and basic.quality)
			priceState = "not_marketable"
			if ACUITY_CURRENCY_IDS[currencyID] then
				rewardAcuity = rewardAcuity + count
			end
		end

		rewardIcons[#rewardIcons + 1] = {
			itemID = itemID,
			itemLink = itemLink,
			name = itemName,
			currencyID = currencyID,
			count = count,
			icon = iconTexture,
			borderAtlas = borderAtlas,
			unitPrice = unitPrice,
			totalPrice = totalPrice,
			priceState = priceState,
			knowledgeContribution = knowledgeContribution,
			favoriteBadge = knowledgeContribution > 1,
			extraLines = extraLines,
		}
	end

	return {
		gold = rewardGold,
		itemValue = rewardItemValue,
		totalValue = rewardGold + rewardItemValue,
		hasPriceData = rewardItemValue > 0,
		isPriceComplete = marketableRewardCount > 0 and pricedRewardCount == marketableRewardCount,
		totalValueKnown = rewardGold > 0 or marketableRewardCount == 0 or pricedRewardCount > 0,
		totalValueComplete = marketableRewardCount == 0 or pricedRewardCount == marketableRewardCount,
		marketableItemCount = marketableRewardCount,
		excludedItemCount = excludedRewardCount,
		icons = rewardIcons,
		knowledge = rewardKnowledge,
		acuity = rewardAcuity,
	}
end

local function GetRewardTooltipLabel(rewardIcon)
	if rewardIcon.currencyID then
		return GetCurrencyLink(rewardIcon.currencyID, rewardIcon.count)
			or (C_CurrencyInfo.GetBasicCurrencyInfo(rewardIcon.currencyID, rewardIcon.count) or {}).name
			or UNKNOWN
	end

	if LinkHasDisplayName(rewardIcon.itemLink) then
		return rewardIcon.itemLink
	end

	local resolvedLink = rewardIcon.itemID and Util.GetItemLink(rewardIcon.itemID)
	if LinkHasDisplayName(resolvedLink) then
		return resolvedLink
	end

	local itemName = rewardIcon.name or Util.GetItemName(rewardIcon.itemID)
	if itemName and itemName ~= "" then
		return rewardIcon.count and rewardIcon.count > 1 and FormatItemCountLabel(rewardIcon.count, itemName) or itemName
	end

	return rewardIcon.itemID and LF("ITEM_FALLBACK_FORMAT", rewardIcon.itemID) or UNKNOWN
end

local function EvaluateProfit(orderData)
	local reward = orderData and orderData.reward or {}
	local cost = orderData and orderData.materialCost or 0
	local materialEntryCount = #GetMaterialPlanEntries(orderData)
	local hasCostData = orderData and (materialEntryCount == 0 or orderData.materialCostKnown)
	local hasRewardData = reward.totalValueKnown

	if not (hasCostData and hasRewardData) then
		return nil, false, false
	end

	local costComplete = materialEntryCount == 0 or orderData.materialCostComplete
	local rewardComplete = reward.totalValueComplete
	return (reward.totalValue or 0) - cost, true, costComplete and rewardComplete
end

local function GetLockedStatus(slot, recipeInfo)
	if not (slot and slot.slotInfo and recipeInfo and recipeInfo.recipeID and recipeInfo.skillLineAbilityID) then
		return false, nil
	end

	return C_TradeSkillUI.GetReagentSlotStatus(slot.slotInfo.mcrSlotID, recipeInfo.recipeID, recipeInfo.skillLineAbilityID)
end

local function CreateOperationContext(orderData, suppliedReagents)
	local reagents = {}
	for _, suppliedReagent in ipairs(suppliedReagents or EMPTY_LIST) do
		local reagentInfo = suppliedReagent.reagentInfo
		local slotData = suppliedReagent.slotIndex and orderData.slotMap[suppliedReagent.slotIndex]
		if reagentInfo and slotData and slotData.dataSlotType == MUTABLE_SLOT_TYPE then
			AddMutableOperationReagent(reagents, reagentInfo, slotData.dataSlotIndex, reagentInfo.quantity)
		end
	end

	local operationInfo = GetOperationInfo(orderData, reagents, false)
	return reagents, operationInfo
end

local function ScoreMutableOption(orderData, slotData, option, baseReagents, baseOperation)
	if not (slotData and slotData.dataSlotType == MUTABLE_SLOT_TYPE and option.itemID and baseOperation) then
		return 0
	end

	local testReagents = CopyOperationReagents(baseReagents)
	AddMutableOperationReagent(testReagents, option, slotData.dataSlotIndex, slotData.quantityRequired)

	local operationInfo = GetOperationInfo(orderData, testReagents, false)
	if not operationInfo then
		return 0
	end

	local qualityDelta = ((operationInfo.craftingQuality or 0) - (baseOperation.craftingQuality or 0)) * 100000
	local concentrationDelta = (baseOperation.concentrationCost or 0) - (operationInfo.concentrationCost or 0)
	return qualityDelta + concentrationDelta
end

local function SortSlotOptions(left, right)
	if (left.score or 0) ~= (right.score or 0) then
		return (left.score or 0) > (right.score or 0)
	end

	local leftRank = GetMarketPreferenceRank(left.priceState, left.unitPrice)
	local rightRank = GetMarketPreferenceRank(right.priceState, right.unitPrice)
	if leftRank ~= rightRank then
		return leftRank < rightRank
	end

	local leftPrice = left.unitPrice or math.huge
	local rightPrice = right.unitPrice or math.huge
	if leftPrice ~= rightPrice then
		return leftPrice < rightPrice
	end

	if (left.ownedCount or 0) ~= (right.ownedCount or 0) then
		return (left.ownedCount or 0) > (right.ownedCount or 0)
	end

	return (left.reagentQuality or 0) > (right.reagentQuality or 0)
end

local function EstimateConcentrationCost(orderData, inventoryOnly, preferHighScore)
	local operationInfo = BuildStrategizedOperation(orderData, inventoryOnly, preferHighScore and "best" or "lowest")
	if not operationInfo then
		return nil
	end

	if orderData.requiredQuality > 0 and (operationInfo.craftingQuality or 0) < orderData.requiredQuality then
		return math.huge, operationInfo
	end

	return operationInfo.concentrationCost or 0, operationInfo
end

local function BuildRequiredReagents(orderData, reagentSlotSchematics, suppliedReagents)
	local coveredSlots = {}
	for _, suppliedReagent in ipairs(suppliedReagents or EMPTY_LIST) do
		if suppliedReagent.slotIndex then
			coveredSlots[suppliedReagent.slotIndex] = suppliedReagent.reagentInfo
		end
	end

	local requiredReagents = {}
	local mutableSlots = {}
	local staticMaterialEntries = {}
	local staticMissingRequiredSlots = 0
	local materialCost = 0
	local pricedSlotCount = 0
	local marketableSlotCount = 0
	local excludedSlotCount = 0
	local slotMap = {}

	for _, slot in ipairs(reagentSlotSchematics or EMPTY_LIST) do
		local slotData = {
			slotIndex = slot.slotIndex,
			dataSlotType = slot.dataSlotType,
			dataSlotIndex = slot.dataSlotIndex,
			required = slot.required,
			quantityRequired = slot.quantityRequired,
			covered = coveredSlots[slot.slotIndex],
			options = {},
		}

		slotData.locked, slotData.lockedReason = GetLockedStatus(slot, orderData.recipeInfo)
		slotMap[slot.slotIndex] = slotData

		if not slotData.covered then
			for _, reagent in ipairs(slot.reagents or {}) do
				if reagent.itemID then
					local itemLink = reagent.itemLink or reagent.hyperlink or Util.GetItemLink(reagent.itemID)
					local itemIdentity = GetReagentItemIdentity(reagent.itemID, itemLink)
					local priceInfo = Pricing:GetPriceInfo(itemIdentity, 1)
					local quality = Util.GetProfessionItemQuality(itemIdentity) or Util.GetProfessionItemQuality(reagent.itemID)
					local ownedCount, otherQualityOwnedCount, totalOwnedCount = Util.GetQualityAwareItemCounts(reagent.itemID, itemLink)
					local option = {
						itemID = reagent.itemID,
						itemLink = itemLink,
						itemIdentity = itemIdentity,
						name = Util.GetItemName(reagent.itemID),
						ownedCount = ownedCount,
						otherQualityOwnedCount = otherQualityOwnedCount,
						totalOwnedCount = totalOwnedCount,
						unitPrice = priceInfo.unitPrice,
						priceState = priceInfo.state,
						isMarketable = priceInfo.isMarketable,
						reagentQuality = quality,
						borderAtlas = GetBorderAtlas(reagent.itemID),
					}

					slotData.options[#slotData.options + 1] = option
				end
			end
		end

		if #slotData.options > 0 then
			local availableTotal = 0
			for _, option in ipairs(slotData.options) do
				availableTotal = availableTotal + (option.ownedCount or 0)
			end
			slotData.availableTotal = availableTotal
			slotData.shortage = math.max(0, slotData.quantityRequired - availableTotal)
		end

		if slotData.dataSlotType == MUTABLE_SLOT_TYPE and not slotData.covered and #slotData.options > 0 then
			mutableSlots[#mutableSlots + 1] = slotData
		elseif slot.required and not slotData.covered then
			local staticEntry = BuildMaterialEntry(slotData, SelectDefaultSlotOption(slotData), slotData.quantityRequired)
			if staticEntry then
				staticMaterialEntries[#staticMaterialEntries + 1] = staticEntry
			else
				staticMissingRequiredSlots = staticMissingRequiredSlots + 1
			end
		end

		if slot.required and not slotData.covered then
			requiredReagents[#requiredReagents + 1] = slotData
		end
	end

	orderData.slotMap = slotMap
	orderData.requiredReagents = requiredReagents
	orderData.mutableSlots = mutableSlots
	orderData.staticMaterialEntries = staticMaterialEntries
	orderData.staticMissingRequiredSlots = staticMissingRequiredSlots
	orderData.operationReagents, orderData.baseOperation = CreateOperationContext(orderData, suppliedReagents)

	for _, slotData in ipairs(mutableSlots) do
		for _, option in ipairs(slotData.options) do
			option.score = ScoreMutableOption(orderData, slotData, option, orderData.operationReagents, orderData.baseOperation)
		end

		table.sort(slotData.options, SortSlotOptions)

		local availableTotal = slotData.availableTotal or 0
		slotData.availableTotal = availableTotal
		slotData.shortage = math.max(0, slotData.quantityRequired - availableTotal)
	end

	orderData.qualityRequirement = EvaluateQualityRequirement(orderData)

	local qualityRequirement = orderData.qualityRequirement or {}
	local materialPlan = qualityRequirement.activePlan or qualityRequirement.lowestPlan or BuildLowestMaterialPlan(orderData) or {}
	orderData.materialPlan = materialPlan

	for _, entry in ipairs(GetMaterialPlanEntries(orderData)) do
		local option = entry.option
		local quantity = entry.quantity or 0
		if option and quantity > 0 then
			if entry.marketValueExcluded then
				excludedSlotCount = excludedSlotCount + 1
			else
				marketableSlotCount = marketableSlotCount + 1
			end

			if not entry.marketValueExcluded and entry.totalPrice and entry.totalPrice > 0 then
				materialCost = materialCost + entry.totalPrice
				pricedSlotCount = pricedSlotCount + 1
			end
		end
	end

	orderData.materialCost = materialCost
	orderData.marketableMaterialEntryCount = marketableSlotCount
	orderData.excludedMaterialEntryCount = excludedSlotCount
	orderData.materialCostKnown = marketableSlotCount == 0 or pricedSlotCount > 0
	orderData.materialCostComplete = marketableSlotCount == 0 or pricedSlotCount == marketableSlotCount

	local activeOperation = materialPlan.operationInfo or orderData.baseOperation
	if orderData.requiredQuality > 0 and activeOperation and (activeOperation.craftingQuality or 0) < orderData.requiredQuality then
		local ownedFillCost = EstimateConcentrationCost(orderData, true, false)
		local bestOwnedCost = EstimateConcentrationCost(orderData, true, true)
		local lowestFillCost = qualityRequirement.lowestPlan
			and qualityRequirement.lowestPlan.operationInfo
			and qualityRequirement.lowestPlan.operationInfo.concentrationCost
		local bestMarketCost = qualityRequirement.reachablePlan
			and qualityRequirement.reachablePlan.operationInfo
			and qualityRequirement.reachablePlan.operationInfo.concentrationCost
		local currentCost = activeOperation.concentrationCost or 0
		local currencyID = activeOperation.concentrationCurrencyID or (orderData.baseOperation and orderData.baseOperation.concentrationCurrencyID)

		orderData.concentration = {
			currencyID = currencyID,
			currentCost = currentCost,
			lowestFillCost = lowestFillCost ~= currentCost and lowestFillCost or nil,
			ownedFillCost = ownedFillCost,
			bestOwnedCost = bestOwnedCost,
			bestMarketCost = bestMarketCost ~= currentCost and bestMarketCost or nil,
			available = GetCurrencyQuantity(currencyID),
		}
	end

	orderData.productTooltipLines = BuildProductTooltipLines(orderData)
	orderData.qualityRequirement = CompactQualityRequirement(orderData.qualityRequirement)
end

local function AppendFingerprintParts(parts, ...)
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		parts[#parts + 1] = tostring(value == nil and "" or value)
	end
end

local function AppendRewardFingerprint(parts, rewards)
	for _, reward in ipairs(rewards or EMPTY_LIST) do
		AppendFingerprintParts(
			parts,
			reward.itemLink or reward.itemID or "",
			reward.currencyType or "",
			reward.count or reward.quantity or 1
		)
	end
end

local function AppendSuppliedReagentFingerprint(parts, suppliedReagents)
	for _, suppliedReagent in ipairs(suppliedReagents or EMPTY_LIST) do
		local reagentInfo = suppliedReagent.reagentInfo or {}
		AppendFingerprintParts(
			parts,
			suppliedReagent.slotIndex or "",
			reagentInfo.itemID or "",
			reagentInfo.itemLink or "",
			reagentInfo.currencyID or "",
			reagentInfo.quality or "",
			reagentInfo.quantity or suppliedReagent.quantity or 0
		)
	end
end

local function BuildOrderFingerprint(rawOrder)
	local parts = {}
	AppendFingerprintParts(
		parts,
		rawOrder and rawOrder.orderID or "",
		rawOrder and rawOrder.expirationTime or "",
		rawOrder and rawOrder.customerName or "",
		rawOrder and rawOrder.skillLineAbilityID or "",
		rawOrder and rawOrder.minQuality or "",
		rawOrder and rawOrder.tipAmount or "",
		rawOrder and rawOrder.consortiumCut or ""
	)
	AppendRewardFingerprint(parts, rawOrder and rawOrder.npcOrderRewards)
	AppendSuppliedReagentFingerprint(parts, rawOrder and rawOrder.reagents)
	return table.concat(parts, "|")
end

local function IsItemDataPending(itemID)
	if type(itemID) ~= "number" or itemID <= 0 then
		return false
	end

	if C_Item and type(C_Item.IsItemDataCachedByID) == "function" then
		local ok, isCached = pcall(C_Item.IsItemDataCachedByID, itemID)
		if ok then
			return not isCached
		end
	end

	return Util.GetItemName(itemID) == nil
end

local function TrackUnresolvedItemID(unresolvedItemIDs, itemID)
	if IsItemDataPending(itemID) then
		unresolvedItemIDs[itemID] = true
	end
end

local function CollectUnresolvedItemIDs(orderData)
	local unresolvedItemIDs = {}
	if not orderData then
		return unresolvedItemIDs
	end

	TrackUnresolvedItemID(unresolvedItemIDs, orderData.product and orderData.product.itemID)

	for _, rewardIcon in ipairs((orderData.reward and orderData.reward.icons) or EMPTY_LIST) do
		TrackUnresolvedItemID(unresolvedItemIDs, rewardIcon.itemID)
	end

	for _, slotData in ipairs(orderData.requiredReagents or EMPTY_LIST) do
		for _, option in ipairs(slotData.options or EMPTY_LIST) do
			TrackUnresolvedItemID(unresolvedItemIDs, option.itemID)
		end
	end

	return unresolvedItemIDs
end

local function OrderHasUnresolvedItemData(orderData)
	if not orderData then
		return false
	end
	return next(orderData.unresolvedItemIDs or EMPTY_LIST) ~= nil
end

local function PrepareOrder(rawOrder)
	local recipeInfo = GetRecipeInfo(rawOrder)
	local recipeSchematic = recipeInfo and GetRecipeSchematic(recipeInfo)
	if not (recipeInfo and recipeSchematic) then
		return nil
	end

	local output = GetOutputPresentation(rawOrder, recipeInfo)
	local rewardData = EvaluateRewardValue(rawOrder)
	local isKnown = IsRecipeKnown(recipeInfo)
	local suppliedReagents = rawOrder.reagents
	local reagentSlotSchematics = recipeSchematic.reagentSlotSchematics
	local orderData = {
		orderID = rawOrder.orderID,
		customerName = rawOrder.customerName,
		expirationTime = rawOrder.expirationTime or 0,
		recipeInfo = recipeInfo,
		requiredQuality = GetOrderQuality(rawOrder),
		product = output,
		isKnown = isKnown,
		firstCraft = recipeInfo.firstCraft,
		canSkillUp = recipeInfo.canSkillUp,
		relativeDifficulty = recipeInfo.relativeDifficulty,
		skillUps = recipeInfo.numSkillUps or 0,
		unknownRecipeTooltip = isKnown and nil or BuildUnknownRecipeTooltip(recipeInfo),
		reward = rewardData,
	}

	BuildRequiredReagents(orderData, reagentSlotSchematics, suppliedReagents)
	orderData.profitValue, orderData.profitKnown, orderData.profitComplete = EvaluateProfit(orderData)
	orderData.unresolvedItemIDs = CollectUnresolvedItemIDs(orderData)
	orderData.hasUnresolvedItemData = OrderHasUnresolvedItemData(orderData)

	return orderData
end

function Pane:MarkDetailWarningDirty()
	self.detailWarningDataDirty = true
	if self:IsDetailWarningVisible() then
		self:ScheduleDetailWarningUpdate(DETAIL_WARNING_UPDATE_DELAY)
	end
end

function Pane:ScheduleDetailWarningUpdate(delay)
	if self.detailWarningTimerQueued then
		return
	end

	self.detailWarningTimerQueued = true
	C_Timer.After(delay or 0, function()
		Pane.detailWarningTimerQueued = nil
		if Pane and Pane:IsDetailWarningVisible() then
			Pane:UpdateDetailExpensiveWarning()
		end
	end)
end

function Pane:IsDetailWarningVisible()
	local _, _, schematicForm = self:GetCurrentOrderViewContext()
	return not not (schematicForm and schematicForm:IsShown())
end

function Pane:EnsureDetailWarningHooks()
	local _, _, schematicForm = self:GetCurrentOrderViewContext()
	if not schematicForm then
		return false
	end

	if not schematicForm.coppDetailWarningOnShowHooked then
		schematicForm.coppDetailWarningOnShowHooked = true
		schematicForm:HookScript("OnShow", function()
			Pane:ScheduleDetailWarningUpdate(0)
		end)
	end

	if not schematicForm.coppDetailWarningOnHideHooked then
		schematicForm.coppDetailWarningOnHideHooked = true
		schematicForm:HookScript("OnHide", function(self)
			if self.coppExpensiveIngredientWarning then
				self.coppExpensiveIngredientWarning:Hide()
			end
			Pane:HideDetailExpensiveIngredientSlotWarnings(self)
		end)
	end

	if type(schematicForm.Init) == "function" and not schematicForm.coppDetailWarningInitHooked then
		schematicForm.coppDetailWarningInitHooked = true
		hooksecurefunc(schematicForm, "Init", function()
			Pane:MarkDetailWarningDirty()
		end)
	end

	if type(schematicForm.RegisterCallback) == "function"
		and type(ProfessionsRecipeSchematicFormMixin) == "table"
		and ProfessionsRecipeSchematicFormMixin.Event
		and not schematicForm.coppDetailWarningCallbacksRegistered then
		schematicForm.coppDetailWarningCallbacksRegistered = true

		if ProfessionsRecipeSchematicFormMixin.Event.AllocationsModified then
			schematicForm:RegisterCallback(ProfessionsRecipeSchematicFormMixin.Event.AllocationsModified, function()
				Pane:ScheduleDetailWarningUpdate(0)
			end)
		end

		if ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified then
			schematicForm:RegisterCallback(ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified, function()
				Pane:ScheduleDetailWarningUpdate(0)
			end)
		end
	end

	return true
end

function Pane:EnsureExpensiveIngredientWarningFrame(schematicForm)
	if not schematicForm then
		return nil
	end

	local warningFrame = schematicForm.coppExpensiveIngredientWarning
	if warningFrame then
		return warningFrame
	end

	local parent = (schematicForm.AllocateBestQualityCheckbox and schematicForm.AllocateBestQualityCheckbox:GetParent()) or schematicForm
	warningFrame = CreateFrame("Button", nil, parent)
	warningFrame:SetHeight(18)
	warningFrame:Hide()

	warningFrame.icon = warningFrame:CreateTexture(nil, "ARTWORK")
	warningFrame.icon:SetTexture(DETAIL_WARNING_ICON_TEXTURE)
	warningFrame.icon:SetSize(16, 16)
	warningFrame.icon:SetPoint("LEFT", warningFrame, "LEFT", 0, 0)

	warningFrame.text = warningFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	warningFrame.text:SetPoint("LEFT", warningFrame.icon, "RIGHT", 4, 0)
	warningFrame.text:SetPoint("RIGHT", warningFrame, "RIGHT", 0, 0)
	warningFrame.text:SetJustifyH("LEFT")
	warningFrame.text:SetJustifyV("MIDDLE")

	warningFrame:SetScript("OnEnter", function(self)
		Pane:ShowDetailExpensiveWarningTooltip(self)
	end)
	warningFrame:SetScript("OnLeave", GameTooltip_Hide)

	schematicForm.coppExpensiveIngredientWarning = warningFrame
	return warningFrame
end

function Pane:EnsureExpensiveIngredientSlotWarning(slotFrame)
	if not slotFrame then
		return nil
	end

	local warningButton = slotFrame.coppExpensiveIngredientWarning
	if warningButton then
		return warningButton
	end

	warningButton = CreateFrame("Button", nil, slotFrame)
	warningButton:SetSize(16, 16)
	warningButton:SetFrameStrata(slotFrame:GetFrameStrata())
	warningButton:SetFrameLevel((slotFrame:GetFrameLevel() or 0) + 10)
	warningButton:Hide()

	warningButton.icon = warningButton:CreateTexture(nil, "ARTWORK")
	warningButton.icon:SetTexture(DETAIL_WARNING_ICON_TEXTURE)
	warningButton.icon:SetAllPoints()

	warningButton:SetScript("OnEnter", function(self)
		Pane:ShowDetailExpensiveIngredientSlotTooltip(self)
	end)
	warningButton:SetScript("OnLeave", GameTooltip_Hide)

	slotFrame.coppExpensiveIngredientWarning = warningButton
	return warningButton
end

function Pane:HideDetailExpensiveIngredientSlotWarnings(schematicForm)
	for _, slotFrame in ipairs((schematicForm and schematicForm.coppTrackedExpensiveIngredientSlots) or EMPTY_LIST) do
		local warningButton = slotFrame and slotFrame.coppExpensiveIngredientWarning
		if warningButton then
			warningButton:Hide()
		end
	end
end

function Pane:GetDetailReagentSlotFrames(schematicForm)
	local slotFramesByIndex = {}
	local visitedFrames = {}

	local function TrackSlotFrame(frame)
		if not frame or type(frame.GetReagentSlotSchematic) ~= "function" then
			return
		end

		local ok, slotSchematic = pcall(frame.GetReagentSlotSchematic, frame)
		local slotIndex = ok and slotSchematic and slotSchematic.slotIndex or nil
		if not slotIndex then
			return
		end

		local existing = slotFramesByIndex[slotIndex]
		local existingHasButton = existing and existing.Button ~= nil
		local frameHasButton = frame.Button ~= nil
		if not existing or (frameHasButton and not existingHasButton) then
			slotFramesByIndex[slotIndex] = frame
		end
	end

	local function Visit(frame, depth)
		if not frame or visitedFrames[frame] or depth > 4 then
			return
		end

		visitedFrames[frame] = true
		TrackSlotFrame(frame)

		if type(frame.GetChildren) ~= "function" then
			return
		end

		for _, child in ipairs({ frame:GetChildren() }) do
			Visit(child, depth + 1)
		end
	end

	Visit(schematicForm and schematicForm.Reagents, 0)
	Visit(schematicForm and schematicForm.OptionalReagents, 0)
	for _, frame in ipairs((schematicForm and schematicForm.extraSlotFrames) or EMPTY_LIST) do
		Visit(frame, 0)
	end

	if next(slotFramesByIndex) == nil then
		Visit(schematicForm, 0)
	end

	local orderedFrames = {}
	for slotIndex, frame in pairs(slotFramesByIndex) do
		orderedFrames[#orderedFrames + 1] = {
			slotIndex = slotIndex,
			frame = frame,
		}
	end

	table.sort(orderedFrames, function(left, right)
		return (left.slotIndex or 0) < (right.slotIndex or 0)
	end)

	local slotFrames = {}
	for _, entry in ipairs(orderedFrames) do
		slotFrames[#slotFrames + 1] = entry.frame
	end

	schematicForm.coppTrackedExpensiveIngredientSlots = slotFrames
	return slotFrames
end

function Pane:ShowDetailExpensiveIngredientSlotTooltip(frame)
	local warningEntries = frame and frame.warningEntries or EMPTY_LIST
	local warningColor = GetWarningColor()
	local savingsColor = GetSavingsColor()
	local mutedColor = GetMutedTooltipColor()
	local totalSavings = 0
	local showAggregateSaving = #warningEntries > 1

	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
	GameTooltip:SetText(L.WARNING_ITEM_TITLE, warningColor.r, warningColor.g, warningColor.b)
	GameTooltip:AddLine(L.WARNING_ITEM_SUBTITLE, mutedColor.r, mutedColor.g, mutedColor.b, true)

	for entryIndex, entry in ipairs(warningEntries) do
		local selectedLabel = entry.selectedOption.itemLink or entry.selectedOption.name or UNKNOWN
		local cheapestLabel = entry.cheapestOption.itemLink or entry.cheapestOption.name or UNKNOWN
		local entrySavings = math.max(0, entry.totalSavings or 0)
		totalSavings = totalSavings + entrySavings

		if entryIndex == 1 then
			GameTooltip:AddLine(" ")
		else
			GameTooltip:AddLine(" ")
		end

		GameTooltip:AddDoubleLine(
			FormatItemCountLabel(entry.quantity or 0, selectedLabel),
			LF("WARNING_ITEM_LINE_RIGHT_FORMAT", entry.percentAboveRounded or 0),
			1,
			1,
			1,
			warningColor.r,
			warningColor.g,
			warningColor.b
		)
		GameTooltip:AddDoubleLine(L.WARNING_SELECTED_UNIT_COST, Util.FormatMoney(entry.selectedUnitPrice), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine(L.WARNING_CHEAPEST_UNIT_COST, Util.FormatMoney(entry.cheapestUnitPrice), mutedColor.r, mutedColor.g, mutedColor.b, 1, 1, 1)
		GameTooltip:AddLine(LF("WARNING_CHEAPER_QUALITY_FORMAT", cheapestLabel), mutedColor.r, mutedColor.g, mutedColor.b, true)
		GameTooltip:AddDoubleLine(
			L.WARNING_POTENTIAL_SAVING,
			Util.FormatMoney(entrySavings),
			savingsColor.r,
			savingsColor.g,
			savingsColor.b,
			savingsColor.r,
			savingsColor.g,
			savingsColor.b
		)
	end

	GameTooltip:AddLine(" ")
	if showAggregateSaving and totalSavings > 0 then
		GameTooltip:AddDoubleLine(
			L.WARNING_TOTAL_POTENTIAL_SAVING,
			Util.FormatMoney(totalSavings),
			1,
			1,
			1,
			savingsColor.r,
			savingsColor.g,
			savingsColor.b
		)
		GameTooltip:AddLine(" ")
	end
	GameTooltip:AddLine(L.WARNING_ITEM_SELF_SUPPLIED_ONLY, mutedColor.r, mutedColor.g, mutedColor.b, true)
	GameTooltip:Show()
end

function Pane:ShowDetailExpensiveWarningTooltip(frame)
	local thresholdPercent = frame and frame.thresholdPercent or GetExpensiveIngredientThresholdPercent()
	local warningCount = frame and frame.warningCount or 0
	local totalSavings = frame and frame.totalSavings or 0
	local warningColor = GetWarningColor()
	local savingsColor = GetSavingsColor()
	local mutedColor = GetMutedTooltipColor()

	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
	GameTooltip:SetText(L.WARNING_SUMMARY_TITLE, warningColor.r, warningColor.g, warningColor.b)
	GameTooltip:AddLine(
		LF("WARNING_SUMMARY_DESC_FORMAT", thresholdPercent),
		mutedColor.r,
		mutedColor.g,
		mutedColor.b,
		true
	)
	if warningCount > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L.WARNING_SUMMARY_AFFECTED_INGREDIENTS, tostring(warningCount), 1, 1, 1, 1, 1, 1)
		if totalSavings > 0 then
			GameTooltip:AddDoubleLine(
				L.WARNING_TOTAL_POTENTIAL_SAVING,
				Util.FormatMoney(totalSavings),
				1,
				1,
				1,
				savingsColor.r,
				savingsColor.g,
				savingsColor.b
			)
		end
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L.WARNING_SUMMARY_HOVER_HINT, mutedColor.r, mutedColor.g, mutedColor.b, true)
	GameTooltip:AddLine(L.WARNING_SUMMARY_SELF_SUPPLIED_ONLY, mutedColor.r, mutedColor.g, mutedColor.b, true)
	GameTooltip:Show()
end

function Pane:RefreshDetailWarningOrderData(orderInfo)
	if not (orderInfo and orderInfo.orderID) then
		self.detailWarningOrderID = nil
		self.detailWarningOrderData = nil
		self.detailWarningDataDirty = nil
		return nil
	end

	if not self.detailWarningDataDirty
		and self.detailWarningOrderID == orderInfo.orderID
		and self.detailWarningOrderData then
		return self.detailWarningOrderData
	end

	self.detailWarningOrderID = orderInfo.orderID
	self.detailWarningOrderData = PrepareOrder(orderInfo)
	self.detailWarningDataDirty = nil
	return self.detailWarningOrderData
end

function Pane:BuildExpensiveIngredientWarnings(orderData, transaction, thresholdPercent)
	local warningEntries = {}
	if not (orderData and transaction) then
		return warningEntries
	end

	for slotIndex, slotData in pairs(orderData.slotMap or EMPTY_LIST) do
		if slotData and not slotData.covered and not slotData.locked then
			local cheapestByGroup = {}
			local groupCounts = {}

			for _, option in ipairs(slotData.options or EMPTY_LIST) do
				local groupKey = GetExpensiveIngredientGroupKey(option)
				if groupKey and IsPricedMarketOption(option) then
					groupCounts[groupKey] = (groupCounts[groupKey] or 0) + 1
					if IsCheaperWarningOption(option, cheapestByGroup[groupKey]) then
						cheapestByGroup[groupKey] = option
					end
				end
			end

			local allocations = type(transaction.GetAllocations) == "function" and transaction:GetAllocations(slotIndex) or nil
			if allocations and type(allocations.FindAllocationByReagent) == "function" then
				for _, option in ipairs(slotData.options or EMPTY_LIST) do
					local groupKey = GetExpensiveIngredientGroupKey(option)
					local cheapestOption = groupKey and cheapestByGroup[groupKey]
					if groupKey
						and cheapestOption
						and cheapestOption ~= option
						and (groupCounts[groupKey] or 0) > 1
						and IsPricedMarketOption(option)
						and type(cheapestOption.unitPrice) == "number"
						and cheapestOption.unitPrice > 0 then
						local reagent = self:FindTransactionReagent(transaction, slotIndex, option)
						local allocation = reagent and allocations:FindAllocationByReagent(reagent)
						local quantity = allocation and type(allocation.GetQuantity) == "function" and allocation:GetQuantity() or 0
						if quantity > 0 then
							local percentAbove = ((option.unitPrice - cheapestOption.unitPrice) / cheapestOption.unitPrice) * 100
							if percentAbove > thresholdPercent then
								local totalSavings = math.max(0, (option.unitPrice - cheapestOption.unitPrice) * quantity)
								warningEntries[#warningEntries + 1] = {
									slotIndex = slotIndex,
									quantity = quantity,
									selectedOption = option,
									selectedUnitPrice = option.unitPrice,
									cheapestOption = cheapestOption,
									cheapestUnitPrice = cheapestOption.unitPrice,
									percentAbove = percentAbove,
									percentAboveRounded = math.floor(percentAbove + 0.5),
									totalSavings = totalSavings,
								}
							end
						end
					end
				end
			end
		end
	end

	table.sort(warningEntries, function(left, right)
		if (left.percentAbove or 0) ~= (right.percentAbove or 0) then
			return (left.percentAbove or 0) > (right.percentAbove or 0)
		end
		if (left.selectedUnitPrice or 0) ~= (right.selectedUnitPrice or 0) then
			return (left.selectedUnitPrice or 0) > (right.selectedUnitPrice or 0)
		end
		return (left.slotIndex or 0) < (right.slotIndex or 0)
	end)

	return warningEntries
end

function Pane:UpdateDetailExpensiveIngredientSlotWarnings(schematicForm, warningEntries, thresholdPercent)
	self:HideDetailExpensiveIngredientSlotWarnings(schematicForm)

	if not (schematicForm and warningEntries and #warningEntries > 0) then
		return
	end

	local warningsBySlot = {}
	for _, entry in ipairs(warningEntries) do
		local slotIndex = entry.slotIndex
		if slotIndex then
			local bucket = warningsBySlot[slotIndex]
			if not bucket then
				bucket = {}
				warningsBySlot[slotIndex] = bucket
			end
			bucket[#bucket + 1] = entry
		end
	end

	for _, slotFrame in ipairs(self:GetDetailReagentSlotFrames(schematicForm)) do
		local ok, slotSchematic = pcall(slotFrame.GetReagentSlotSchematic, slotFrame)
		local slotIndex = ok and slotSchematic and slotSchematic.slotIndex or nil
		local slotWarnings = slotIndex and warningsBySlot[slotIndex] or nil
		local warningButton = slotWarnings and self:EnsureExpensiveIngredientSlotWarning(slotFrame) or nil
		if warningButton and slotWarnings and #slotWarnings > 0 then
			local anchorTo = slotFrame.Button or slotFrame
			warningButton.warningEntries = slotWarnings
			warningButton.thresholdPercent = thresholdPercent
			warningButton:ClearAllPoints()
			warningButton:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", 4, 2)
			warningButton:Show()
		end
	end
end

function Pane:UpdateDetailExpensiveWarning()
	self:EnsureDetailWarningHooks()

	local _, orderInfo, schematicForm, transaction = self:GetCurrentOrderViewContext()
	local warningFrame = schematicForm and self:EnsureExpensiveIngredientWarningFrame(schematicForm) or nil
	local checkbox = schematicForm and schematicForm.AllocateBestQualityCheckbox
	if not warningFrame then
		return
	end

	if ns.GetConfig("warnExpensiveIngredients") == false
		or not (schematicForm and schematicForm:IsShown())
		or not transaction
		or not orderInfo then
		warningFrame:Hide()
		self:HideDetailExpensiveIngredientSlotWarnings(schematicForm)
		return
	end

	local orderData = self:RefreshDetailWarningOrderData(orderInfo)
	local thresholdPercent = GetExpensiveIngredientThresholdPercent()
	local warningEntries = self:BuildExpensiveIngredientWarnings(orderData, transaction, thresholdPercent)
	self:UpdateDetailExpensiveIngredientSlotWarnings(schematicForm, warningEntries, thresholdPercent)
	if #warningEntries == 0 or not (checkbox and checkbox:IsShown()) then
		warningFrame:Hide()
		return
	end

	local warningColor = GetWarningColor()
	local warningCount = #warningEntries
	local warningText = L.WARNING_SUMMARY_LABEL
	local totalSavings = 0
	for _, entry in ipairs(warningEntries) do
		totalSavings = totalSavings + math.max(0, entry.totalSavings or 0)
	end
	local checkboxLabel = checkbox and (checkbox.Text or checkbox.text)
	local anchorTarget = checkboxLabel or checkbox
	warningFrame.warningEntries = warningEntries
	warningFrame.thresholdPercent = thresholdPercent
	warningFrame.warningCount = warningCount
	warningFrame.totalSavings = totalSavings
	warningFrame:ClearAllPoints()
	warningFrame:SetPoint("LEFT", anchorTarget, "RIGHT", 10, 0)
	warningFrame.text:SetText(warningText)
	warningFrame:SetWidth(20 + warningFrame.text:GetStringWidth())
	warningFrame.text:SetTextColor(warningColor.r, warningColor.g, warningColor.b)
	warningFrame:Show()
end

local function CompareRewards(left, right)
	if left.reward.knowledge ~= right.reward.knowledge then
		return left.reward.knowledge > right.reward.knowledge
	end
	if left.reward.acuity ~= right.reward.acuity then
		return left.reward.acuity > right.reward.acuity
	end
	if left.reward.totalValue ~= right.reward.totalValue then
		return left.reward.totalValue > right.reward.totalValue
	end
	return left.expirationTime < right.expirationTime
end

local function CompareProfit(left, right)
	local leftProfit = NumericSortValue(left.profitValue)
	local rightProfit = NumericSortValue(right.profitValue)
	if leftProfit ~= rightProfit then
		return leftProfit > rightProfit
	end
	if left.profitKnown ~= right.profitKnown then
		return left.profitKnown
	end
	if left.product.plainLabel ~= right.product.plainLabel then
		return left.product.plainLabel < right.product.plainLabel
	end
	return CompareRewards(left, right)
end

local function SortOrders(orders, sortKey, ascending)
	table.sort(orders, function(left, right)
		local result
		if sortKey == "order" then
			if left.isKnown ~= right.isKnown then
				result = left.isKnown
			elseif left.product.plainLabel ~= right.product.plainLabel then
				result = left.product.plainLabel < right.product.plainLabel
			else
				result = CompareRewards(left, right)
			end
		elseif sortKey == "cost" then
			local leftCost = NumericSortValue(left.materialCost)
			local rightCost = NumericSortValue(right.materialCost)
			if leftCost ~= rightCost then
				result = leftCost < rightCost
			else
				result = left.product.plainLabel < right.product.plainLabel
			end
		elseif sortKey == "profit" then
			result = CompareProfit(left, right)
		elseif sortKey == "time" then
			if left.expirationTime ~= right.expirationTime then
				result = left.expirationTime < right.expirationTime
			elseif left.product.plainLabel ~= right.product.plainLabel then
				result = left.product.plainLabel < right.product.plainLabel
			else
				result = CompareRewards(left, right)
			end
		else
			result = CompareRewards(left, right)
		end

		if ascending then
			return not result
		end

		return result
	end)
end

function Pane:ShowCostTooltip(row)
	GameTooltip:SetOwner(row.costHitBox, "ANCHOR_RIGHT")
	GameTooltip:SetText(L.TOOLTIP_SUPPLIED_MATERIALS)

	if #GetMaterialPlanEntries(row.order) == 0 then
		GameTooltip:AddLine(L.TOOLTIP_ALL_REQUIRED_REAGENTS_ALREADY_SUPPLIED, 1, 1, 1, true)
	else
		for _, entry in ipairs(GetMaterialPlanEntries(row.order)) do
			local option = entry.option
			if option then
				local line = FormatItemCountLabel(entry.quantity or 0, option.name or UNKNOWN)
				local right = GetPriceDisplayText(entry.totalPrice, entry.priceState)
				GameTooltip:AddDoubleLine(line, right, 1, 1, 1, 1, 1, 1)
			end
		end
	end

	if row.order.concentration then
		local concentration = row.order.concentration
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L.TOOLTIP_CURRENT_CONCENTRATION, FormatConcentrationValue(concentration.currentCost or 0), 1, 1, 1, 1, 1, 1)
		if concentration.lowestFillCost ~= nil then
			GameTooltip:AddDoubleLine(L.TOOLTIP_LOWEST_QUALITY_MATERIALS, FormatConcentrationValue(concentration.lowestFillCost), 0.9, 0.9, 0.9, 1, 1, 1)
		end
		if concentration.ownedFillCost ~= nil then
			GameTooltip:AddDoubleLine(L.TOOLTIP_WITH_OWNED_REAGENTS, FormatConcentrationValue(concentration.ownedFillCost), 0.9, 0.9, 0.9, 1, 1, 1)
		end
		if concentration.bestOwnedCost ~= nil then
			GameTooltip:AddDoubleLine(L.TOOLTIP_BEST_OWNED_MIX, FormatConcentrationValue(concentration.bestOwnedCost), 0.9, 0.9, 0.9, 1, 1, 1)
		end
		if concentration.bestMarketCost ~= nil then
			GameTooltip:AddDoubleLine(L.TOOLTIP_BEST_MARKET_MIX, FormatConcentrationValue(concentration.bestMarketCost), 0.9, 0.9, 0.9, 1, 1, 1)
		end
	end

	GameTooltip:Show()
end

function Pane:ShowRewardTooltip(row)
	GameTooltip:SetOwner(row.rewardHitBox, "ANCHOR_RIGHT")
	GameTooltip:SetText(L.TOOLTIP_REWARD_VALUE)
	GameTooltip:AddDoubleLine(L.TOOLTIP_GOLD, Util.FormatMoney(row.order.reward.gold), 1, 1, 1, 1, 1, 1)

	for _, rewardIcon in ipairs(row.order.reward.icons) do
		if rewardIcon.itemLink or rewardIcon.currencyID then
			local left = GetRewardTooltipLabel(rewardIcon)
			local right = GetPriceDisplayText(rewardIcon.totalPrice, rewardIcon.priceState)
			GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
		end
	end

	if row.order.reward.hasPriceData then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L.TOOLTIP_TOTAL, Util.FormatMoney(row.order.reward.totalValue), 1, 1, 1, 1, 1, 1)
	end

	GameTooltip:Show()
end

function Pane:ShowProfitTooltip(row)
	GameTooltip:SetOwner(row.profitHitBox, "ANCHOR_RIGHT")
	GameTooltip:SetText(L.TOOLTIP_ESTIMATED_PROFIT)

	if not row.order.profitKnown then
		GameTooltip:AddLine(L.TOOLTIP_NOT_ENOUGH_MARKET_DATA, 1, 1, 1, true)
		GameTooltip:Show()
		return
	end

	GameTooltip:AddDoubleLine(L.TOOLTIP_REWARD_TOTAL, FormatSignedMoney(math.max(0, row.order.reward.totalValue or 0)), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(
		L.TOOLTIP_SUPPLY_COST,
		FormatSignedMoney(-math.max(0, row.order.materialCost or 0)),
		1,
		1,
		1,
		RED_FONT_COLOR.r,
		RED_FONT_COLOR.g,
		RED_FONT_COLOR.b
	)
	GameTooltip:AddLine(" ")

	local value = row.order.profitValue or 0
	local color = value < 0 and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR
	local rightText = FormatSignedMoney(value)
	if not row.order.profitComplete then
		rightText = rightText .. "*"
	end
	GameTooltip:AddDoubleLine(L.TOOLTIP_NET_PROFIT, rightText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, color.r, color.g, color.b)

	if not row.order.profitComplete then
		GameTooltip:AddLine(L.TOOLTIP_PARTIAL_MARKET_DATA, 0.95, 0.95, 0.95)
	end

	GameTooltip:Show()
end

function Pane:ShowIconTooltip(iconFrame)
	local data = iconFrame.data
	if not data then
		return
	end

	GameTooltip:SetOwner(iconFrame, "ANCHOR_RIGHT")
	if data.itemLink then
		GameTooltip:SetHyperlink(data.itemLink)
	elseif data.itemID then
		GameTooltip:SetHyperlink(("item:%d"):format(data.itemID))
	elseif data.currencyID then
		GameTooltip:SetCurrencyByID(data.currencyID)
	end

	if data.reagentQuality and data.selectedQualityOwnedCount ~= nil then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L.ICON_AVAILABLE_SELECTED_QUALITY, tostring(data.selectedQualityOwnedCount), 1, 1, 1, 1, 1, 1)
		if (data.otherQualityOwnedCount or 0) > 0 then
			local warningColor = WARNING_FONT_COLOR or { r = 1, g = 0.282, b = 0 }
			GameTooltip:AddDoubleLine(L.ICON_AVAILABLE_OTHER_QUALITIES, tostring(data.otherQualityOwnedCount), 1, 1, 1, warningColor.r, warningColor.g, warningColor.b)
			if (data.shortage or 0) > 0 then
				GameTooltip:AddLine(L.ICON_OTHER_QUALITIES_HINT, warningColor.r, warningColor.g, warningColor.b, true)
			end
		end
	elseif data.availableTotal then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L.ICON_AVAILABLE, tostring(data.availableTotal), 1, 1, 1, 1, 1, 1)
	end

	local hasPricingState = data.totalPrice ~= nil or data.unitPrice ~= nil or data.priceState ~= nil
	if hasPricingState then
		if data.totalPrice then
			GameTooltip:AddDoubleLine(L.ICON_MARKET_VALUE, Util.FormatMoney(data.totalPrice), 1, 1, 1, 1, 1, 1)
		elseif data.unitPrice then
			GameTooltip:AddDoubleLine(L.ICON_UNIT_VALUE, Util.FormatMoney(data.unitPrice), 1, 1, 1, 1, 1, 1)
		elseif IsExcludedFromMarketValue(data.priceState) then
			GameTooltip:AddLine(L.PRICE_NOT_MARKETABLE, 0.95, 0.95, 0.95, true)
		elseif data.itemID then
			GameTooltip:AddLine(L.PRICE_NO_MARKET_DATA, 0.95, 0.95, 0.95, true)
		end
	end

	if data.extraLines then
		for _, line in ipairs(data.extraLines) do
			GameTooltip:AddLine(line, 0.95, 0.95, 0.95, true)
		end
	end

	if data.toggleDontBuy and data.itemID then
		GameTooltip:AddLine(" ")
		if data.doNotBuy then
			GameTooltip:AddLine(("|cffff4040%s|r"):format(L.DONT_BUY_MARKED), 1, 1, 1, true)
			GameTooltip:AddLine(L.DONT_BUY_MARKED_DESC, 0.95, 0.95, 0.95, true)
		else
			GameTooltip:AddLine(L.DONT_BUY_CLICK_TO_MARK, 1, 1, 1, true)
			GameTooltip:AddLine(L.DONT_BUY_DESC, 0.95, 0.95, 0.95, true)
		end
	end

	if not data.isKnown and data.unknownRecipeLines then
		local addonTitle = ns.GetAddonMetadata and ns.GetAddonMetadata(ns.ADDON_NAME, "Title") or nil
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(("|cff4cc9f0%s|r"):format(addonTitle or L.ADDON_TITLE or ns.ADDON_NAME), 0.95, 0.95, 0.95, true)
		for _, line in ipairs(data.unknownRecipeLines) do
			GameTooltip:AddLine(line, 0.95, 0.95, 0.95, true)
		end
	end

	GameTooltip:Show()
end

function Pane:SetIconData(iconFrame, data)
	iconFrame.data = data
	if not data then
		if iconFrame.favorite then
			iconFrame.favorite:Hide()
		end
		iconFrame:Hide()
		return
	end

	iconFrame.icon:SetTexture(data.icon or "Interface/Icons/INV_Misc_QuestionMark")
	iconFrame.border:SetAtlas(data.borderAtlas or GetBorderAtlas(data.itemID))
	iconFrame.count:SetText(FormatCount(data.count, data.alwaysShowCount))
	iconFrame.icon:SetDesaturated(data.desaturated)
	if iconFrame.favorite then
		iconFrame.favorite:SetShown(not not data.favoriteBadge)
	end
	if iconFrame.blocked then
		iconFrame.blocked:SetShown(not not data.doNotBuy)
	end
	if data.shortage and data.shortage > 0 then
		if (data.otherQualityOwnedCount or 0) > 0 then
			local warningColor = WARNING_FONT_COLOR or { r = 1, g = 0.282, b = 0 }
			iconFrame.count:SetTextColor(warningColor.r, warningColor.g, warningColor.b)
		else
			iconFrame.count:SetTextColor(1, 0.2, 0.2)
		end
	else
		iconFrame.count:SetTextColor(1, 1, 1)
	end
	iconFrame:Show()
end

function Pane:CreateIcon(parent)
	local iconButton = CreateFrame("Button", nil, parent)
	iconButton:SetSize(REAGENT_ICON_SIZE, REAGENT_ICON_SIZE)
	iconButton.icon = iconButton:CreateTexture(nil, "ARTWORK")
	iconButton.icon:SetAllPoints()

	iconButton.border = iconButton:CreateTexture(nil, "OVERLAY")
	iconButton.border:SetAllPoints()
	iconButton.border:SetAtlas("Professions-Slot-Frame")

	iconButton.favorite = iconButton:CreateTexture(nil, "OVERLAY", nil, 1)
	iconButton.favorite:SetAtlas("auctionhouse-icon-favorite", true)
	iconButton.favorite:SetSize(12, 12)
	iconButton.favorite:SetPoint("TOPRIGHT", iconButton, "TOPRIGHT", 3, 2)
	iconButton.favorite:Hide()

	iconButton.blocked = iconButton:CreateTexture(nil, "HIGHLIGHT")
	iconButton.blocked:SetTexture(DONT_BUY_OVERLAY_TEXTURE)
	iconButton.blocked:SetSize(18, 18)
	iconButton.blocked:SetPoint("CENTER", iconButton, "CENTER")
	iconButton.blocked:Hide()

	iconButton.count = iconButton:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	iconButton.count:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -2, 2)
	iconButton.count:SetJustifyH("RIGHT")

	iconButton:SetScript("OnEnter", function(self)
		Pane:ShowIconTooltip(self)
	end)
	iconButton:SetScript("OnLeave", GameTooltip_Hide)
	iconButton:SetScript("OnClick", function(self, button)
		local data = self.data
		if IsModifiedClick("CHATLINK") then
			local link = data and (data.itemLink or GetCurrencyLink(data.currencyID, data.count))
			if link then
				ChatFrameUtil.InsertLink(link)
				return
			end
		end

		if button == "LeftButton" and data and data.toggleDontBuy and data.itemID then
			Pane:ToggleDontBuyItem(data.itemID)
			if GameTooltip:IsOwned(self) then
				Pane:ShowIconTooltip(self)
			end
			return
		end

		Pane:ViewOrder(self.row and self.row.order)
	end)

	return iconButton
end

function Pane:FindLiveOrderInfo(orderID)
	if not orderID then
		return nil
	end

	for _, orderInfo in ipairs(C_CraftingOrders.GetCrafterOrders() or EMPTY_LIST) do
		if orderInfo.orderID == orderID then
			return orderInfo
		end
	end

	return nil
end

function Pane:BuildPendingOpenPlan(orderData)
	if not (orderData and orderData.orderID and orderData.recipeInfo and orderData.recipeInfo.recipeID) then
		return nil
	end

	local slotAllocations = {}
	local clearSlotIndices = {}

	for slotIndex, slotData in pairs(orderData.slotMap or {}) do
		if slotData and not slotData.covered then
			clearSlotIndices[#clearSlotIndices + 1] = slotIndex
		end
	end
	table.sort(clearSlotIndices)

	for _, entry in ipairs(GetMaterialPlanEntries(orderData)) do
		local slotData = entry.slotData
		local option = entry.option
		local quantity = entry.quantity or 0
		if slotData and option and quantity > 0 then
			CreatePendingSlotAllocation(slotAllocations, slotData.slotIndex, option.itemID, option.currencyID, quantity)
		end
	end

	return {
		orderID = orderData.orderID,
		recipeID = orderData.recipeInfo.recipeID,
		clearSlotIndices = clearSlotIndices,
		slotAllocations = slotAllocations,
		applyConcentration = not not (orderData.concentration and (orderData.concentration.currentCost or 0) > 0),
		attempts = 0,
	}
end

function Pane:GetCurrentOrderViewContext()
	local ordersPage = ProfessionsFrame and ProfessionsFrame.OrdersPage
	local orderView = ordersPage and ordersPage.OrderView
	local schematicForm = orderView and orderView.OrderDetails and orderView.OrderDetails.SchematicForm
	local transaction = schematicForm and ((type(schematicForm.GetTransaction) == "function" and schematicForm:GetTransaction()) or schematicForm.transaction)
	return orderView, orderView and orderView.order, schematicForm, transaction
end

function Pane:FindTransactionReagent(transaction, slotIndex, allocationData)
	if not (transaction and slotIndex and allocationData) then
		return nil
	end

	local reagentSlotSchematic = type(transaction.GetReagentSlotSchematic) == "function" and transaction:GetReagentSlotSchematic(slotIndex)
	for _, reagent in ipairs(reagentSlotSchematic and reagentSlotSchematic.reagents or EMPTY_LIST) do
		if allocationData.itemID and reagent.itemID == allocationData.itemID then
			return reagent
		end
		if allocationData.currencyID and reagent.currencyID == allocationData.currencyID then
			return reagent
		end
	end

	return nil
end

function Pane:ApplyPendingOrderPlanNow()
	local pending = self.pendingOpenPlan
	if not pending then
		return true
	end

	local orderView, orderInfo, schematicForm, transaction = self:GetCurrentOrderViewContext()
	if not (orderView and orderInfo and schematicForm and transaction) then
		return false
	end

	if orderInfo.orderID ~= pending.orderID then
		return false
	end

	if type(transaction.GetRecipeID) == "function" and pending.recipeID and transaction:GetRecipeID() ~= pending.recipeID then
		return false
	end

	local checkbox = schematicForm.AllocateBestQualityCheckbox
	if checkbox and type(checkbox.SetChecked) == "function" then
		checkbox:SetChecked(false)
	end

	if type(Professions) == "table" and type(Professions.SetShouldAllocateBestQualityReagents) == "function" then
		pcall(Professions.SetShouldAllocateBestQualityReagents, false)
	end

	if type(transaction.SetManuallyAllocated) == "function" then
		pcall(transaction.SetManuallyAllocated, transaction, true)
	end

	for _, slotIndex in ipairs(pending.clearSlotIndices or EMPTY_LIST) do
		if type(transaction.ClearAllocations) == "function" then
			pcall(transaction.ClearAllocations, transaction, slotIndex)
		end
	end

	for slotIndex, allocationsData in pairs(pending.slotAllocations or {}) do
		local allocations = type(transaction.GetAllocations) == "function" and transaction:GetAllocations(slotIndex) or nil
		if allocations and type(allocations.Clear) == "function" then
			pcall(allocations.Clear, allocations)
		elseif type(transaction.ClearAllocations) == "function" then
			pcall(transaction.ClearAllocations, transaction, slotIndex)
		end

		for _, allocationData in ipairs(allocationsData) do
			local reagent = self:FindTransactionReagent(transaction, slotIndex, allocationData)
			if reagent then
				if allocations and type(allocations.Allocate) == "function" then
					pcall(allocations.Allocate, allocations, reagent, allocationData.quantity)
				elseif type(transaction.OverwriteAllocation) == "function" then
					pcall(transaction.OverwriteAllocation, transaction, slotIndex, reagent, allocationData.quantity)
				end
			end
		end
	end

	if type(transaction.SetApplyConcentration) == "function" then
		pcall(transaction.SetApplyConcentration, transaction, pending.applyConcentration)
	end

	if type(schematicForm.TriggerEvent) == "function"
		and type(ProfessionsRecipeSchematicFormMixin) == "table"
		and ProfessionsRecipeSchematicFormMixin.Event
		and ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified then
		pcall(schematicForm.TriggerEvent, schematicForm, ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified, false)
	end

	if type(schematicForm.UpdateAllSlots) == "function" then
		pcall(schematicForm.UpdateAllSlots, schematicForm)
	end
	if type(schematicForm.UpdateDetailsStats) == "function" then
		pcall(schematicForm.UpdateDetailsStats, schematicForm)
	end

	self:ScheduleDetailWarningUpdate(0)

	return true
end

function Pane:SchedulePendingOrderPlan(delay)
	if not self.pendingOpenPlan or self.pendingPlanTimerQueued then
		return
	end

	self.pendingPlanTimerQueued = true
	C_Timer.After(delay or 0, function()
		Pane.pendingPlanTimerQueued = nil
		Pane:TryApplyPendingOrderPlan()
	end)
end

function Pane:TryApplyPendingOrderPlan()
	local pending = self.pendingOpenPlan
	if not pending then
		return
	end

	if self:ApplyPendingOrderPlanNow() then
		self.pendingOpenPlan = nil
		return
	end

	pending.attempts = (pending.attempts or 0) + 1
	if pending.attempts < 20 then
		self:SchedulePendingOrderPlan(0.05)
	else
		self.pendingOpenPlan = nil
	end
end

function Pane:ViewOrder(orderData)
	if not (orderData and orderData.orderID) then
		return
	end

	local orderInfo = self:FindLiveOrderInfo(orderData.orderID)
	if orderInfo and ProfessionsFrame and ProfessionsFrame.OrdersPage then
		if ns.GetConfig("openPatronOrderBehavior") == "apply_plan" then
			self.pendingOpenPlan = self:BuildPendingOpenPlan(orderData)
		else
			self.pendingOpenPlan = nil
		end
		ProfessionsFrame.OrdersPage:ViewOrder(orderInfo)
		self:SchedulePendingOrderPlan(0)
		return
	end

	self.pendingOpenPlan = nil
	ns.Print(L.MSG_ORDER_NO_LONGER_AVAILABLE)
end

function Pane:CreateRow(index, row)
	local hasNativeLayout = row ~= nil
	row = row or CreateFrame("Button", nil, self.scrollChild or self.scrollFrame)
	row.rowIndex = index or row.rowIndex or 1
	if row.craftingOrdersInitialized then
		return row
	end

	row.craftingOrdersInitialized = true
	if self.rows and not row.trackedByPane then
		row.trackedByPane = true
		self.rows[#self.rows + 1] = row
	end
	row:SetHeight(ROW_HEIGHT)
	row:SetWidth(CONTENT_WIDTH)
	if not hasNativeLayout and self.scrollChild then
		row:SetPoint("LEFT", self.scrollChild, "LEFT", 0, 0)
		row:SetPoint("RIGHT", self.scrollChild, "RIGHT", -2, 0)
	end
	row:SetHighlightAtlas("talents-pvpflyout-rowhighlight")
	row:GetHighlightTexture():SetVertexColor(0.12, 0.48, 0.95)
	row:GetHighlightTexture():SetAlpha(0.75)

	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints()
	row.background:SetColorTexture(1, 1, 1, row.rowIndex % 2 == 0 and 0.025 or 0.01)

	row.checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.checkbox:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -12)
	row.checkbox:SetScript("OnClick", function(self)
		if self.row and self.row.order then
			Pane.selectedOrderIDs[self.row.order.orderID] = self:GetChecked() or nil
			Pane:UpdateToolbar()
		end
	end)
	row.checkbox.row = row

	row.productIcon = self:CreateIcon(row)
	row.productIcon.row = row
	row.productIcon:SetSize(PRODUCT_ICON_SIZE, PRODUCT_ICON_SIZE)
	row.productIcon:SetPoint("TOPLEFT", row, "TOPLEFT", SELECT_WIDTH + PRODUCT_ICON_LEFT_OFFSET, PRODUCT_ICON_TOP_OFFSET)

	row.title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.title:SetPoint("TOPLEFT", row.productIcon, "TOPRIGHT", PRODUCT_TEXT_GAP, -1)
	row.title:SetPoint("RIGHT", row, "LEFT", SELECT_WIDTH + ORDER_WIDTH - 6, 0)
	row.title:SetJustifyH("LEFT")

	row.flags = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.flags:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
	row.flags:SetPoint("RIGHT", row.title, "RIGHT")
	row.flags:SetJustifyH("LEFT")

	row.reagentLabel = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.reagentLabel:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
	row.reagentLabel:SetText("")
	row.reagentLabel:Hide()

	row.reagentIcons = {}

	row.costText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.costText:SetPoint("TOPLEFT", row, "TOPLEFT", SELECT_WIDTH + ORDER_WIDTH + 8, -10)
	row.costText:SetPoint("RIGHT", row, "LEFT", SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH - 6, 0)
	row.costText:SetJustifyH("LEFT")

	row.costHint = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.costHint:SetPoint("TOPLEFT", row.costText, "BOTTOMLEFT", 0, -2)
	row.costHint:SetPoint("RIGHT", row.costText, "RIGHT")
	row.costHint:SetJustifyH("LEFT")

	row.costHitBox = CreateFrame("Frame", nil, row)
	row.costHitBox:SetPoint("TOPLEFT", row, "TOPLEFT", SELECT_WIDTH + ORDER_WIDTH, 0)
	row.costHitBox:SetSize(COST_WIDTH, ROW_HEIGHT)
	row.costHitBox:EnableMouse(true)
	row.costHitBox:SetScript("OnEnter", function()
		Pane:ShowCostTooltip(row)
	end)
	row.costHitBox:SetScript("OnLeave", GameTooltip_Hide)
	row.costHitBox:SetScript("OnMouseUp", function()
		Pane:ViewOrder(row.order)
	end)

	row.rewardText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.rewardText:SetPoint("TOPLEFT", row, "TOPLEFT", SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + 8, -8)
	row.rewardText:SetPoint("RIGHT", row, "LEFT", SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + REWARD_WIDTH - 8, 0)
	row.rewardText:SetJustifyH("LEFT")

	row.rewardValue = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.rewardValue:SetPoint("TOPLEFT", row.rewardText, "BOTTOMLEFT", 0, -2)
	row.rewardValue:SetPoint("RIGHT", row.rewardText, "RIGHT")
	row.rewardValue:SetJustifyH("LEFT")
	row.rewardValue:Hide()

	row.rewardIcons = {}

	row.rewardHitBox = CreateFrame("Frame", nil, row)
	row.rewardHitBox:SetPoint("TOPLEFT", row, "TOPLEFT", SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH, 0)
	row.rewardHitBox:SetSize(REWARD_WIDTH, ROW_HEIGHT)
	row.rewardHitBox:EnableMouse(true)
	row.rewardHitBox:SetScript("OnEnter", function()
		Pane:ShowRewardTooltip(row)
	end)
	row.rewardHitBox:SetScript("OnLeave", GameTooltip_Hide)
	row.rewardHitBox:SetScript("OnMouseUp", function()
		Pane:ViewOrder(row.order)
	end)

	row.profitText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.profitText:SetPoint("TOPLEFT", row, "TOPLEFT", SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + REWARD_WIDTH + 8, -10)
	row.profitText:SetPoint("RIGHT", row, "LEFT", SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + REWARD_WIDTH + PROFIT_WIDTH - 6, 0)
	row.profitText:SetJustifyH("LEFT")

	row.profitHitBox = CreateFrame("Frame", nil, row)
	row.profitHitBox:SetPoint("TOPLEFT", row, "TOPLEFT", SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + REWARD_WIDTH, 0)
	row.profitHitBox:SetSize(PROFIT_WIDTH, ROW_HEIGHT)
	row.profitHitBox:EnableMouse(true)
	row.profitHitBox:SetScript("OnEnter", function()
		Pane:ShowProfitTooltip(row)
	end)
	row.profitHitBox:SetScript("OnLeave", GameTooltip_Hide)
	row.profitHitBox:SetScript("OnMouseUp", function()
		Pane:ViewOrder(row.order)
	end)

	row.timeLeft = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.timeLeft:SetPoint("TOPLEFT", row, "TOPLEFT", SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + REWARD_WIDTH + PROFIT_WIDTH + 8, -10)
	row.timeLeft:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.timeLeft:SetJustifyH("LEFT")

	row:SetScript("OnClick", function(self)
		Pane:ViewOrder(self.order)
	end)

	return row
end

function Pane:EnsureRowCount(count)
	while #self.rows < count do
		self:CreateRow(#self.rows + 1)
	end
end

function Pane:EnsureIconCount(row, bucketName, count)
	local bucket = row[bucketName]
	while #bucket < count do
		local icon = self:CreateIcon(row)
		icon.row = row
		bucket[#bucket + 1] = icon
	end
end

function Pane:UpdateHeaderArrow()
	if not self.sortArrow or not self.headers then
		return
	end

	local header = self.headers[self.sortKey]
	if not header then
		self.sortArrow:Hide()
		return
	end

	self.sortArrow:ClearAllPoints()
	self.sortArrow:SetParent(header)
	self.sortArrow:SetPoint("LEFT", header:GetFontString(), "RIGHT", 4, 0)
	local isAscending
	if self.sortKey == "reward" or self.sortKey == "profit" then
		isAscending = self.sortAscending
	else
		isAscending = not self.sortAscending
	end
	self.sortArrow:SetTexCoord(0, 1, isAscending and 1 or 0, isAscending and 0 or 1)
	self.sortArrow:Show()
end

function Pane:UpdateToolbar()
	local provider = Pricing:GetActiveProvider()
	local selectedCount = 0

	for _, order in ipairs(self.orders) do
		if self.selectedOrderIDs[order.orderID] then
			selectedCount = selectedCount + 1
		end
	end

	self.createListButton:SetText("+")

	if provider and provider.key == "auctioneer" then
		self.createListButton.tooltipTitle = L.TOOLBAR_EXPORT_SHOPPING_LIST
		self.createListButton.tooltipText = L.TOOLBAR_EXPORT_AUCTIONEER_TOOLTIP
	elseif provider then
		self.createListButton.tooltipTitle = L.TOOLBAR_CREATE_SHOPPING_LIST
		self.createListButton.tooltipText = L.TOOLBAR_CREATE_AUCTIONATOR_TOOLTIP
	else
		self.createListButton.tooltipTitle = L.TOOLBAR_SHOPPING_LIST_UNAVAILABLE
		self.createListButton.tooltipText = L.TOOLBAR_INSTALL_PRICING_TOOLTIP
	end

	if selectedCount == 0 then
		if provider then
			self.createListButton.tooltipText = L.TOOLBAR_SELECT_ORDERS_TOOLTIP
		else
			self.createListButton.tooltipText = L.TOOLBAR_INSTALL_AND_SELECT_TOOLTIP
		end
	end
	self.createListButton:SetEnabled(selectedCount > 0 and provider ~= nil)

	if self.filterButton then
		SetFallbackFilterButtonLabel(self.filterButton, L.TOOLBAR_FILTER_BUTTON)
		self.filterButton.tooltipTitle = L.TOOLBAR_FILTER_MENU
		self.filterButton.tooltipText = L.TOOLBAR_FILTER_TOOLTIP
		self.filterButton.recipeFilterLabel = self:GetRecipeFilterLabel()
		self.filterButton.concentrationFilterLabel = self:GetConcentrationFilterLabel()
	end

	self:UpdateFilterPanel()
end

function Pane:CollectShoppingEntries()
	local grouped = {}
	local selectedOrders = 0
	local skippedEntries = 0

	for _, order in ipairs(self.orders) do
		if self.selectedOrderIDs[order.orderID] then
			selectedOrders = selectedOrders + 1
			for _, materialEntry in ipairs(GetMaterialPlanEntries(order)) do
				local option = materialEntry.option
				if option and option.itemID and self:IsDontBuyItem(option.itemID) then
					skippedEntries = skippedEntries + 1
				elseif option and option.itemID and option.isMarketable ~= false then
					local refreshedLink = Util.GetItemLink(option.itemID)
					local itemLink = LinkHasDisplayName(option.itemLink) and option.itemLink or refreshedLink
					local itemIdentity = GetReagentItemIdentity(option.itemID, itemLink)
					local reagentQuality = option.reagentQuality
						or Util.GetProfessionItemQuality(itemIdentity)
						or Util.GetProfessionItemQuality(option.itemID)
					local groupKey = GetShoppingEntryGroupKey({
						itemID = option.itemID,
						reagentQuality = reagentQuality,
					})
					local bucket = grouped[groupKey]
					if not bucket then
						bucket = {
							itemID = option.itemID,
							itemLink = itemLink,
							itemIdentity = itemIdentity,
							name = option.name,
							reagentQuality = reagentQuality,
							required = 0,
							unitPrice = option.unitPrice,
							isMarketable = option.isMarketable,
						}
						grouped[groupKey] = bucket
					elseif LinkHasDisplayName(itemLink) and not LinkHasDisplayName(bucket.itemLink) then
						bucket.itemLink = itemLink
						bucket.itemIdentity = itemIdentity
					end
					bucket.required = bucket.required + (materialEntry.quantity or 0)
					bucket.unitPrice = bucket.unitPrice or option.unitPrice
				end
			end
		end
	end

	local export = {}
	for _, entry in pairs(grouped) do
		local owned = Util.GetQualityAwareItemCounts(entry.itemID, entry.itemLink)
		local missing = math.max(0, entry.required - owned)
		if missing > 0 then
			entry.quantity = missing
			export[#export + 1] = entry
		end
	end

	table.sort(export, function(left, right)
		return (left.name or UNKNOWN) < (right.name or UNKNOWN)
	end)

	return export, selectedOrders, skippedEntries
end

function Pane:CreateShoppingList()
	local entries, selectedCount, skippedEntries = self:CollectShoppingEntries()
	if selectedCount == 0 then
		ns.Print(L.MSG_SELECT_ORDERS_FIRST)
		return
	end

	if #entries == 0 then
		if skippedEntries > 0 then
			ns.Print(L.MSG_NO_ITEMS_AFTER_EXCLUSIONS)
		else
			ns.Print(L.MSG_ALREADY_HAVE_REAGENTS)
		end
		return
	end

	local listName = LF("SHOPPING_LIST_NAME_FORMAT", Util.GetLocalTimeStamp())
	local ok, message = Pricing:ExportShoppingList(entries, listName)
	ns.Print(ok and message or LF("MSG_SHOPPING_LIST_EXPORT_FAILED_FORMAT", message or UNKNOWN))
end

function Pane:ApplyReferenceLayout()
	if not self.root then
		return
	end

	local browseFrame = ProfessionsFrame and ProfessionsFrame.OrdersPage and ProfessionsFrame.OrdersPage.BrowseFrame
	if not browseFrame then
		return
	end

	self.root:ClearAllPoints()
	self.root:SetSize(ROOT_WIDTH, ROOT_HEIGHT)
	self.root:SetPoint("BOTTOMRIGHT", browseFrame, "BOTTOMRIGHT", ROOT_RIGHT_OFFSET, ROOT_BOTTOM_OFFSET)
end

function Pane:ApplyLeftFilterButtonVisuals()
	if not self.root or not self.filterButton then
		return
	end

	local source = FindLeftRecipeFilterButton(self.root)
	if source and CopyFilterButtonVisuals(source, self.filterButton) then
		return
	end

	CreateFallbackFilterButtonVisuals(self.filterButton, L.TOOLBAR_FILTER_BUTTON)
	SetFallbackFilterButtonVisualsShown(self.filterButton, true)
end

function Pane:BuildFrame()
	if self.root then
		return true
	end

	local browseFrame = ProfessionsFrame and ProfessionsFrame.OrdersPage and ProfessionsFrame.OrdersPage.BrowseFrame
	if not browseFrame then
		return false
	end

	local root = CreateFrame("Frame", "CraftingOrdersPlusPlusBrowsePane", browseFrame)
	root:Hide()

	local background = root:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas("auctionhouse-background-index", false)
	background:SetPoint("TOPLEFT", 3, BACKGROUND_TOP_OFFSET)
	background:SetPoint("BOTTOMRIGHT", -4, 0)

	self.createListButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
	self.createListButton:SetPoint("TOPLEFT", root, "TOPLEFT", CREATE_LIST_BUTTON_LEFT_OFFSET, CREATE_LIST_BUTTON_TOP_OFFSET)
	self.createListButton:SetSize(CREATE_LIST_BUTTON_WIDTH, CREATE_LIST_BUTTON_HEIGHT)
	self.createListButton:SetText("+")
	self.createListButton:SetNormalFontObject(GameFontNormalSmall)
	self.createListButton:SetHighlightFontObject(GameFontHighlightSmall)
	self.createListButton:SetMotionScriptsWhileDisabled(true)
	self.createListButton:SetScript("OnClick", function()
		Pane:CreateShoppingList()
	end)
	self.createListButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tooltipTitle or L.TOOLBAR_CREATE_SHOPPING_LIST)
		GameTooltip:AddLine(self.tooltipText or L.TOOLBAR_SELECT_ORDERS_TOOLTIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	self.createListButton:SetScript("OnLeave", GameTooltip_Hide)

	self.filterButton = CreateBlizzardFilterButton(root)
	self.filterButton:SetPoint("TOPRIGHT", root, "TOPRIGHT", FILTER_BUTTON_RIGHT_OFFSET, FILTER_BUTTON_TOP_OFFSET)
	self.filterButton:SetSize(FILTER_BUTTON_WIDTH, FILTER_BUTTON_HEIGHT)
	self.filterButton:SetMotionScriptsWhileDisabled(true)
	CreateFallbackFilterButtonVisuals(self.filterButton, L.TOOLBAR_FILTER_BUTTON)
	self.filterButton:SetScript("OnClick", function()
		Pane:ToggleFilterPanel()
	end)
	self.filterButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(self.tooltipTitle or L.TOOLBAR_FILTER_MENU)
		GameTooltip:AddLine(self.tooltipText or L.TOOLBAR_FILTER_TOOLTIP, 1, 1, 1, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L.FILTER_RECIPE_HEADER, self.recipeFilterLabel or Pane:GetRecipeFilterLabel(), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine(L.FILTER_CONCENTRATION_HEADER, self.concentrationFilterLabel or Pane:GetConcentrationFilterLabel(), 1, 1, 1, 1, 1, 1)
		GameTooltip:Show()
	end)
	self.filterButton:SetScript("OnLeave", function(self)
		GameTooltip_Hide()
	end)

	self.filterPanel = CreateFrame("Frame", nil, root, BackdropTemplateMixin and "BackdropTemplate" or nil)
	self.filterPanel:SetPoint("TOPRIGHT", self.filterButton, "BOTTOMRIGHT", 0, -4)
	self.filterPanel:SetSize(FILTER_PANEL_WIDTH, FILTER_PANEL_HEIGHT)
	self.filterPanel:SetFrameStrata("DIALOG")
	self.filterPanel:SetFrameLevel(root:GetFrameLevel() + 20)
	if type(self.filterPanel.SetBackdrop) == "function" then
		self.filterPanel:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = {
				left = 4,
				right = 4,
				top = 4,
				bottom = 4,
			},
		})
		self.filterPanel:SetBackdropColor(0.02, 0.02, 0.02, 0.92)
		self.filterPanel:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
	end
	self.filterPanel:Hide()

	self.filterPanel.recipeHeader = self.filterPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	self.filterPanel.recipeHeader:SetPoint("TOPLEFT", self.filterPanel, "TOPLEFT", 12, -12)
	self.filterPanel.recipeHeader:SetWidth(FILTER_PANEL_WIDTH - 28)
	self.filterPanel.recipeHeader:SetJustifyH("LEFT")
	self.filterPanel.recipeHeader:SetText(L.FILTER_RECIPE_HEADER)

	self.recipeFilterButtons = {
		[RECIPE_FILTER_KNOWN] = CreateFilterMenuToggle(self.filterPanel, L.FILTER_RECIPE_KNOWN, self.filterPanel.recipeHeader, -17),
	}

	self.recipeFilterButtons[RECIPE_FILTER_KNOWN]:SetScript("OnClick", function()
		Pane:SetRecipeFilter(Pane.recipeFilter == RECIPE_FILTER_KNOWN and RECIPE_FILTER_ALL or RECIPE_FILTER_KNOWN)
	end)

	self.filterPanel.concentrationHeader = self.filterPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	self.filterPanel.concentrationHeader:SetPoint("TOPLEFT", self.recipeFilterButtons[RECIPE_FILTER_KNOWN], "BOTTOMLEFT", 2, -12)
	self.filterPanel.concentrationHeader:SetWidth(FILTER_PANEL_WIDTH - 28)
	self.filterPanel.concentrationHeader:SetJustifyH("LEFT")
	self.filterPanel.concentrationHeader:SetText(L.FILTER_CONCENTRATION_HEADER)

	self.concentrationFilterButtons = {
		[CONCENTRATION_FILTER_NONE] = CreateFilterMenuToggle(self.filterPanel, L.FILTER_CONCENTRATION_NONE, self.filterPanel.concentrationHeader, -17),
	}

	self.concentrationFilterButtons[CONCENTRATION_FILTER_NONE]:SetScript("OnClick", function()
		Pane:SetConcentrationFilter(Pane.concentrationFilter == CONCENTRATION_FILTER_NONE and CONCENTRATION_FILTER_ALL or CONCENTRATION_FILTER_NONE)
	end)

	self.headers = {
		order = CreateHeaderButton(root, L.HEADER_YOU_CRAFT_SUPPLY, "order", ORDER_WIDTH, SELECT_WIDTH + 2),
		cost = CreateHeaderButton(root, L.HEADER_COST, "cost", COST_WIDTH, SELECT_WIDTH + ORDER_WIDTH + 2),
		reward = CreateHeaderButton(root, L.HEADER_REWARD, "reward", REWARD_WIDTH, SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + 2),
		profit = CreateHeaderButton(root, L.HEADER_PROFIT, "profit", PROFIT_WIDTH, SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + REWARD_WIDTH + 2),
		time = CreateHeaderButton(root, GetTimeHeaderText(), "time", PATRON_WIDTH, SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + REWARD_WIDTH + PROFIT_WIDTH + 2),
	}

	for _, header in pairs(self.headers) do
		header:SetScript("OnClick", function(button, mouseButton)
			local sortAscending
			if Pane.sortKey == button.sortKey then
				sortAscending = mouseButton == "RightButton" and true or not Pane.sortAscending
			else
				sortAscending = mouseButton == "RightButton"
			end
			Pane:SetSort(button.sortKey, sortAscending)
		end)
	end

	self.sortArrow = root:CreateTexture(nil, "ARTWORK")
	self.sortArrow:SetAtlas("auctionhouse-ui-sortarrow", true)

	local scrollBarInset = 10
	local scrollBarGap = 10

	self.scrollFrame = CreateFrame("Frame", nil, root, "WowScrollBoxList")
	self.scrollFrame:SetPoint("TOPLEFT", root, "TOPLEFT", 0, SCROLL_TOP_OFFSET)

	self.scrollBar = CreateFrame("EventFrame", nil, root, "MinimalScrollBar")
	self.scrollBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -scrollBarInset, SCROLL_TOP_OFFSET)
	self.scrollBar:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -scrollBarInset, 10)

	self.scrollFrame:SetPoint("TOPRIGHT", self.scrollBar, "TOPLEFT", -scrollBarGap, 0)
	self.scrollFrame:SetPoint("BOTTOMRIGHT", self.scrollBar, "BOTTOMLEFT", -scrollBarGap, 0)

	if self.scrollFrame.SetInterpolateScroll then
		self.scrollFrame:SetInterpolateScroll(true)
	end
	if self.scrollBar.SetInterpolateScroll then
		self.scrollBar:SetInterpolateScroll(true)
	end

	local scrollView = CreateScrollBoxListLinearView()
	scrollView:SetElementExtent(ROW_HEIGHT)
	if scrollView.SetPadding then
		scrollView:SetPadding(0, 0, 0, 0, 0)
	end
	scrollView:SetElementInitializer("Button", function(button, elementData)
		Pane:CreateRow(elementData and elementData.index, button)
		Pane:ApplyRowData(button, elementData)
	end)
	if scrollView.SetElementResetter then
		scrollView:SetElementResetter(function(button)
			button.order = nil
		end)
	end

	ScrollUtil.InitScrollBoxListWithScrollBar(self.scrollFrame, self.scrollBar, scrollView)
	self.orderDataProvider = CreateDataProvider()
	self.scrollFrame:SetDataProvider(self.orderDataProvider)
	self.rows = {}

	self.noOrders = root:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
	self.noOrders:SetPoint("CENTER", self.scrollFrame, "CENTER", 0, 40)
	self.noOrders:SetText(EMPTY_STATE_EMPTY_TEXT)
	self.noOrders:Hide()

	root:SetScript("OnShow", function()
		Pane:ApplyReferenceLayout()
		Pane:ApplyLeftFilterButtonVisuals()
		C_Timer.After(0, function()
			if Pane and Pane.root and Pane.root:IsShown() then
				Pane:ApplyLeftFilterButtonVisuals()
				Pane:UpdateScrollBox()
			end
		end)
		Pane:BeginVisibleSession()
		Pane:MarkDirty("show")
	end)
	root:SetScript("OnUpdate", function(_, elapsed)
		Pane.elapsedSinceTick = (Pane.elapsedSinceTick or 0) + elapsed

		if Pane.pendingDueAt and GetTime() >= Pane.pendingDueAt then
			Pane.pendingDueAt = nil
			Pane:ProcessPendingRefresh()
		end

		if Pane.root:IsShown() and Pane.elapsedSinceTick > 30 then
			Pane.elapsedSinceTick = 0
			Pane:UpdateTimeLabels()
		end
	end)

	self.root = root
	self:ApplyReferenceLayout()

	if not self.layoutHooked then
		self.layoutHooked = true
		browseFrame:HookScript("OnSizeChanged", function()
			Pane:ApplyReferenceLayout()
		end)
	end

	return true
end

function Pane:GetVisibleRawOrders()
	local rawOrders = {}
	for _, rawOrder in ipairs(C_CraftingOrders.GetCrafterOrders() or EMPTY_LIST) do
		if rawOrder.orderType == ns.ORDER_TYPE_NPC then
			rawOrders[#rawOrders + 1] = rawOrder
		end
	end

	return rawOrders
end

function Pane:GetCurrentProfessionID()
	local ordersPage = ProfessionsFrame and ProfessionsFrame.OrdersPage
	local professionInfo = ordersPage and ordersPage.professionInfo
	if professionInfo and professionInfo.profession then
		return professionInfo.profession
	end

	if type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.GetChildProfessionInfo) == "function" then
		professionInfo = C_TradeSkillUI.GetChildProfessionInfo()
		if professionInfo and professionInfo.profession then
			return professionInfo.profession
		end
	end

	if type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
		professionInfo = C_TradeSkillUI.GetBaseProfessionInfo()
		if professionInfo and professionInfo.profession then
			return professionInfo.profession
		end
	end

	return nil
end

function Pane:HideAllRows()
	for _, row in ipairs(self.rows or {}) do
		row:Hide()
		row.order = nil
	end

	if self.orderDataProvider then
		self.orderDataProvider:Flush()
	end
	self:UpdateScrollBox()
end

function Pane:SetRowIcons(row, bucketName, startX, yOffset, items)
	self:EnsureIconCount(row, bucketName, #items)

	local xOffset = startX
	for index, icon in ipairs(row[bucketName]) do
		local item = items[index]
		if item then
			if item.leadingSpacer then
				xOffset = xOffset + ICON_GROUP_SPACER
			end
			icon:SetPoint("TOPLEFT", row, "TOPLEFT", xOffset, yOffset)
			self:SetIconData(icon, item)
			xOffset = xOffset + REAGENT_ICON_SIZE + 2
		else
			icon:Hide()
			icon.data = nil
		end
	end
end

function Pane:GetFlagText(order)
	local parts = {}
	if order.firstCraft then
		parts[#parts + 1] = "|A:Professions_Icon_FirstTimeCraft:14:12:0:1|a"
	end
	if order.canSkillUp and order.relativeDifficulty ~= nil then
		local atlas = ({
			[0] = "Professions-Icon-Skill-High",
			[1] = "Professions-Icon-Skill-Medium",
			[2] = "Professions-Icon-Skill-Low",
		})[order.relativeDifficulty]
		if atlas then
			parts[#parts + 1] = ("|A:%s:13:14|a %s"):format(atlas, order.skillUps > 1 and order.skillUps or "")
		end
	end
	return table.concat(parts, "  ")
end

function Pane:SortPreparedOrders()
	SortOrders(self.orders, self.sortKey, self.sortAscending)
end

function Pane:UpdateScrollBox()
	if self.scrollFrame and self.scrollFrame.FullUpdate then
		local updateImmediately = ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately or true
		self.scrollFrame:FullUpdate(updateImmediately)
	end
end

function Pane:ApplyRowData(row, elementData)
	local order = elementData and (elementData.order or elementData)
	if not row or not order then
		if row then
			row:Hide()
			row.order = nil
		end
		return
	end

	local index = elementData.index or row.rowIndex or 1
	row.rowIndex = index
	row.order = order
	row:Show()
	if row.background then
		row.background:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.025 or 0.01)
	end
	row.checkbox:SetChecked(not not self.selectedOrderIDs[order.orderID])

	local titleColor = WHITE_FONT_COLOR
	local desaturated = false
	local greyUnknown = not order.isKnown and ns.GetConfig("greyUnknownRecipes")
	if greyUnknown then
		titleColor = DISABLED_FONT_COLOR
		desaturated = true
	end
	row:SetAlpha(greyUnknown and 0.6 or 1)
	local inlineFlags = order.isKnown and self:GetFlagText(order) or ""
	if inlineFlags ~= "" then
		inlineFlags = "  " .. inlineFlags
	end
	row.title:SetText(order.product.label .. GetQualityIndicatorText(order) .. inlineFlags)
	row.title:SetTextColor(titleColor.r, titleColor.g, titleColor.b)
	row.flags:SetText("")
	row.flags:Hide()
	self:SetIconData(row.productIcon, {
		itemID = order.product.itemID,
		itemLink = order.product.itemLink,
		icon = order.product.icon,
		count = 1,
		isKnown = order.isKnown,
		desaturated = desaturated,
		extraLines = order.productTooltipLines,
		unknownRecipeLines = order.isKnown and nil or order.unknownRecipeTooltip,
	})

	local reagentIcons = {}
	for _, entry in ipairs(GetMaterialPlanEntries(order)) do
		local option = entry.option
		if option then
			reagentIcons[#reagentIcons + 1] = {
				itemID = option.itemID,
				itemLink = option.itemLink,
				icon = select(5, C_Item.GetItemInfoInstant(option.itemID)),
				count = entry.quantity,
				alwaysShowCount = true,
				name = option.name,
				reagentQuality = option.reagentQuality,
				borderAtlas = option.borderAtlas,
				shortage = entry.shortage,
				availableTotal = entry.availableTotal,
				selectedQualityOwnedCount = entry.selectedQualityOwnedCount,
				otherQualityOwnedCount = entry.otherQualityOwnedCount,
				totalOwnedCount = entry.totalOwnedCount,
				unitPrice = option.unitPrice,
				totalPrice = entry.totalPrice,
				priceState = entry.priceState,
				doNotBuy = self:IsDontBuyItem(option.itemID),
				toggleDontBuy = true,
			}
		end
	end

	if order.concentration and order.concentration.currentCost and order.concentration.currencyID then
		local currencyBasic = C_CurrencyInfo.GetBasicCurrencyInfo(order.concentration.currencyID, order.concentration.currentCost)
		reagentIcons[#reagentIcons + 1] = {
			currencyID = order.concentration.currencyID,
			icon = currencyBasic and currencyBasic.icon,
			count = order.concentration.currentCost,
			alwaysShowCount = true,
			borderAtlas = GetBorderAtlas(nil, currencyBasic and currencyBasic.quality),
			leadingSpacer = #reagentIcons > 0,
			availableTotal = order.concentration.available,
			shortage = math.max(0, (order.concentration.currentCost or 0) - (order.concentration.available or 0)),
			extraLines = BuildConcentrationExtraLines(order.concentration),
		}
	end

	row.reagentLabel:Hide()
	self:SetRowIcons(row, "reagentIcons", SELECT_WIDTH + PRODUCT_ICON_LEFT_OFFSET + PRODUCT_ICON_SIZE + PRODUCT_TEXT_GAP, ROW_ICON_Y_OFFSET, reagentIcons)

	if #GetMaterialPlanEntries(order) == 0 then
		row.costText:SetText(NONE)
		row.costHint:SetText(L.COST_HINT_ALL_PROVIDED)
	elseif (order.marketableMaterialEntryCount or 0) == 0 and (order.excludedMaterialEntryCount or 0) > 0 then
		row.costText:SetText(NONE)
		row.costHint:SetText(L.PRICE_NOT_MARKETABLE)
	elseif order.materialCostKnown then
		local costText = FormatListMoney(order.materialCost)
		if not order.materialCostComplete then
			costText = costText .. "*"
		end
		row.costText:SetText(costText)
		row.costHint:SetText(order.materialCostComplete and L.COST_HINT_ALL_PRICED or L.COST_HINT_PARTIAL_PRICING)
	else
		row.costText:SetText(NONE)
		row.costHint:SetText(L.PRICE_NO_MARKET_DATA)
	end

	row.rewardText:SetText(order.reward.gold > 0 and FormatListMoney(order.reward.gold) or NONE)
	row.rewardValue:SetText("")

	if order.profitKnown then
		local profitText = FormatListMoney(order.profitValue or 0, true)
		if not order.profitComplete then
			profitText = profitText .. "*"
		end
		row.profitText:SetText(profitText)
		if (order.profitValue or 0) < 0 then
			row.profitText:SetTextColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
		else
			row.profitText:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
		end
	else
		row.profitText:SetText(NONE)
		row.profitText:SetTextColor(DISABLED_FONT_COLOR.r, DISABLED_FONT_COLOR.g, DISABLED_FONT_COLOR.b)
	end

	for _, icon in ipairs(order.reward.icons) do
		if icon.itemID and not icon.icon then
			icon.icon = select(5, C_Item.GetItemInfoInstant(icon.itemID))
		end
	end
	self:SetRowIcons(row, "rewardIcons", SELECT_WIDTH + ORDER_WIDTH + COST_WIDTH + 8, ROW_ICON_Y_OFFSET, order.reward.icons)

	local secondsRemaining = math.max(0, (order.expirationTime or 0) - C_CraftingOrders.GetCraftingOrderTime())
	local red, green, blue = GetTimeColor(secondsRemaining)
	row.timeLeft:SetText(FormatTimeRemaining(secondsRemaining))
	row.timeLeft:SetTextColor(red, green, blue)
end

function Pane:RenderRows()
	self.rowData = self.rowData or {}
	wipe(self.rowData)
	for index, order in ipairs(self.orders) do
		self.rowData[index] = {
			order = order,
			index = index,
		}
	end

	if self.orderDataProvider then
		self.orderDataProvider:Flush()
		if #self.rowData > 0 then
			self.orderDataProvider:InsertTable(self.rowData)
		end
	end

	self:UpdateScrollBox()
	C_Timer.After(0, function()
		if Pane and Pane.root and Pane.root:IsShown() then
			Pane:UpdateScrollBox()
		end
	end)
	self:UpdateEmptyState()
	self:UpdateHeaderArrow()
	self:UpdateToolbar()
end

function Pane:UpdateTimeLabels()
	for _, row in ipairs(self.rows) do
		if row:IsShown() and row.order then
			local secondsRemaining = math.max(0, (row.order.expirationTime or 0) - C_CraftingOrders.GetCraftingOrderTime())
			local red, green, blue = GetTimeColor(secondsRemaining)
			row.timeLeft:SetText(FormatTimeRemaining(secondsRemaining))
			row.timeLeft:SetTextColor(red, green, blue)
		end
	end
end

local function GetConfigKeyFromReason(reason)
	return type(reason) == "string" and reason:match("^config:(.+)$") or nil
end

local function DoesReasonBumpGeneration(reason)
	local configKey = GetConfigKeyFromReason(reason)
	return reason == "pricing-db"
		or reason == "trade-skill-source"
		or configKey == "pricingSource"
end

local function IsRenderOnlyConfigKey(configKey)
	return configKey == "greyUnknownRecipes"
		or configKey == "showSilverCopperInList"
		or configKey == "dontBuyPerCharacter"
end

function Pane:GetRecipeFilterLabel(filterKey)
	filterKey = NormalizeRecipeFilter(filterKey or self.recipeFilter)
	if filterKey == RECIPE_FILTER_KNOWN then
		return L.FILTER_RECIPE_KNOWN
	elseif filterKey == RECIPE_FILTER_UNKNOWN then
		return L.FILTER_RECIPE_UNKNOWN
	end

	return L.FILTER_RECIPE_ALL
end

function Pane:GetConcentrationFilterLabel(filterKey)
	filterKey = NormalizeConcentrationFilter(filterKey or self.concentrationFilter)
	if filterKey == CONCENTRATION_FILTER_NEEDS then
		return L.FILTER_CONCENTRATION_NEEDS
	elseif filterKey == CONCENTRATION_FILTER_NONE then
		return L.FILTER_CONCENTRATION_NONE
	end

	return L.FILTER_CONCENTRATION_ALL
end

function Pane:HasActiveFilters()
	return NormalizeRecipeFilter(self.recipeFilter) ~= RECIPE_FILTER_ALL
		or NormalizeConcentrationFilter(self.concentrationFilter) ~= CONCENTRATION_FILTER_ALL
end

function Pane:DoesOrderMatchFilters(orderData)
	if not orderData then
		return false
	end

	local recipeFilter = NormalizeRecipeFilter(self.recipeFilter)
	if recipeFilter == RECIPE_FILTER_KNOWN and not orderData.isKnown then
		return false
	elseif recipeFilter == RECIPE_FILTER_UNKNOWN and orderData.isKnown then
		return false
	end

	local concentrationFilter = NormalizeConcentrationFilter(self.concentrationFilter)
	local needsConcentration = DoesOrderNeedConcentration(orderData)
	if concentrationFilter == CONCENTRATION_FILTER_NEEDS and not needsConcentration then
		return false
	elseif concentrationFilter == CONCENTRATION_FILTER_NONE and needsConcentration then
		return false
	end

	return true
end

function Pane:ApplyOrderFilters()
	local filteredOrders = {}
	for _, order in ipairs(self.allOrders or EMPTY_LIST) do
		if self:DoesOrderMatchFilters(order) then
			filteredOrders[#filteredOrders + 1] = order
		end
	end

	self.orders = filteredOrders
end

function Pane:SetRecipeFilter(filterKey)
	filterKey = NormalizeRecipeFilter(filterKey)
	local db = ns.GetDatabase and ns.GetDatabase()
	if type(db) == "table" then
		db.patronRecipeFilter = filterKey
	end

	if self.recipeFilter == filterKey then
		self:UpdateFilterPanel()
		return
	end

	self.recipeFilter = filterKey
	self:UpdateFilterPanel()
	self:MarkDirty("filter")
end

function Pane:SetConcentrationFilter(filterKey)
	filterKey = NormalizeConcentrationFilter(filterKey)
	local db = ns.GetDatabase and ns.GetDatabase()
	if type(db) == "table" then
		db.patronConcentrationFilter = filterKey
	end

	if self.concentrationFilter == filterKey then
		self:UpdateFilterPanel()
		return
	end

	self.concentrationFilter = filterKey
	self:UpdateFilterPanel()
	self:MarkDirty("filter")
end

function Pane:SetSort(sortKey, sortAscending)
	sortKey = NormalizeSortKey(sortKey)
	sortAscending = sortAscending == true
	local db = ns.GetDatabase and ns.GetDatabase()
	if type(db) == "table" then
		db.patronSortKey = sortKey
		db.patronSortAscending = sortAscending
	end

	if self.sortKey == sortKey and self.sortAscending == sortAscending then
		self:UpdateHeaderArrow()
		return
	end

	self.sortKey = sortKey
	self.sortAscending = sortAscending
	self:MarkDirty("sort")
end

function Pane:LoadSavedFilters()
	self.recipeFilter = NormalizeRecipeFilter(ns.GetConfig and ns.GetConfig("patronRecipeFilter") or self.recipeFilter)
	self.concentrationFilter = NormalizeConcentrationFilter(ns.GetConfig and ns.GetConfig("patronConcentrationFilter") or self.concentrationFilter)
	self:UpdateFilterPanel()
end

function Pane:LoadSavedSort()
	self.sortKey = NormalizeSortKey(ns.GetConfig and ns.GetConfig("patronSortKey") or self.sortKey)
	self.sortAscending = (ns.GetConfig and ns.GetConfig("patronSortAscending")) == true
	self:UpdateHeaderArrow()
end

function Pane:UpdateFilterPanel()
	if not self.filterPanel then
		return
	end

	if self.recipeFilterButtons then
		local recipeFilter = NormalizeRecipeFilter(self.recipeFilter)
		SetFilterMenuToggleChecked(self.recipeFilterButtons[RECIPE_FILTER_KNOWN], recipeFilter == RECIPE_FILTER_KNOWN)
	end

	if self.concentrationFilterButtons then
		local concentrationFilter = NormalizeConcentrationFilter(self.concentrationFilter)
		SetFilterMenuToggleChecked(self.concentrationFilterButtons[CONCENTRATION_FILTER_NONE], concentrationFilter == CONCENTRATION_FILTER_NONE)
	end
end

function Pane:ToggleFilterPanel()
	if not self.filterPanel then
		return
	end

	if self.filterPanel:IsShown() then
		self.filterPanel:Hide()
		return
	end

	self:UpdateFilterPanel()
	self.filterPanel:Show()
end

local function GetReasonPriority(reason)
	if reason == "show" or reason == "order-type" or reason == "can-request" or reason == "request-timeout" or reason == "request-success" then
		return 3
	end
	if reason == "pricing-db" or reason == "trade-skill-source" or reason == "order-count" or reason == "rewards" or reason == "item-data" then
		return 2
	end
	if GetConfigKeyFromReason(reason) then
		return 2
	end
	if reason == "sort" or reason == "filter" then
		return 1
	end
	return 0
end

function Pane:HasVisibleOrdersForProfession(profession)
	local orders = self.allOrders or self.orders or EMPTY_LIST
	return profession ~= nil
		and self.ordersProfession == profession
		and #orders > 0
end

function Pane:HasSuccessfulRequestForVisibleSession(profession)
	local requestInfo = self.lastSuccessfulRequest
	return requestInfo ~= nil
		and requestInfo.visibleSessionId == self.visibleSessionId
		and requestInfo.profession == profession
end

function Pane:HasTimedOutRequestForVisibleSession(profession)
	local requestInfo = self.lastTimedOutRequest
	return requestInfo ~= nil
		and requestInfo.visibleSessionId == self.visibleSessionId
		and requestInfo.profession == profession
end

function Pane:NeedsPreparedOrderRebuild(profession)
	return profession ~= nil
		and self.ordersProfession == profession
		and (self.ordersGeneration or 0) ~= (self.rebuildGeneration or 0)
end

function Pane:PruneSelectedOrders()
	local validSelection = {}
	for _, order in ipairs(self.allOrders or self.orders or EMPTY_LIST) do
		if self.selectedOrderIDs[order.orderID] then
			validSelection[order.orderID] = true
		end
	end

	self.selectedOrderIDs = validSelection
end

function Pane:ClearVisibleOrders(profession)
	self.allOrders = {}
	self.orders = {}
	self.ordersProfession = profession
	self.ordersGeneration = self.rebuildGeneration or 0
	self.selectedOrderIDs = {}
	self.hasUnresolvedItemData = false
	self.unresolvedItemIDs = {}
	self:HideAllRows()
end

function Pane:SetVisibleProfession(profession)
	local changed = self.visibleProfession ~= profession
	if changed then
		self.visibleProfession = profession
	end

	if self.requesting
		and self.activeRequestProfession
		and self.activeRequestProfession ~= profession then
		self:ClearRequestState()
	end

	if changed and self.root and self.root:IsShown() and self.ordersProfession ~= profession then
		self:ClearVisibleOrders(profession)
	end

	return changed
end

function Pane:BeginVisibleSession()
	self:LoadSavedFilters()
	self:LoadSavedSort()
	self.visibleSessionId = (self.visibleSessionId or 0) + 1
	self.requestSettleUntil = nil
	self.requestReadinessRetryCount = 0
	self:SetVisibleProfession(self:GetCurrentProfessionID())
end

function Pane:BumpPreparedOrderGeneration()
	self.rebuildGeneration = (self.rebuildGeneration or 0) + 1
end

function Pane:ChoosePendingReason(reason)
	if not reason then
		return
	end

	if not self.pendingReason or GetReasonPriority(reason) >= GetReasonPriority(self.pendingReason) then
		self.pendingReason = reason
	end
end

function Pane:SchedulePendingRefresh(reason, delay)
	if not (self.root and self.root:IsShown()) then
		return
	end

	local dueAt = GetTime() + (delay or GetRefreshDelay(reason))
	if self.needsRebuild and self.requestSettleUntil then
		dueAt = math.max(dueAt, self.requestSettleUntil)
	end

	if not self.pendingDueAt or dueAt < self.pendingDueAt then
		self.pendingDueAt = dueAt
	end

	self:ChoosePendingReason(reason)
	self:UpdateEmptyState()
end

function Pane:ScheduleRequestReadinessRetry(reason)
	if (self.requestReadinessRetryCount or 0) >= REQUEST_READINESS_RETRY_LIMIT then
		self:UpdateEmptyState()
		return false
	end

	self.requestReadinessRetryCount = (self.requestReadinessRetryCount or 0) + 1
	self:SchedulePendingRefresh(reason or "show", REQUEST_READINESS_RETRY_DELAY)
	self:UpdateEmptyState()
	return true
end

function Pane:ShouldQueueOpenRequest(profession)
	if not profession then
		return false
	end

	return self.ordersProfession ~= profession
		or not self:HasVisibleOrdersForProfession(profession)
		or not self:HasSuccessfulRequestForVisibleSession(profession)
		or self:HasTimedOutRequestForVisibleSession(profession)
end

function Pane:IsLoadingOrders()
	return not not self.requesting
		or not not self.needsRequest
end

function Pane:UpdateEmptyState()
	if not self.noOrders then
		return
	end

	local hasOrders = #(self.orders or EMPTY_LIST) > 0
	local hasPreparedOrders = #(self.allOrders or EMPTY_LIST) > 0
	local isLoading = not hasOrders and self:IsLoadingOrders()
	local emptyText = EMPTY_STATE_EMPTY_TEXT
	if not isLoading and not hasOrders and hasPreparedOrders and self:HasActiveFilters() then
		emptyText = EMPTY_STATE_FILTERED_TEXT
	end

	self.noOrders:SetText(isLoading and EMPTY_STATE_LOADING_TEXT or emptyText)
	if isLoading then
		self.noOrders:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	else
		self.noOrders:SetTextColor(DISABLED_FONT_COLOR.r, DISABLED_FONT_COLOR.g, DISABLED_FONT_COLOR.b)
	end

	self.noOrders:SetShown(not hasOrders)
end

function Pane:MarkDirty(reason)
	reason = reason or "update"

	local isVisible = self.root and self.root:IsShown()
	local currentProfession = isVisible and self:GetCurrentProfessionID() or self.visibleProfession
	local professionChanged = false
	local configKey = GetConfigKeyFromReason(reason)

	if DoesReasonBumpGeneration(reason) or (reason == "item-data" and self.hasUnresolvedItemData) then
		self:BumpPreparedOrderGeneration()
	end

	if isVisible then
		professionChanged = self:SetVisibleProfession(currentProfession)
	end

	if reason == "sort" or reason == "filter" then
		self.needsRender = true
	elseif reason == "show" or reason == "order-type" or reason == "can-request" or reason == "request-timeout" then
		if currentProfession == nil or self:ShouldQueueOpenRequest(currentProfession) then
			self.needsRequest = true
		end
		if self:NeedsPreparedOrderRebuild(currentProfession) then
			self.needsRebuild = true
		end
	elseif reason == "request-success" or reason == "order-count" or reason == "rewards" or reason == "pricing-db" then
		self.needsRebuild = true
	elseif reason == "item-data" then
		if self.hasUnresolvedItemData then
			self.needsRebuild = true
		end
	elseif reason == "trade-skill-source" then
		if professionChanged or currentProfession == nil or not self:HasSuccessfulRequestForVisibleSession(currentProfession) then
			self.needsRequest = true
		else
			self.needsRebuild = true
		end
	elseif configKey == "pricingSource" then
		self.needsRebuild = true
	elseif IsRenderOnlyConfigKey(configKey) then
		self.needsRender = true
	end

	if not isVisible then
		return
	end

	if self.needsRequest or self.needsRebuild or self.needsRender then
		self:SchedulePendingRefresh(reason, GetRefreshDelay(reason))
	else
		self:UpdateEmptyState()
	end
end

function Pane:ClearRequestState(requestID)
	if requestID ~= nil and self.activeRequestID ~= requestID then
		return false
	end

	self.requesting = false
	self.activeRequestID = nil
	self.activeRequestProfession = nil
	self.activeRequestSessionId = nil
	self.activeRequestReason = nil
	self:UpdateEmptyState()
	return true
end

function Pane:StartRequestTimeout(requestID)
	C_Timer.After(REQUEST_TIMEOUT, function()
		if not Pane or Pane.activeRequestID ~= requestID then
			return
		end

		local timedOutProfession = Pane.activeRequestProfession
		local timedOutSessionId = Pane.activeRequestSessionId
		local professionMatches = timedOutProfession ~= nil
			and timedOutProfession == Pane:GetCurrentProfessionID()
		if timedOutProfession and timedOutSessionId then
			Pane.lastTimedOutRequest = {
				visibleSessionId = timedOutSessionId,
				profession = timedOutProfession,
			}
		end
		Pane:ClearRequestState(requestID)
		if professionMatches and Pane.root and Pane.root:IsShown() then
			Pane:MarkDirty("request-timeout")
		end
	end)
end

function Pane:RequestOrders(reason, profession)
	local now = GetTime()
	local requestID = (self.requestSerial or 0) + 1
	local requestSessionId = self.visibleSessionId
	self.requestSerial = requestID
	self.requestReadinessRetryCount = 0
	self.requesting = true
	self.activeRequestID = requestID
	self.activeRequestProfession = profession
	self.activeRequestSessionId = requestSessionId
	self.activeRequestReason = reason
	self:UpdateEmptyState()
	self.lastRequestAt = now
	self:StartRequestTimeout(requestID)
	C_CraftingOrders.RequestCrafterOrders({
		profession = profession,
		orderType = ns.ORDER_TYPE_NPC,
		forCrafter = true,
		offset = 0,
		searchFavorites = false,
		initialNonPublicSearch = false,
		primarySort = { sortType = 0, reversed = false },
		secondarySort = { sortType = 0, reversed = false },
		callback = function(result, orderType)
			local currentProfession = self:GetCurrentProfessionID()
			local isActiveRequest = self.activeRequestID == requestID
			local isCurrentSession = requestSessionId == self.visibleSessionId
			if isActiveRequest then
				self:ClearRequestState(requestID)
			end

			if result == 0
				and orderType == ns.ORDER_TYPE_NPC
				and profession == currentProfession
				and self.root
				and self.root:IsShown() then
				if isCurrentSession then
					self.lastSuccessfulRequest = {
						visibleSessionId = requestSessionId,
						profession = profession,
					}
					if self:HasTimedOutRequestForVisibleSession(profession) then
						self.lastTimedOutRequest = nil
					end
				end

				self.requestSettleUntil = GetTime() + REQUEST_SETTLE_DELAY
				self:MarkDirty("request-success")
			end
		end,
	})
end

function Pane:MaybeRequestOrders(reason)
	if not self.needsRequest then
		return false
	end

	local profession = self:GetCurrentProfessionID()
	if self.requesting then
		if self.activeRequestProfession == profession then
			self.needsRequest = false
		else
			self:ClearRequestState()
		end
		return false
	end

	local now = GetTime()
	if self.lastRequestAt and (now - self.lastRequestAt) < REQUEST_COOLDOWN then
		self:SchedulePendingRefresh(reason or "request-cooldown", (self.lastRequestAt + REQUEST_COOLDOWN) - now)
		self:UpdateEmptyState()
		return false
	end

	if not profession then
		self:ScheduleRequestReadinessRetry(reason)
		return false
	end

	if type(C_TradeSkillUI) ~= "table"
		or type(C_TradeSkillUI.IsNearProfessionSpellFocus) ~= "function"
		or not C_TradeSkillUI.IsNearProfessionSpellFocus(profession) then
		self:ScheduleRequestReadinessRetry(reason)
		return false
	end

	self.needsRequest = false
	self:RequestOrders(reason, profession)
	return true
end

function Pane:RebuildPreparedOrders()
	local currentProfession = self:GetCurrentProfessionID()
	local rawOrders = self:GetVisibleRawOrders()
	local preserveVisibleCache = #rawOrders == 0
		and self:HasVisibleOrdersForProfession(currentProfession)
		and self:IsLoadingOrders()

	if preserveVisibleCache then
		local hasUnresolvedItemData = false
		local unresolvedItemIDs = {}
		for _, order in ipairs(self.allOrders or self.orders or EMPTY_LIST) do
			if order.hasUnresolvedItemData then
				hasUnresolvedItemData = true
				for itemID in pairs(order.unresolvedItemIDs or EMPTY_LIST) do
					unresolvedItemIDs[itemID] = true
				end
			end
		end

		self.hasUnresolvedItemData = hasUnresolvedItemData
		self.unresolvedItemIDs = unresolvedItemIDs
		self.ordersProfession = currentProfession
		return false
	end

	local preparedOrders = {}
	local preparedOrderCache = {}
	local hasUnresolvedItemData = false
	local unresolvedItemIDs = {}

	for _, rawOrder in ipairs(rawOrders) do
		local fingerprint = BuildOrderFingerprint(rawOrder)
		local cacheEntry = self.preparedOrderCache[rawOrder.orderID]
		local orderData

		if cacheEntry
			and cacheEntry.fingerprint == fingerprint
			and cacheEntry.generation == self.rebuildGeneration then
			orderData = cacheEntry.data
			hasUnresolvedItemData = hasUnresolvedItemData or not not cacheEntry.hasUnresolvedItemData
		else
			orderData = PrepareOrder(rawOrder)
			hasUnresolvedItemData = hasUnresolvedItemData or not not (orderData and orderData.hasUnresolvedItemData)
		end

		if orderData then
			preparedOrders[#preparedOrders + 1] = orderData
			for itemID in pairs(orderData.unresolvedItemIDs or EMPTY_LIST) do
				unresolvedItemIDs[itemID] = true
			end
			preparedOrderCache[rawOrder.orderID] = {
				fingerprint = fingerprint,
				generation = self.rebuildGeneration,
				data = orderData,
				hasUnresolvedItemData = orderData.hasUnresolvedItemData or false,
			}
		end
	end

	self.preparedOrderCache = preparedOrderCache
	self.allOrders = preparedOrders
	self:ApplyOrderFilters()
	self.ordersProfession = currentProfession
	self.ordersGeneration = self.rebuildGeneration
	self.hasUnresolvedItemData = hasUnresolvedItemData
	self.unresolvedItemIDs = unresolvedItemIDs
	self:PruneSelectedOrders()
	return true
end

function Pane:ProcessPendingRefresh()
	if not (self.root and self.root:IsShown()) then
		return
	end

	local reason = self.pendingReason or "update"
	self.pendingReason = nil
	self:SetVisibleProfession(self:GetCurrentProfessionID())
	self:MaybeRequestOrders(reason)

	if self.needsRebuild then
		self.needsRebuild = false
		if self:RebuildPreparedOrders() then
			self.needsRender = true
		end
	end

	if self.needsRender then
		self.needsRender = false
		self:ApplyOrderFilters()
		self:SortPreparedOrders()
		self:RenderRows()
	else
		self:UpdateEmptyState()
		self:UpdateHeaderArrow()
		self:UpdateToolbar()
	end

	if self.requestSettleUntil and GetTime() >= self.requestSettleUntil then
		self.requestSettleUntil = nil
	end
end

function Pane:SetCustomPaneShown(isShown)
	if not self.root then
		return
	end

	if isShown then
		self:ApplyReferenceLayout()
	else
		if self.filterPanel then
			self.filterPanel:Hide()
		end
		self:ClearRequestState()
		self.pendingReason = nil
		self.pendingDueAt = nil
		self.needsRequest = false
		self.needsRebuild = false
		self.needsRender = false
		self.requestSettleUntil = nil
		self.requestReadinessRetryCount = 0
		self.trailingDirtyTokens = nil
	end

	if isShown then
		self:UpdateEmptyState()
		self:UpdateToolbar()
	end
	self.root:SetShown(isShown)
	local browseFrame = ProfessionsFrame.OrdersPage.BrowseFrame
	if browseFrame.OrderList then
		browseFrame.OrderList:SetShown(not isShown)
	end
	if browseFrame.SearchButton then
		browseFrame.SearchButton:SetShown(not isShown)
	end
	if browseFrame.FavoritesSearchButton then
		browseFrame.FavoritesSearchButton:SetShown(not isShown)
	end
end

local function IsOrderTypeButtonSelected(button)
	if not button then
		return false
	end

	if type(button.IsSelected) == "function" then
		local ok, selected = pcall(button.IsSelected, button)
		if ok and selected ~= nil then
			return not not selected
		end
	end

	if button.Selected and type(button.Selected.IsShown) == "function" and button.Selected:IsShown() then
		return true
	end

	if type(button.GetButtonState) == "function" then
		local ok, state = pcall(button.GetButtonState, button)
		if ok and state == "PUSHED" then
			return true
		end
	end

	return false
end

function Pane:GetCurrentOrderType()
	local ordersPage = ProfessionsFrame and ProfessionsFrame.OrdersPage
	if not ordersPage then
		return nil
	end

	for _, methodName in ipairs({
		"GetCraftingOrderType",
		"GetCurrentOrderType",
		"GetOrderType",
	}) do
		local method = ordersPage[methodName]
		if type(method) == "function" then
			local ok, orderType = pcall(method, ordersPage)
			if ok and type(orderType) == "number" then
				return orderType
			end
		end
	end

	for _, fieldName in ipairs({
		"orderType",
		"craftingOrderType",
		"selectedOrderType",
		"selectedCraftingOrderType",
	}) do
		local orderType = ordersPage[fieldName]
		if type(orderType) == "number" then
			return orderType
		end
	end

	for _, candidate in ipairs({
		{ "NpcOrdersButton", ns.ORDER_TYPE_NPC },
		{ "PatronOrdersButton", ns.ORDER_TYPE_NPC },
		{ "PublicOrdersButton", Enum.CraftingOrderType and Enum.CraftingOrderType.Public or 0 },
		{ "GuildOrdersButton", Enum.CraftingOrderType and Enum.CraftingOrderType.Guild or 1 },
		{ "PersonalOrdersButton", Enum.CraftingOrderType and Enum.CraftingOrderType.Personal or 2 },
	}) do
		local button = ordersPage[candidate[1]]
		if IsOrderTypeButtonSelected(button) then
			return candidate[2]
		end
	end

	return nil
end

function Pane:SyncCurrentOrderType(reason)
	local orderType = self:GetCurrentOrderType()
	if orderType == nil then
		return
	end

	local showCustomPane = orderType == ns.ORDER_TYPE_NPC
	self:SetCustomPaneShown(showCustomPane)
	if showCustomPane then
		self:MarkDirty(reason or "order-type")
	end
end

function Pane:InitializeHooks()
	local ordersPage = ProfessionsFrame and ProfessionsFrame.OrdersPage
	if not ordersPage then
		return false
	end

	if type(ordersPage.SetCraftingOrderType) == "function" and not self.orderTypeHooked then
		self.orderTypeHooked = true
		hooksecurefunc(ordersPage, "SetCraftingOrderType", function(_, orderType)
			local showCustomPane = orderType == ns.ORDER_TYPE_NPC
			Pane:SetCustomPaneShown(showCustomPane)
			if showCustomPane then
				Pane:MarkDirty("order-type")
			end
		end)
	end

	if not self.ordersPageShowHooked then
		self.ordersPageShowHooked = true
		ordersPage:HookScript("OnShow", function()
			Pane:SyncCurrentOrderType("show")
		end)
	end

	local orderView = ordersPage.OrderView
	if orderView and type(orderView.SetOrder) == "function" and not self.orderViewSetOrderHooked then
		self.orderViewSetOrderHooked = true
		hooksecurefunc(orderView, "SetOrder", function(_, order)
			Pane:RefreshDetailWarningOrderData(order)
			Pane:ScheduleDetailWarningUpdate(0)
			if Pane.pendingOpenPlan and order and order.orderID == Pane.pendingOpenPlan.orderID then
				Pane:SchedulePendingOrderPlan(0)
			end
		end)
	end

	self:EnsureDetailWarningHooks()

	return true
end

function Pane:ScheduleTrailingDirty(reason, delay)
	self.trailingDirtyTokens = self.trailingDirtyTokens or {}
	local token = (self.trailingDirtyTokens[reason] or 0) + 1
	self.trailingDirtyTokens[reason] = token

	C_Timer.After(delay or 0, function()
		if not Pane or not Pane.trailingDirtyTokens or Pane.trailingDirtyTokens[reason] ~= token then
			return
		end

		Pane.trailingDirtyTokens[reason] = nil
		Pane:MarkDirty(reason)
	end)
end

function Pane:InitializeEvents()
	if self.eventsInitialized then
		return
	end

	self.eventsInitialized = true
	ns.RegisterEvent("CRAFTINGORDERS_UPDATE_ORDER_COUNT", function(_, orderType)
		if orderType == ns.ORDER_TYPE_NPC then
			Pane:MarkDirty("order-count")
		end
	end)

	ns.RegisterEvent("CRAFTINGORDERS_CAN_REQUEST", function()
		Pane:MarkDirty("can-request")
	end)

	ns.RegisterEvent("CRAFTINGORDERS_UPDATE_REWARDS", function()
		Pane:MarkDirty("rewards")
	end)

	ns.RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, itemID)
		if Pane.root
			and Pane.root:IsShown()
			and type(itemID) == "number"
			and Pane.unresolvedItemIDs
			and Pane.unresolvedItemIDs[itemID] then
			Pane:ScheduleTrailingDirty("item-data", ITEM_DATA_REFRESH_DELAY)
		end
		Pane:MarkDetailWarningDirty()
	end)

	ns.RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", function()
		Pane:MarkDirty("trade-skill-source")
		Pane:MarkDetailWarningDirty()
	end)
end

function Pane:ScheduleInitializeRetry()
	if self.initializeRetryQueued then
		return
	end

	self.initializeRetryQueued = true
	C_Timer.After(INITIALIZE_RETRY_DELAY, function()
		if Pane then
			Pane.initializeRetryQueued = nil
		end
		if Pane and not Pane.initialized then
			Pane:Initialize()
		end
	end)
end

function Pane:Initialize()
	if self.initialized then
		return
	end

	self:LoadSavedFilters()
	self:LoadSavedSort()

	if not self:BuildFrame() then
		self:ScheduleInitializeRetry()
		return
	end

	if not self:InitializeHooks() then
		self:ScheduleInitializeRetry()
		return
	end

	self.initializeRetryQueued = nil
	self.initialized = true
	self:InitializeEvents()
	self:UpdateToolbar()
	C_Timer.After(0, function()
		if Pane and Pane.initialized then
			Pane:SyncCurrentOrderType("initial-state")
			Pane:ScheduleDetailWarningUpdate(0)
		end
	end)
end
