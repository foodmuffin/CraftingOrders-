local _, ns = ...

ns.Options = ns.Options or {}

local Options = ns.Options
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

local function CreateLabel(parent, fontObject, text, anchor, relativeTo, relativePoint, xOffset, yOffset, width)
	local label = parent:CreateFontString(nil, "ARTWORK", fontObject)
	label:SetPoint(anchor, relativeTo, relativePoint, xOffset, yOffset)
	label:SetJustifyH("LEFT")
	label:SetJustifyV("TOP")
	if width then
		label:SetWidth(width)
	end
	label:SetText(text)
	return label
end

local function GetCheckButtonLabel(checkbox)
	if not checkbox then
		return nil
	end

	local label = checkbox.text or checkbox.Text
	if label then
		return label
	end

	label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", checkbox, "RIGHT", 2, 1)
	checkbox.Text = label
	return label
end

local function CreateCheckButton(parent, text, anchor, relativeTo, relativePoint, xOffset, yOffset, onClick)
	local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	checkbox:SetPoint(anchor, relativeTo, relativePoint, xOffset, yOffset)
	local label = GetCheckButtonLabel(checkbox)
	if label then
		label:SetText(text)
		label:SetFontObject(GameFontHighlight)
	end
	checkbox:SetScript("OnClick", onClick)
	return checkbox
end

local function CreateRadioButton(parent, text, anchor, relativeTo, relativePoint, xOffset, yOffset, onClick)
	local radio = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
	radio:SetPoint(anchor, relativeTo, relativePoint, xOffset, yOffset)
	radio.label = radio:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	radio.label:SetPoint("LEFT", radio, "RIGHT", 4, 0)
	radio.label:SetJustifyH("LEFT")
	radio.label:SetText(text)
	radio:SetScript("OnClick", onClick)
	return radio
end

local function CreatePercentSlider(parent, name, text, anchor, relativeTo, relativePoint, xOffset, yOffset, onValueChanged)
	local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	slider:SetPoint(anchor, relativeTo, relativePoint, xOffset, yOffset)
	slider:SetWidth(220)
	slider:SetMinMaxValues(0, 100)
	slider:SetValueStep(1)
	slider:SetObeyStepOnDrag(true)
	slider.Text:SetText(text)
	_G[name .. "Low"]:SetText("0%")
	_G[name .. "High"]:SetText("100%")
	slider:SetScript("OnValueChanged", onValueChanged)
	return slider
end

local function SetSliderEnabled(slider, enabled)
	if not slider then
		return
	end

	slider:SetEnabled(enabled)
	slider:EnableMouse(enabled)
	slider:SetAlpha(enabled and 1 or 0.45)
end

local function UpdatePercentSliderText(slider, prefix, value)
	if not slider or not slider.Text then
		return
	end

	local percentValue = math.max(0, math.min(100, math.floor((tonumber(value) or 0) + 0.5)))
	slider.Text:SetText(LF("OPTION_PERCENT_THRESHOLD_FORMAT", prefix, percentValue))
end

function Options:UpdateScrollLayout()
	if not (self.panel and self.panel.scrollFrame and self.panel.scrollChild and self.panel.footer) then
		return
	end

	local scrollFrame = self.panel.scrollFrame
	local scrollChild = self.panel.scrollChild
	local scrollWidth = scrollFrame:GetWidth() or 0
	if scrollWidth > 0 then
		scrollChild:SetWidth(math.max(660, math.floor(scrollWidth - 24)))
	end

	local top = scrollChild:GetTop()
	local bottom = self.panel.footer:GetBottom()
	local minimumHeight = (scrollFrame:GetHeight() or 0) + 1
	if top and bottom then
		local contentHeight = math.ceil(top - bottom + 24)
		scrollChild:SetHeight(math.max(minimumHeight, contentHeight))
	else
		scrollChild:SetHeight(math.max(minimumHeight, scrollChild:GetHeight() or 1))
	end
end

function Options:QueueScrollLayoutUpdate()
	if self.scrollLayoutQueued then
		return
	end

	self.scrollLayoutQueued = true
	C_Timer.After(0, function()
		Options.scrollLayoutQueued = nil
		Options:UpdateScrollLayout()
	end)
end

function Options:BuildPanel()
	if self.panel then
		return
	end
	if not Settings then
		return
	end

	local panel = CreateFrame("Frame", nil, UIParent)
	panel.name = L.ADDON_TITLE
	panel:Hide()

	panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
	panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 4)
	panel.scrollChild = CreateFrame("Frame", nil, panel.scrollFrame)
	panel.scrollChild:SetPoint("TOPLEFT", panel.scrollFrame, "TOPLEFT", 0, 0)
	panel.scrollChild:SetSize(660, 1)
	panel.scrollFrame:SetScrollChild(panel.scrollChild)
	panel.scrollFrame:HookScript("OnSizeChanged", function()
		Options:QueueScrollLayoutUpdate()
	end)

	panel.title = CreateLabel(panel, "GameFontNormalLarge", L.ADDON_TITLE, "TOPLEFT", panel.scrollChild, "TOPLEFT", 16, -16)
	panel.version = CreateLabel(
		panel,
		"GameFontHighlightSmall",
		LF("OPTION_VERSION_FORMAT", ns.GetAddonMetadata(ns.ADDON_NAME, "Version") or "?"),
		"TOPLEFT",
		panel.title,
		"BOTTOMLEFT",
		0,
		-6
	)
	panel.description = CreateLabel(
		panel,
		"GameFontHighlight",
		L.OPTION_DESCRIPTION,
		"TOPLEFT",
		panel.version,
		"BOTTOMLEFT",
		0,
		-12,
		620
	)

	panel.sourceHeader = CreateLabel(panel, "GameFontNormal", L.OPTION_PRICING_ADDON_HEADER, "TOPLEFT", panel.description, "BOTTOMLEFT", 0, -18)
	panel.noPricingInfo = CreateLabel(
		panel,
		"GameFontHighlight",
		L.OPTION_NO_PRICING_INFO,
		"TOPLEFT",
		panel.sourceHeader,
		"BOTTOMLEFT",
		0,
		-8,
		620
	)

	panel.sourceAuctionator = CreateRadioButton(
		panel,
		L.OPTION_PRICING_AUCTIONATOR,
		"TOPLEFT",
		panel.sourceHeader,
		"BOTTOMLEFT",
		0,
		-8,
		function(self)
			self:SetChecked(true)
			ns.SetConfig("pricingSource", "auctionator")
		end
	)

	panel.sourceAuctioneer = CreateRadioButton(
		panel,
		L.OPTION_PRICING_AUCTIONEER,
		"TOPLEFT",
		panel.sourceAuctionator,
		"BOTTOMLEFT",
		0,
		-6,
		function(self)
			self:SetChecked(true)
			ns.SetConfig("pricingSource", "auctioneer")
		end
	)

	panel.sourceFooter = CreateLabel(panel, "GameFontHighlightSmall", "", "TOPLEFT", panel.sourceAuctioneer, "BOTTOMLEFT", 0, -10, 640)
	panel.preferencesHeader = CreateLabel(panel, "GameFontNormal", L.OPTION_DISPLAY_HEADER, "TOPLEFT", panel.sourceFooter, "BOTTOMLEFT", 0, -18)

	panel.greyUnknownRecipes = CreateCheckButton(
		panel,
		L.OPTION_GREY_UNKNOWN_RECIPES,
		"TOPLEFT",
		panel.preferencesHeader,
		"BOTTOMLEFT",
		0,
		-8,
		function(self)
			ns.SetConfig("greyUnknownRecipes", self:GetChecked())
		end
	)

	panel.showSilverCopperInList = CreateCheckButton(
		panel,
		L.OPTION_SHOW_SILVER_COPPER,
		"TOPLEFT",
		panel.greyUnknownRecipes,
		"BOTTOMLEFT",
		0,
		-6,
		function(self)
			ns.SetConfig("showSilverCopperInList", self:GetChecked())
		end
	)

	panel.warningHeader = CreateLabel(
		panel,
		"GameFontNormal",
		L.OPTION_INGREDIENT_WARNINGS_HEADER,
		"TOPLEFT",
		panel.showSilverCopperInList,
		"BOTTOMLEFT",
		0,
		-18
	)

	panel.warnExpensiveIngredients = CreateCheckButton(
		panel,
		L.OPTION_WARN_EXPENSIVE_INGREDIENTS,
		"TOPLEFT",
		panel.warningHeader,
		"BOTTOMLEFT",
		0,
		-8,
		function(self)
			ns.SetConfig("warnExpensiveIngredients", self:GetChecked())
		end
	)

	panel.expensiveIngredientThreshold = CreatePercentSlider(
		panel,
		"CraftingOrdersPlusPlusExpensiveIngredientThresholdSlider",
		L.OPTION_PERCENT_THRESHOLD,
		"TOPLEFT",
		panel.warnExpensiveIngredients,
		"BOTTOMLEFT",
		4,
		-18,
		function(self, value)
			local roundedValue = math.max(0, math.min(100, math.floor((tonumber(value) or 0) + 0.5)))
			UpdatePercentSliderText(self, L.OPTION_PERCENT_THRESHOLD, roundedValue)
			if self.suppressCallback then
				return
			end
			ns.SetConfig("expensiveIngredientThresholdPercent", roundedValue)
		end
	)

	panel.warningHint = CreateLabel(
		panel,
		"GameFontHighlightSmall",
		L.OPTION_WARNING_HINT,
		"TOPLEFT",
		panel.expensiveIngredientThreshold,
		"BOTTOMLEFT",
		0,
		-8,
		620
	)

	panel.openBehaviorHeader = CreateLabel(
		panel,
		"GameFontNormal",
		L.OPTION_OPENING_HEADER,
		"TOPLEFT",
		panel.warningHint,
		"BOTTOMLEFT",
		0,
		-18
	)

	panel.openBehaviorNone = CreateRadioButton(
		panel,
		L.OPTION_OPENING_NONE,
		"TOPLEFT",
		panel.openBehaviorHeader,
		"BOTTOMLEFT",
		0,
		-8,
		function(self)
			self:SetChecked(true)
			ns.SetConfig("openPatronOrderBehavior", "none")
		end
	)

	panel.openBehaviorApplyPlan = CreateRadioButton(
		panel,
		L.OPTION_OPENING_APPLY_PLAN,
		"TOPLEFT",
		panel.openBehaviorNone,
		"BOTTOMLEFT",
		0,
		-6,
		function(self)
			self:SetChecked(true)
			ns.SetConfig("openPatronOrderBehavior", "apply_plan")
		end
	)

	panel.openBehaviorHint = CreateLabel(
		panel,
		"GameFontHighlightSmall",
		L.OPTION_OPENING_HINT,
		"TOPLEFT",
		panel.openBehaviorApplyPlan,
		"BOTTOMLEFT",
		4,
		-2,
		620
	)

	panel.dontBuyPerCharacter = CreateCheckButton(
		panel,
		L.OPTION_DONT_BUY_PER_CHARACTER,
		"TOPLEFT",
		panel.openBehaviorHint,
		"BOTTOMLEFT",
		0,
		-18,
		function(self)
			if ns.SetDontBuyScopePerCharacter then
				ns.SetDontBuyScopePerCharacter(self:GetChecked())
			else
				ns.SetConfig("dontBuyPerCharacter", self:GetChecked())
			end
		end
	)

	panel.dontBuyScopeHint = CreateLabel(
		panel,
		"GameFontHighlightSmall",
		L.OPTION_DONT_BUY_HINT,
		"TOPLEFT",
		panel.dontBuyPerCharacter,
		"BOTTOMLEFT",
		4,
		-2,
		620
	)

	panel.footer = CreateLabel(
		panel,
		"GameFontHighlightSmall",
		L.OPTION_FOOTER_HINT,
		"TOPLEFT",
		panel.dontBuyScopeHint,
		"BOTTOMLEFT",
		0,
		-18,
		640
	)

	panel.scrollWidgets = {
		panel.title,
		panel.version,
		panel.description,
		panel.sourceHeader,
		panel.noPricingInfo,
		panel.sourceAuctionator,
		panel.sourceAuctioneer,
		panel.sourceFooter,
		panel.preferencesHeader,
		panel.greyUnknownRecipes,
		panel.showSilverCopperInList,
		panel.warningHeader,
		panel.warnExpensiveIngredients,
		panel.expensiveIngredientThreshold,
		panel.warningHint,
		panel.openBehaviorHeader,
		panel.openBehaviorNone,
		panel.openBehaviorApplyPlan,
		panel.openBehaviorHint,
		panel.dontBuyPerCharacter,
		panel.dontBuyScopeHint,
		panel.footer,
	}

	for _, widget in ipairs(panel.scrollWidgets) do
		widget:SetParent(panel.scrollChild)
	end

	panel.title:ClearAllPoints()
	panel.title:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 16, -16)

	panel:SetScript("OnShow", function()
		Options:Refresh()
		Options:QueueScrollLayoutUpdate()
	end)

	local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(category)

	self.panel = panel
	self.category = category
end

function Options:Refresh()
	if not self.panel then
		return
	end

	local status = ns.Pricing and ns.Pricing:GetStatus() or {}
	local db = ns.GetDatabase() or {}
	local selectedProviderKey = status.selectedProviderKey or db.pricingSource
	local lastPricingAnchor = self.panel.sourceHeader
	local visibleSourceCount = 0

	local function LayoutDetectedRadio(radio, shouldShow, yOffset)
		radio:ClearAllPoints()
		if not shouldShow then
			radio:Hide()
			return
		end

		radio:SetPoint("TOPLEFT", lastPricingAnchor, "BOTTOMLEFT", 0, yOffset)
		radio:Show()
		lastPricingAnchor = radio
		visibleSourceCount = visibleSourceCount + 1
	end

	LayoutDetectedRadio(self.panel.sourceAuctionator, status.auctionatorDetected, -8)
	LayoutDetectedRadio(self.panel.sourceAuctioneer, status.auctioneerDetected, visibleSourceCount > 0 and -6 or -8)

	self.panel.sourceAuctionator:SetChecked(selectedProviderKey == "auctionator")
	self.panel.sourceAuctioneer:SetChecked(selectedProviderKey == "auctioneer")

	self.panel.noPricingInfo:ClearAllPoints()
	self.panel.noPricingInfo:SetPoint("TOPLEFT", self.panel.sourceHeader, "BOTTOMLEFT", 0, -8)
	self.panel.noPricingInfo:SetShown(visibleSourceCount == 0)

	self.panel.sourceFooter:ClearAllPoints()
	if visibleSourceCount == 0 then
		self.panel.sourceFooter:Hide()
		lastPricingAnchor = self.panel.noPricingInfo
	else
		self.panel.sourceFooter:SetPoint("TOPLEFT", lastPricingAnchor, "BOTTOMLEFT", 0, -10)
		self.panel.sourceFooter:SetShown(true)
		if selectedProviderKey == "auctioneer" then
			self.panel.sourceFooter:SetText(L.OPTION_PRICING_FOOTER_AUCTIONEER)
		else
			self.panel.sourceFooter:SetText(L.OPTION_PRICING_FOOTER_AUCTIONATOR)
		end
		lastPricingAnchor = self.panel.sourceFooter
	end

	self.panel.preferencesHeader:ClearAllPoints()
	self.panel.preferencesHeader:SetPoint("TOPLEFT", lastPricingAnchor, "BOTTOMLEFT", 0, -18)
	self.panel.greyUnknownRecipes:SetChecked(db.greyUnknownRecipes)
	self.panel.showSilverCopperInList:SetChecked(db.showSilverCopperInList)
	self.panel.warnExpensiveIngredients:SetChecked(db.warnExpensiveIngredients ~= false)
	self.panel.expensiveIngredientThreshold.suppressCallback = true
	self.panel.expensiveIngredientThreshold:SetValue(math.max(0, math.min(100, tonumber(db.expensiveIngredientThresholdPercent) or 10)))
	self.panel.expensiveIngredientThreshold.suppressCallback = nil
	UpdatePercentSliderText(
		self.panel.expensiveIngredientThreshold,
		L.OPTION_PERCENT_THRESHOLD,
		tonumber(db.expensiveIngredientThresholdPercent) or 10
	)
	SetSliderEnabled(self.panel.expensiveIngredientThreshold, db.warnExpensiveIngredients ~= false)
	self.panel.openBehaviorNone:SetChecked(db.openPatronOrderBehavior ~= "apply_plan")
	self.panel.openBehaviorApplyPlan:SetChecked(db.openPatronOrderBehavior == "apply_plan")
	self.panel.dontBuyPerCharacter:SetChecked(db.dontBuyPerCharacter)
	self:QueueScrollLayoutUpdate()
end

function Options:Initialize()
	if self.panel then
		self.initialized = true
		self:Refresh()
		return
	end

	self:BuildPanel()
	if self.panel then
		self.initialized = true
		self:Refresh()
	end
end
