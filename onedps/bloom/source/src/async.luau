--[[
	██████╗ ██╗      ██████╗  ██████╗ ███╗   ███╗
	██╔══██╗██║     ██╔═══██╗██╔═══██╗████╗ ████║
	██████╔╝██║     ██║   ██║██║   ██║██╔████╔██║
	██╔══██╗██║     ██║   ██║██║   ██║██║╚██╔╝██║
	██████╔╝███████╗╚██████╔╝╚██████╔╝██║ ╚═╝ ██║
	╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝     ╚═╝

	Low-level graphics library for EditableImage
]]

--!native
--!optimize 2
--!strict

local Types = require("./types")
local Platform = require("./platform")

export type Task = Types.Task
export type Scheduler = Types.Scheduler
export type Options = Types.SchedulerOptions
export type Stats = Types.SchedulerStats

type InternalTask = Types.Task & {
	owner: InternalScheduler,
	callback: (...any) -> ...any,
	arguments: { [number]: any, n: number },
	thread: thread?,
	token: number,
}

type Queue = {
	items: { [number]: InternalTask },
	tokens: { [number]: number },
	head: number,
	tail: number,
}

type InternalScheduler = Types.Scheduler & {
	queues: { Queue },
	deadline_tasks: { InternalTask },
	running: boolean,
	worker_generation: number,
	queue_generation: number,
	budget: number,
	poll_interval: number,
	aging_interval: number,
	max_tasks_per_step: number,
	pending_count: number,
	active_count: number,
	completed_count: number,
	failed_count: number,
	cancelled_count: number,
	last_step_seconds: number,
	max_step_seconds: number,
}

local PRIORITY_COUNT = 4
local DEFAULT_PRIORITY = 1
local MIN_BUDGET = 0.0001
local DEFAULT_BUDGET = 0.002
local DEFAULT_POLL_INTERVAL = 0.001
local DEFAULT_AGING_INTERVAL = 0.25
local DEFAULT_MAX_TASKS_PER_STEP = 256
local QUEUE_COMPACT_THRESHOLD = 128
local DEADLINE_COMPACT_THRESHOLD = 64
local FOREIGN_YIELD_ERROR = "Task yielded outside Async.Yield(); scheduler callbacks must use cooperative yielding only"
local MISSING_THREAD_ERROR = "Missing task coroutine"

local YIELD_TOKEN = table.freeze({})

local env: any = _G
local current_thread: thread? = nil

local report = function(message: string): ()
	local text = "[Bloom.Async] Task failed: " .. message
	local shim: any = env.warn

	if shim ~= nil then
		shim(text)
		return
	end

	warn(text)
end

local finish = function(item: InternalTask, state: Types.TaskState): ()
	item.state = state
	item.finished_at = os.clock()
	item.thread = nil
	table.clear(item.arguments)
	item.arguments.n = 0
end

local fail = function(owner: InternalScheduler, item: InternalTask, message: string): ()
	item.error = message
	finish(item, "failed")
	owner.failed_count += 1
	report(message)
end

local create_queue = function(): Queue
	return { items = {}, tokens = {}, head = 1, tail = 0 }
end

local compact_queue = function(queue: Queue): ()
	local head = queue.head
	local count = queue.tail - head + 1

	for index = 1, count do
		queue.items[index] = queue.items[head + index - 1]
		queue.tokens[index] = queue.tokens[head + index - 1]
	end

	for index = count + 1, queue.tail do
		queue.items[index] = nil
		queue.tokens[index] = nil
	end

	queue.head = 1
	queue.tail = count
end

local enqueue = function(queue: Queue, item: InternalTask): ()
	local token = item.token + 1
	local tail = queue.tail + 1
	item.token = token
	queue.tail = tail
	queue.items[tail] = item
	queue.tokens[tail] = token
end

local dequeue = function(queue: Queue): InternalTask?
	local head = queue.head

	if head > queue.tail then
		return nil
	end

	local item = queue.items[head]
	queue.items[head] = nil
	queue.tokens[head] = nil
	head += 1
	queue.head = head

	if head > queue.tail then
		queue.head = 1
		queue.tail = 0
	elseif head > QUEUE_COMPACT_THRESHOLD and head * 2 > queue.tail then
		compact_queue(queue)
	end

	return item
end

local peek_valid = function(queue: Queue): InternalTask?
	while queue.head <= queue.tail do
		local item = queue.items[queue.head]

		if item == nil then
			queue.tokens[queue.head] = nil
			queue.head += 1
		elseif queue.tokens[queue.head] == item.token and (item.state == "pending" or item.state == "yielded") then
			return item
		else
			dequeue(queue)
		end
	end

	queue.head = 1
	queue.tail = 0
	return nil
end

local task_methods = {
	Cancel = function(self: Types.Task): ()
		local item = self :: InternalTask
		local state = item.state

		if state ~= "pending" and state ~= "yielded" then
			return
		end

		local owner = item.owner
		owner.pending_count -= 1
		owner.cancelled_count += 1
		finish(item, "cancelled")
	end,
	IsCancelled = function(self: Types.Task): boolean
		return self.state == "cancelled"
	end,
	IsFinished = function(self: Types.Task): boolean
		local state = self.state
		return state == "completed" or state == "cancelled" or state == "failed"
	end,
}

local terminate = function(thread: thread): ()
	local task_library = Platform.task
	local cancel = task_library.cancel

	if cancel ~= nil then
		pcall(cancel, thread)
	else
		pcall(coroutine.close, thread)
	end
end

local resume = function(self: InternalScheduler, item: InternalTask): ()
	local thread = item.thread

	if thread == nil then
		fail(self, item, MISSING_THREAD_ERROR)
		return
	end

	local generation = self.queue_generation
	local previous = current_thread

	item.state = "running"
	item.started_at = item.started_at or os.clock()
	self.active_count += 1
	current_thread = thread

	local ok, result = coroutine.resume(thread)

	current_thread = previous
	self.active_count -= 1

	if not ok then
		fail(self, item, tostring(result))
	elseif result == YIELD_TOKEN then
		if generation ~= self.queue_generation then
			finish(item, "cancelled")
			self.cancelled_count += 1
		else
			item.state = "yielded"
			self.pending_count += 1
			enqueue(self.queues[item.priority + 1], item)
		end
	elseif coroutine.status(thread) == "dead" then
		finish(item, "completed")
		self.completed_count += 1
	else
		terminate(thread)
		fail(self, item, FOREIGN_YIELD_ERROR)
	end
end

local compact_deadlines = function(self: InternalScheduler): ()
	local tasks = self.deadline_tasks
	local length = #tasks
	local count = 0

	for index = 1, length do
		local item = tasks[index]
		local state = item.state

		if state == "pending" or state == "yielded" then
			count += 1
			tasks[count] = item
		end
	end

	for index = count + 1, length do
		tasks[index] = nil
	end
end

local pop_next = function(self: InternalScheduler): InternalTask?
	local now = os.clock()
	local deadlines = self.deadline_tasks

	if #deadlines > DEADLINE_COMPACT_THRESHOLD then
		compact_deadlines(self)
		deadlines = self.deadline_tasks
	end

	for index = 1, #deadlines do
		local item = deadlines[index]
		local state = item.state

		if state == "pending" or state == "yielded" then
			local deadline = item.deadline

			if deadline ~= nil and now >= deadline then
				item.token += 1
				item.state = "running"
				return item
			end
		end
	end

	local selected: Queue? = nil
	local selected_score = math.huge

	for index = 1, PRIORITY_COUNT do
		local queue = self.queues[index]
		local item = peek_valid(queue)

		if item ~= nil then
			local waited = math.max(0, now - item.submitted_at)
			local score = item.priority - math.floor(waited / self.aging_interval)

			if score < selected_score then
				selected = queue
				selected_score = score
			end
		end
	end

	if selected == nil then
		return nil
	end

	return dequeue(selected)
end

local submit = function(
	self: Types.Scheduler,
	callback: (...any) -> ...any,
	options: Types.SubmitOptions?,
	...
): Types.Task
	assert(type(callback) == "function", "Async.Submit expects a function")

	local owner = self :: InternalScheduler
	local settings: Types.SubmitOptions = options or {}
	local priority = math.clamp(math.floor(settings.priority or DEFAULT_PRIORITY), 0, PRIORITY_COUNT - 1)
	local arguments = table.pack(...)

	local item: InternalTask = {
		owner = owner,
		callback = callback,
		arguments = arguments,
		thread = nil,
		token = 0,
		state = "pending" :: Types.TaskState,
		priority = priority,
		submitted_at = os.clock(),
		started_at = nil,
		finished_at = nil,
		deadline = settings.deadline,
		error = nil,
		Cancel = task_methods.Cancel,
		IsCancelled = task_methods.IsCancelled,
		IsFinished = task_methods.IsFinished,
	}

	item.thread = coroutine.create(function()
		item.callback(table.unpack(item.arguments, 1, item.arguments.n))
	end)

	enqueue(owner.queues[priority + 1], item)
	owner.pending_count += 1

	if item.deadline ~= nil then
		local deadlines = owner.deadline_tasks
		deadlines[#deadlines + 1] = item
	end

	return item
end

local submit_default = function(self: Types.Scheduler, callback: (...any) -> ...any, ...: any): Types.Task
	return submit(self, callback, nil, ...)
end

local submit_with_options = function(
	self: Types.Scheduler,
	callback: (...any) -> ...any,
	options: Types.SubmitOptions,
	...
): Types.Task
	return submit(self, callback, options, ...)
end

local step = function(self: Types.Scheduler, budget: number?): number
	local owner = self :: InternalScheduler

	if owner.pending_count == 0 or owner.active_count > 0 then
		return 0
	end

	local started = os.clock()
	local limit = math.max(budget or owner.budget, 0)
	local unlimited = limit == math.huge
	local resumed = 0

	while resumed < owner.max_tasks_per_step do
		if resumed > 0 and not unlimited and os.clock() - started >= limit then
			break
		end

		local item = pop_next(owner)

		if item == nil then
			break
		end

		owner.pending_count -= 1
		resume(owner, item)
		resumed += 1
	end

	local elapsed = os.clock() - started
	owner.last_step_seconds = elapsed
	owner.max_step_seconds = math.max(owner.max_step_seconds, elapsed)

	return resumed
end

local start = function(self: Types.Scheduler): ()
	local owner = self :: InternalScheduler

	if owner.running then
		return
	end

	owner.running = true
	owner.worker_generation += 1
	local generation = owner.worker_generation
	local task_library = Platform.task

	task_library.spawn(function()
		while owner.running and owner.worker_generation == generation do
			step(self)
			task_library.wait(owner.poll_interval)
		end
	end)
end

local stop = function(self: Types.Scheduler): ()
	local owner = self :: InternalScheduler
	owner.running = false
	owner.worker_generation += 1
end

local clear = function(self: Types.Scheduler): ()
	local owner = self :: InternalScheduler
	owner.queue_generation += 1

	for index = 1, PRIORITY_COUNT do
		local queue = owner.queues[index]

		for position = queue.head, queue.tail do
			local item = queue.items[position]

			if item ~= nil and (item.state == "pending" or item.state == "yielded") then
				finish(item, "cancelled")
				owner.cancelled_count += 1
			end
		end

		table.clear(queue.items)
		queue.head = 1
		queue.tail = 0
	end

	table.clear(owner.deadline_tasks)
	owner.pending_count = 0
end

local pending_count = function(self: Types.Scheduler): number
	return (self :: InternalScheduler).pending_count
end

local get_stats = function(self: Types.Scheduler): Types.SchedulerStats
	local owner = self :: InternalScheduler

	return {
		pending = owner.pending_count,
		active = owner.active_count,
		completed = owner.completed_count,
		failed = owner.failed_count,
		cancelled = owner.cancelled_count,
		last_step_seconds = owner.last_step_seconds,
		max_step_seconds = owner.max_step_seconds,
	}
end

local destroy = function(self: Types.Scheduler): ()
	stop(self)
	clear(self)
end

local new = function(budget: number?, options: Types.SchedulerOptions?): Types.Scheduler
	local settings: Types.SchedulerOptions = options or {}
	local queues: { Queue } = table.create(PRIORITY_COUNT)

	for index = 1, PRIORITY_COUNT do
		queues[index] = create_queue()
	end

	local scheduler: InternalScheduler = {
		queues = queues,
		deadline_tasks = {},
		running = false,
		worker_generation = 0,
		queue_generation = 0,
		budget = math.max(budget or DEFAULT_BUDGET, MIN_BUDGET),
		poll_interval = math.max(settings.poll_interval or DEFAULT_POLL_INTERVAL, 0),
		aging_interval = math.max(settings.aging_interval or DEFAULT_AGING_INTERVAL, MIN_BUDGET),
		max_tasks_per_step = math.max(1, math.floor(settings.max_tasks_per_step or DEFAULT_MAX_TASKS_PER_STEP)),
		pending_count = 0,
		active_count = 0,
		completed_count = 0,
		failed_count = 0,
		cancelled_count = 0,
		last_step_seconds = 0,
		max_step_seconds = 0,
		Start = start,
		Stop = stop,
		Step = step,
		Submit = submit_default,
		SubmitWithOptions = submit_with_options,
		PendingCount = pending_count,
		GetStats = get_stats,
		Clear = clear,
		Destroy = destroy,
	}

	return scheduler
end

local yield = function(): ()
	assert(
		current_thread ~= nil and coroutine.running() == current_thread,
		"Async.Yield must be called from inside a scheduler task"
	)

	coroutine.yield(YIELD_TOKEN)
end

return {
	new = new,
	yield = yield,
	submit = submit,
	submit_with_options = submit_with_options,
	step = step,
	start = start,
	stop = stop,
	clear = clear,
	pending_count = pending_count,
	get_stats = get_stats,
	destroy = destroy,
}
