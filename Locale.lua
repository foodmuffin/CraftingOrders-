local _, ns = ...

ns._localeDefaults = ns._localeDefaults or {}
ns._localeActive = ns._localeActive or {}

local currentLocale = GetLocale and GetLocale() or "enUS"

function ns.AddLocale(locale, strings)
	if type(strings) ~= "table" then
		return
	end

	if locale == "enUS" then
		for key, value in pairs(strings) do
			ns._localeDefaults[key] = value
			if ns._localeActive[key] == nil then
				ns._localeActive[key] = value
			end
		end
	elseif locale == currentLocale then
		for key, value in pairs(strings) do
			ns._localeActive[key] = value
		end
	end
end

ns.L = setmetatable(ns._localeActive, {
	__index = function(_, key)
		return ns._localeDefaults[key] or key
	end,
})

function ns.LF(key, ...)
	local value = ns.L[key] or key
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, value, ...)
		if ok then
			return formatted
		end

		local fallback = ns._localeDefaults[key]
		if fallback and fallback ~= value then
			ok, formatted = pcall(string.format, fallback, ...)
			if ok then
				return formatted
			end
		end
	end

	return value
end
