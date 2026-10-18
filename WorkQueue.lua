local _, ns = ...

-- Preparation is pure calculation. Yield between Lua steps/native calls rather
-- than blocking the UI for an entire list (or a large reagent search).
local Work = {}
ns.PreparationWork = Work
local frame = CreateFrame("Frame")
local clock = debugprofilestop or function() return GetTime() * 1000 end
local BUDGET_MS = 2
local MAX_STEPS = 64

function Work:Cancel()
	self.job = nil
	frame:SetScript("OnUpdate", nil)
end

function Work:Checkpoint()
	local job = self.runningJob
	if not job or coroutine.running() ~= job.thread then return end
	job.steps = job.steps + 1
	if self.job ~= job or job.steps >= MAX_STEPS or clock() >= job.deadline then
		coroutine.yield()
	end
end

-- table.sort cannot yield through its C comparator. Large variant lists use a
-- cooperative merge sort; small synchronous callers keep the native sort.
function Work:Sort(values, less)
	if not self.runningJob then return table.sort(values, less) end
	local size = #values
	local buffer = {}
	local source, target = values, buffer
	local width = 1
	while width < size do
		for first = 1, size, width * 2 do
			local middle = math.min(first + width, size + 1)
			local finish = math.min(first + width * 2 - 1, size)
			local left, right = first, middle
			for out = first, finish do
				self:Checkpoint()
				if left < middle and (right > finish or not less(source[right], source[left])) then
					target[out] = source[left]
					left = left + 1
				else
					target[out] = source[right]
					right = right + 1
				end
			end
		end
		source, target = target, source
		width = width * 2
	end
	if source ~= values then
		for index = 1, size do
			self:Checkpoint()
			values[index] = source[index]
		end
	end
end

function Work:Step()
	local job = self.job
	if not job then return end
	if not job.isCurrent() then
		self:Cancel()
		if job.onError then job.onError(true) end
		return
	end
	job.deadline = clock() + BUDGET_MS
	job.steps = 0
	self.runningJob = job
	local ok, result = coroutine.resume(job.thread)
	self.runningJob = nil
	if self.job ~= job then return end
	if not ok then
		self:Cancel()
		if job.onError then job.onError() end
		geterrorhandler()(result)
	elseif coroutine.status(job.thread) == "dead" then
		self:Cancel()
		if job.isCurrent() then
			job.onComplete(result)
		elseif job.onError then
			job.onError(true)
		end
	end
end

function Work:Start(prepare, isCurrent, onComplete, onError)
	self:Cancel()
	self.job = {
		thread = coroutine.create(prepare),
		isCurrent = isCurrent,
		onComplete = onComplete,
		onError = onError,
	}
	frame:SetScript("OnUpdate", function() Work:Step() end)
end
