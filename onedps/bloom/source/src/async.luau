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

export type Priority = Types.Priority
export type TaskState = Types.TaskState
export type Task = Types.Task
export type Options = Types.SchedulerOptions
export type Stats = Types.SchedulerStats

type Queue = {
	items: { Task? },
	head: number,
	tail: number,
}

--[=[
	@class Async

	Cooperative, priority-aware scheduler that does not depend on frame events.

	Callbacks are never preempted. Long-running callbacks should periodically call
	`Async.Yield()` so the scheduler can run other work and re-check its time budget.
]=]
local async = {}
async.__index = async

export type Scheduler = typeof(setmetatable(
	{} :: {
		queues: { Queue },
		running: boolean,
		worker_generation: number,
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
	},
	async
))

local PRIORITY_COUNT = 4
local DEFAULT_PRIORITY = 1
local MIN_BUDGET = 0.0001
local DEFAULT_BUDGET = 0.002
local DEFAULT_POLL_INTERVAL = 0.001
local DEFAULT_AGING_INTERVAL = 0.25
local DEFAULT_MAX_TASKS_PER_STEP = 256
local QUEUE_COMPACT_THRESHOLD = 128

local YIELD_TOKEN = table.freeze({})

local current_task_thread: thread? = nil

local task_methods = {}
task_methods.__index = task_methods

local function is_queued(state: TaskState): boolean
	return state == "pending" or state == "yielded"
end

task_methods.Cancel = function(self: Task): ()
	if is_queued(self.state) then
		self.state = "cancelled"
	end
end

task_methods.IsCancelled = function(self: Task): boolean
	return self.state == "cancelled"
end

task_methods.IsFinished = function(self: Task): boolean
	return self.state == "completed" or self.state == "cancelled" or self.state == "failed"
end

local function create_queue(): Queue
	return { items = {}, head = 1, tail = 0 }
end

local function reset_queue(queue: Queue): ()
	table.clear(queue.items)
	queue.head = 1
	queue.tail = 0
end

local function enqueue(queue: Queue, item: Task): ()
	queue.tail += 1
	queue.items[queue.tail] = item
end

local function peek(queue: Queue): Task?
	return queue.items[queue.head]
end

local function compact(queue: Queue): ()
	local compacted: { Task? } = {}
	local count = 0

	for index = queue.head, queue.tail do
		local item = queue.items[index]

		if item ~= nil then
			count += 1
			compacted[count] = item
		end
	end

	queue.items = compacted
	queue.head = 1
	queue.tail = count
end

local function dequeue(queue: Queue): Task?
	while queue.head <= queue.tail do
		local item = queue.items[queue.head]

		queue.items[queue.head] = nil
		queue.head += 1

		if item ~= nil then
			if queue.head > QUEUE_COMPACT_THRESHOLD and queue.head > queue.tail / 2 then
				compact(queue)
			end

			return item
		end
	end

	reset_queue(queue)
	return nil
end

local function effective_score(item: Task, now: number, aging_interval: number): number
	local age_bonus = math.floor(math.max(0, now - item.submitted_at) / aging_interval)
	local score = item.priority - age_bonus

	if item.deadline ~= nil and now >= item.deadline then
		score -= PRIORITY_COUNT
	end

	return score
end

local function finish(item: Task, state: TaskState): ()
	item.state = state
	item.finished_at = os.clock()
	item.thread = nil
	table.clear(item.arguments)
	item.arguments.n = 0
end

local function fail(self: Scheduler, item: Task, message: string): ()
	item.error = message
	finish(item, "failed")
	self.failed_count += 1

	warn("[Bloom.Async] Task failed: " .. message)
end

local function drop_cancelled_head(self: Scheduler, queue: Queue): Task?
	local candidate = peek(queue)

	while candidate ~= nil and not is_queued(candidate.state) do
		dequeue(queue)

		if candidate.state == "cancelled" then
			finish(candidate, "cancelled")

			self.pending_count = math.max(0, self.pending_count - 1)
			self.cancelled_count += 1
		end

		candidate = peek(queue)
	end

	return candidate
end

local function pop_next(self: Scheduler): Task?
	local now = os.clock()
	local selected_queue: Queue? = nil
	local selected_score = math.huge

	for _, queue in self.queues do
		local candidate = drop_cancelled_head(self, queue)

		if candidate ~= nil then
			local score = effective_score(candidate, now, self.aging_interval)

			if score < selected_score then
				selected_score = score
				selected_queue = queue
			end
		end
	end

	return if selected_queue then dequeue(selected_queue) else nil
end

local function resume(self: Scheduler, item: Task): ()
	local thread = item.thread
	if thread == nil then
		fail(self, item, "Missing task coroutine")
		return
	end

	item.state = "running"
	item.started_at = item.started_at or os.clock()
	self.active_count += 1

	local previous_thread = current_task_thread
	current_task_thread = thread

	local ok, result = coroutine.resume(thread)
	current_task_thread = previous_thread

	self.active_count = math.max(0, self.active_count - 1)

	if not ok then
		fail(self, item, tostring(result))
	elseif coroutine.status(thread) == "dead" then
		finish(item, "completed")
		self.completed_count += 1
	elseif result == YIELD_TOKEN then
		item.state = "yielded"
		self.pending_count += 1
		enqueue(self.queues[item.priority + 1], item)
	else
		fail(self, item, "Task yielded outside Async.Yield(); scheduler callbacks must use cooperative yielding only")
	end
end

--[=[
	Creates a scheduler.

	@within Async
	@param budget number? -- Execution budget per `Step`, in seconds.
	@param options SchedulerOptions? -- `poll_interval`, `aging_interval` and `max_tasks_per_step`.
	@return Scheduler
]=]
async.New = function(budget: number?, options: Options?): Scheduler
	local settings: Options = options or {}

	local queues: { Queue } = table.create(PRIORITY_COUNT)

	for index = 1, PRIORITY_COUNT do
		queues[index] = create_queue()
	end

	local self = {
		queues = queues,
		running = false,
		worker_generation = 0,
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
	}

	return setmetatable(self, async)
end

local function submit(self: Scheduler, callback: (...any) -> ...any, options: Types.SubmitOptions?, ...: any): Task
	assert(type(callback) == "function", "Async.Submit expects a function")
	local settings: Types.SubmitOptions = options or {}

	local priority = math.clamp(math.floor(settings.priority or DEFAULT_PRIORITY), 0, PRIORITY_COUNT - 1)
	local item: Task = setmetatable({
		callback = callback,
		arguments = table.pack(...),
		state = "pending",
		priority = priority,
		submitted_at = os.clock(),
		started_at = nil,
		finished_at = nil,
		deadline = settings.deadline,
		error = nil,
		thread = nil,
	}, task_methods) :: any

	item.thread = coroutine.create(function()
		item.callback(table.unpack(item.arguments, 1, item.arguments.n))
	end)

	enqueue(self.queues[priority + 1], item)
	self.pending_count += 1

	return item
end

--[=[
	Queues work with the default priority. All arguments after `callback` are forwarded to it.

	@within Async
	@param callback (...any) -> ...any
	@param ... any -- Arguments forwarded unchanged.
	@return Task
]=]
async.Submit = function(self: Scheduler, callback: (...any) -> ...any, ...: any): Task
	return submit(self, callback, nil, ...)
end

--[=[
	Queues work with an explicit priority and/or deadline.

	@within Async
	@param callback (...any) -> ...any
	@param options SubmitOptions -- `priority`: 0..3 (0 is highest); `deadline`: absolute `os.clock()` time.
	@param ... any -- Arguments forwarded unchanged.
	@return Task
]=]
async.SubmitWithOptions = function(
	self: Scheduler,
	callback: (...any) -> ...any,
	options: Types.SubmitOptions,
	...: any
): Task
	return submit(self, callback, options, ...)
end

--[=[
	Cooperatively yields the current scheduler task. The task is re-queued and resumes later.
	Calling this outside a scheduler task is an error.

	@within Async
]=]
async.Yield = function(): ()
	assert(
		current_task_thread ~= nil and coroutine.running() == current_task_thread,
		"Async.Yield must be called from inside a scheduler task"
	)

	coroutine.yield(YIELD_TOKEN)
end

--[=[
	Runs queued work for at most `budget` seconds and at most `max_tasks_per_step` resumes.
	A callback that never yields cannot be preempted; keep callbacks short or call `Async.Yield()`.

	@within Async
	@param budget number? -- Overrides the scheduler budget for this step, in seconds.
	@return number -- Number of tasks resumed.
]=]
async.Step = function(self: Scheduler, budget: number?): number
	local started = os.clock()
	local limit = math.max(budget or self.budget, 0)
	local resumed = 0

	while resumed < self.max_tasks_per_step do
		if resumed > 0 and os.clock() - started >= limit then
			break
		end

		local item = pop_next(self)

		if item == nil then
			break
		end

		self.pending_count = math.max(0, self.pending_count - 1)
		resume(self, item)
		resumed += 1
	end

	local elapsed = os.clock() - started
	self.last_step_seconds = elapsed
	self.max_step_seconds = math.max(self.max_step_seconds, elapsed)

	return resumed
end

--[=[
	Starts a worker loop built on `task.spawn` and `task.wait`.
	It does not connect to Heartbeat, Stepped, RenderStepped or any other engine event.

	@within Async
]=]
async.Start = function(self: Scheduler): ()
	if self.running then
		return
	end

	self.running = true
	self.worker_generation += 1
	local generation = self.worker_generation

	task.spawn(function()
		while self.running and self.worker_generation == generation do
			self:Step()
			task.wait(self.poll_interval)
		end
	end)
end

--[=[
	Stops automatic processing. Queued work stays queued and can be resumed with `Start` or `Step`.

	@within Async
]=]
async.Stop = function(self: Scheduler): ()
	self.running = false
	self.worker_generation += 1
end

--[=[
	Cancels all queued tasks. A task that is currently running stops only at its next cooperative yield.

	@within Async
]=]
async.Clear = function(self: Scheduler): ()
	for _, queue in self.queues do
		for index = queue.head, queue.tail do
			local item = queue.items[index]

			if item ~= nil and (is_queued(item.state) or item.state == "cancelled") then
				finish(item, "cancelled")
				self.cancelled_count += 1
			end
		end

		reset_queue(queue)
	end

	self.pending_count = 0
end

--[=[
	Returns the number of queued or yielded tasks.

	@within Async
	@return number
]=]
async.PendingCount = function(self: Scheduler): number
	return self.pending_count
end

--[=[
	Returns an independent snapshot of scheduler metrics.

	@within Async
	@return Stats
]=]
async.GetStats = function(self: Scheduler): Stats
	return {
		pending = self.pending_count,
		active = self.active_count,
		completed = self.completed_count,
		failed = self.failed_count,
		cancelled = self.cancelled_count,
		last_step_seconds = self.last_step_seconds,
		max_step_seconds = self.max_step_seconds,
	}
end

--[=[
	Stops processing and cancels queued work.

	@within Async
]=]
async.Destroy = function(self: Scheduler): ()
	self:Stop()
	self:Clear()
end

return async
