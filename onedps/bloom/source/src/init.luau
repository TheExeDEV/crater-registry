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

local Types = require("@self/types")
local elements = require("@self/elements")
local color4 = require("@self/color4")
local async = require("@self/async")
local pipeline_module = require("@self/pipeline")
local texture_module = require("@self/texture")
local shader_module = require("@self/shader")
local font_module = require("@self/font")
local support = require("@self/support")

type Context = Types.self
export type Bloom = Context
export type Options = Types.BloomOptions
export type SchedulerOptions = Types.SchedulerOptions
export type SubmitOptions = Types.SubmitOptions
export type Stats = Types.BloomStats
export type TextureDrawOptions = Types.TextureDrawOptions
export type FontOptions = Types.FontOptions
export type UniformMap = Types.Uniforms
export type Task = Types.Task
export type SupportReport = support.Report

local MAX_TILE_SIZE = 1024
local BYTES_PER_PIXEL = 4

local asset_service = game:GetService("AssetService")

--[=[
	@class Bloom

	Low-level graphics library that presents an RGBA `buffer` through `EditableImage` tiles.
]=]
local bloom = {}
bloom.__index = bloom

local function new_stats(): Types.Stats
	return {
		update_calls = 0,
		last_update_seconds = 0,
		uploaded_tiles = 0,
		uploaded_bytes = 0,
		upload_seconds = 0,
		shader_pixels = 0,
		texture_pixels = 0,
		text_glyphs = 0,
	}
end

local function full_viewport(res_x: number, res_y: number): Types.Viewport
	return { x = 1, y = 1, w = res_x, h = res_y }
end

local function validate_resolution(resolution: Vector2, caller: string): (number, number)
	local res_x, res_y = math.floor(resolution.X), math.floor(resolution.Y)
	assert(res_x > 0 and res_y > 0, caller .. " expects a positive resolution")
	return res_x, res_y
end

local function create_editable_image(width: number, height: number): EditableImage
	local editable: EditableImage? = asset_service:CreateEditableImage({ Size = Vector2.new(width, height) })

	assert(editable, `Bloom: EditableImage memory budget is exhausted ({width}x{height} tile)`)
	return editable
end

local function create_tile_label(
	self: Context,
	editable: EditableImage,
	x: number,
	y: number,
	width: number,
	height: number
): ImageLabel?
	local reference = self.reference
	if reference == nil then
		return nil
	end

	local image = reference:Clone()
	image.Size = UDim2.fromOffset(width, height)
	image.Position = UDim2.fromOffset(x, y)
	image.ImageContent = Content.fromObject(editable)
	image.Visible = true
	image.Parent = self.parent
	return image
end

local function destroy_resources(self: Context): ()
	if self._owns_resources then
		for _, image in self.images do
			image:Destroy()
		end
		for _, editable in self.editables do
			editable:Destroy()
		end
	end

	table.clear(self.tiles)
	table.clear(self.editables)
	table.clear(self.images)
	table.clear(self._dirty_tiles)
end

local function create_resources(self: Context): ()
	local tile_size = self.tile_size
	self.size_x = -(-self.res_x // tile_size)
	self.size_y = -(-self.res_y // tile_size)

	local ok, err = pcall(function()
		for tile_y = 0, self.size_y - 1 do
			for tile_x = 0, self.size_x - 1 do
				local index = tile_x + tile_y * self.size_x
				local x, y = tile_x * tile_size, tile_y * tile_size
				local width = math.min(tile_size, self.res_x - x)
				local height = math.min(tile_size, self.res_y - y)

				local editable = create_editable_image(width, height)
				self.editables[index] = editable

				local image = create_tile_label(self, editable, x, y, width, height)

				if image then
					self.images[index] = image
				end

				self.tiles[index] = {
					x = x,
					y = y,
					w = width,
					h = height,
					editable = editable,
					buffer = buffer.create(width * height * BYTES_PER_PIXEL),
					image = image,
				}

				self._dirty_tiles[index] = true
			end
		end
	end)

	if not ok then
		destroy_resources(self)
		error(err, 0)
	end
end

local function new_context(res_x: number, res_y: number, tile_size: number, options: Types.BloomOptions): Context
	local self = {
		res_x = res_x,
		res_y = res_y,
		tile_size = tile_size,
		size_x = 0,
		size_y = 0,
		parent = nil,
		reference = nil,
		pixel_buffer = buffer.create(res_x * res_y * BYTES_PER_PIXEL),
		tiles = {},
		editables = {},
		images = {},
		auto_clip = options.auto_clip ~= false,
		state = {
			clear_color = options.clear_color or color4.Zero,
			viewport = full_viewport(res_x, res_y),
		},
		async = async.New(options.async_budget, options.scheduler_options),
		pipeline = pipeline_module.New(),
		stats = new_stats(),

		_dirty_tiles = {},
		_scheduled_tile_tasks = {},
		_pending_uploads = 0,
		_destroyed = false,
		_frame_active = false,
		_owns_resources = true,
		_clear_row_buffer = nil,
		_clear_row_color = nil,
		_rect_row_buffer = nil,
		_rect_row_width = 0,
		_rect_row_color = nil,
	}

	return setmetatable(self, bloom) :: any
end

--[=[
	Creates a Bloom context. Pass `parent` and `reference` to display the framebuffer:
	`reference` is cloned once per tile and the clones are parented to `parent`.
	Raises a descriptive error when the experience has the Mesh / Image APIs disabled
	(see `CheckSupport`).

	@within Bloom
	@param resolution Vector2 -- Framebuffer size in pixels.
	@param parent Instance? -- Container for the cloned ImageLabels (for example a Frame or ScreenGui).
	@param reference ImageLabel? -- Template cloned for each tile.
	@param options Options? -- `tile_size`, `async_budget`, `scheduler_options`, `auto_clip`, `clear_color`.
	@return Bloom
]=]
bloom.Create = function(
	resolution: Vector2,
	parent: Instance?,
	reference: ImageLabel?,
	options: Types.BloomOptions?
): Context
	local settings: Types.BloomOptions = options or {}
	local res_x, res_y = validate_resolution(resolution, "Bloom.Create")
	support.Assert()

	local tile_size = math.clamp(math.floor(settings.tile_size or MAX_TILE_SIZE), 1, MAX_TILE_SIZE)

	local self = new_context(res_x, res_y, tile_size, settings)
	self.parent = parent
	self.reference = reference

	if self.auto_clip and parent ~= nil and parent:IsA("GuiObject") then
		parent.ClipsDescendants = true
	end

	create_resources(self)
	return self
end

--[=[
	Wraps an existing EditableImage (at most 1024x1024) and the ImageLabel that displays it.
	The image's current pixels are copied into the framebuffer so drawing continues from them.
	The wrapped objects stay owned by the caller and are not destroyed by `Destroy()`.

	@within Bloom
	@param editable_image EditableImage
	@param holder ImageLabel
	@return Bloom
]=]
bloom.FromEditableImage = function(editable_image: EditableImage, holder: ImageLabel): Context
	local size = editable_image.Size
	local res_x, res_y = validate_resolution(size, "Bloom.FromEditableImage")
	assert(res_x <= MAX_TILE_SIZE and res_y <= MAX_TILE_SIZE, "Bloom.FromEditableImage supports images up to 1024x1024")

	local self = new_context(res_x, res_y, MAX_TILE_SIZE, { auto_clip = false })
	self.parent = holder.Parent
	self.reference = holder
	self.size_x, self.size_y = 1, 1
	self._owns_resources = false

	self.pixel_buffer = editable_image:ReadPixelsBuffer(Vector2.zero, size)
	self.editables[0] = editable_image
	self.images[0] = holder

	self.tiles[0] = {
		x = 0,
		y = 0,
		w = res_x,
		h = res_y,
		editable = editable_image,
		buffer = buffer.create(res_x * res_y * BYTES_PER_PIXEL),
		image = holder,
	}

	return self
end

--[=[
	@private
	Marks the tile containing pixel (`x`, `y`) as dirty.
]=]
bloom._MarkDirty = function(self: Context, x: number, y: number): ()
	if x < 1 or y < 1 or x > self.res_x or y > self.res_y then
		return
	end

	local tile_x, tile_y = (x - 1) // self.tile_size, (y - 1) // self.tile_size
	self._dirty_tiles[tile_x + tile_y * self.size_x] = true
end

--[=[
	@private
	Marks every tile intersecting the inclusive rectangle as dirty. The rectangle is clipped to the framebuffer.
]=]
bloom._MarkDirtyRect = function(self: Context, x0: number, y0: number, x1: number, y1: number): ()
	local left, right = math.max(1, math.min(x0, x1)), math.min(self.res_x, math.max(x0, x1))
	local top, bottom = math.max(1, math.min(y0, y1)), math.min(self.res_y, math.max(y0, y1))

	if left > right or top > bottom then
		return
	end

	local tile_size = self.tile_size

	for tile_y = (top - 1) // tile_size, (bottom - 1) // tile_size do
		for tile_x = (left - 1) // tile_size, (right - 1) // tile_size do
			self._dirty_tiles[tile_x + tile_y * self.size_x] = true
		end
	end
end

--[=[
	Marks an inclusive rectangle dirty after writing to `GetBuffer()` directly.

	@within Bloom
	@param x0 number -- Left, 1-based.
	@param y0 number -- Top, 1-based.
	@param x1 number -- Right, inclusive.
	@param y1 number -- Bottom, inclusive.
]=]
bloom.MarkDirty = function(self: Context, x0: number, y0: number, x1: number, y1: number): ()
	self:_MarkDirtyRect(x0, y0, x1, y1)
end

-- Copies the tile's region of the framebuffer into its staging buffer.
local function copy_tile_pixels(self: Context, tile: Types.Tile): ()
	local source_stride = self.res_x * BYTES_PER_PIXEL
	local tile_stride = tile.w * BYTES_PER_PIXEL
	local source_offset = (tile.y * self.res_x + tile.x) * BYTES_PER_PIXEL

	if tile_stride == source_stride then
		buffer.copy(tile.buffer, 0, self.pixel_buffer, source_offset, tile_stride * tile.h)
		return
	end

	for row = 0, tile.h - 1 do
		buffer.copy(tile.buffer, row * tile_stride, self.pixel_buffer, source_offset + row * source_stride, tile_stride)
	end
end

local function upload_tile(self: Context, index: number): boolean
	local tile = self.tiles[index]
	if tile == nil then
		return false
	end

	copy_tile_pixels(self, tile)

	local started = os.clock()
	local editable = tile.editable
	local ok, err = pcall(editable.WritePixelsBuffer, editable, Vector2.zero, Vector2.new(tile.w, tile.h), tile.buffer)
	self.stats.upload_seconds += os.clock() - started

	if not ok then
		warn(string.format("[Bloom] Failed to upload tile %d: %s", index, tostring(err)))
		return false
	end

	self._dirty_tiles[index] = nil
	self.stats.uploaded_tiles += 1
	self.stats.uploaded_bytes += buffer.len(tile.buffer)

	return true
end

local function cancel_pending_uploads(self: Context): ()
	for _, upload_task in self._scheduled_tile_tasks do
		upload_task:Cancel()
	end

	table.clear(self._scheduled_tile_tasks)
	self._pending_uploads = 0
end

local function finish_async_upload(self: Context, index: number): ()
	upload_tile(self, index)

	self._scheduled_tile_tasks[index] = nil
	self._pending_uploads = math.max(0, self._pending_uploads - 1)
	self.pipeline:Run(self, "tileUploaded")

	if self._pending_uploads == 0 then
		self.pipeline:Run(self, "afterUpload")
		self.stats.update_calls += 1
	end
end

--[=[
	Uploads every dirty tile immediately. Use this when deterministic presentation matters more
	than spreading work across frames. Note that Roblox updates only one EditableImage per frame
	on the display side, so many dirty tiles may still take several frames to appear.

	@within Bloom
]=]
bloom.Update = function(self: Context): ()
	if self._destroyed then
		return
	end

	cancel_pending_uploads(self)
	local started = os.clock()

	self.pipeline:Run(self, "beforeUpload")

	for index in self._dirty_tiles do
		upload_tile(self, index)
	end

	self.pipeline:Run(self, "afterUpload")

	self.stats.update_calls += 1
	self.stats.last_update_seconds = os.clock() - started
end

--[=[
	Queues dirty tiles on the cooperative scheduler, one upload per task, and starts it.
	`afterUpload` runs after the last queued tile is uploaded.

	@within Bloom
	@param budget number? -- Scheduler budget per step, in seconds. Persists for later steps.
]=]
bloom.UpdateAsync = function(self: Context, budget: number?): ()
	if self._destroyed then
		return
	end

	if budget then
		self.async.budget = math.max(budget, 0.0001)
	end

	self.pipeline:Run(self, "beforeUpload")

	for index in self._dirty_tiles do
		if self._scheduled_tile_tasks[index] == nil then
			self._pending_uploads += 1
			self._scheduled_tile_tasks[index] = self.async:Submit(finish_async_upload, self, index)
		end
	end

	if self._pending_uploads == 0 then
		self.pipeline:Run(self, "afterUpload")
		return
	end

	self.async:Start()
end

local function get_clear_row(self: Context, color: number): buffer
	local cached = self._clear_row_buffer
	if cached ~= nil and self._clear_row_color == color then
		return cached
	end

	local row = buffer.create(self.res_x * BYTES_PER_PIXEL)
	for x = 0, self.res_x - 1 do
		buffer.writeu32(row, x * BYTES_PER_PIXEL, color)
	end

	self._clear_row_buffer = row
	self._clear_row_color = color
	return row
end

--[=[
	Clears the whole framebuffer (ignoring the viewport).

	@within Bloom
	@param color32 number? -- Packed RGBA color. Defaults to the clear color from `SetClearColor`.
]=]
bloom.Clear = function(self: Context, color32: number?): ()
	if self._destroyed then
		return
	end

	local color = color32 or self.state.clear_color
	local row_bytes = self.res_x * BYTES_PER_PIXEL

	if color == 0 then
		buffer.fill(self.pixel_buffer, 0, 0, row_bytes * self.res_y)
	else
		local row = get_clear_row(self, color)

		for y = 0, self.res_y - 1 do
			buffer.copy(self.pixel_buffer, y * row_bytes, row, 0, row_bytes)
		end
	end

	self:_MarkDirtyRect(1, 1, self.res_x, self.res_y)
end

--[=[
	Resizes the framebuffer. Existing pixels are discarded and owned tiles are recreated.
	Not supported for contexts created with `FromEditableImage`.

	@within Bloom
	@param resolution Vector2 -- New size in pixels.
]=]
bloom.Resize = function(self: Context, resolution: Vector2): ()
	if self._destroyed then
		return
	end

	assert(self._owns_resources, "Resize is not supported for contexts created with FromEditableImage")
	local res_x, res_y = validate_resolution(resolution, "Bloom.Resize")

	cancel_pending_uploads(self)
	destroy_resources(self)

	self.res_x, self.res_y = res_x, res_y
	self.pixel_buffer = buffer.create(res_x * res_y * BYTES_PER_PIXEL)
	self.state.viewport = full_viewport(res_x, res_y)
	self._clear_row_buffer = nil
	self._clear_row_color = nil
	self._rect_row_buffer = nil
	self._rect_row_width = 0
	self._rect_row_color = nil

	create_resources(self)
end

--[=[
	Sets the viewport that clips drawing operations. It is clamped to the framebuffer.

	@within Bloom
	@param x number -- Left, 1-based.
	@param y number -- Top, 1-based.
	@param width number
	@param height number
]=]
bloom.SetViewport = function(self: Context, x: number, y: number, width: number, height: number): ()
	local left, top = math.max(1, math.floor(x)), math.max(1, math.floor(y))
	local right = math.min(self.res_x, math.floor(x) + math.floor(width) - 1)
	local bottom = math.min(self.res_y, math.floor(y) + math.floor(height) - 1)

	self.state.viewport = {
		x = left,
		y = top,
		w = math.max(0, right - left + 1),
		h = math.max(0, bottom - top + 1),
	}
end

--[=[
	Resets the viewport to the whole framebuffer.

	@within Bloom
]=]
bloom.ResetViewport = function(self: Context): ()
	self.state.viewport = full_viewport(self.res_x, self.res_y)
end

--[=[
	Begins a logical frame. The framebuffer is cleared only when `clear_color` is given.

	@within Bloom
	@param clear_color number? -- Packed RGBA color.
]=]
bloom.BeginFrame = function(self: Context, clear_color: number?): ()
	if self._destroyed then
		return
	end

	self._frame_active = true
	if clear_color ~= nil then
		self:Clear(clear_color)
	end
	self.pipeline:Run(self, "beginFrame")
end

--[=[
	Ends a logical frame and presents it.

	@within Bloom
	@param use_async boolean? -- `true` queues uploads with `UpdateAsync`; otherwise `Update` runs immediately.
]=]
bloom.EndFrame = function(self: Context, use_async: boolean?): ()
	if self._destroyed then
		return
	end

	self.pipeline:Run(self, "endFrame")
	self._frame_active = false

	if use_async then
		self:UpdateAsync()
	else
		self:Update()
	end
end

--[=[
	Sets the color used by `Clear()` when no explicit color is passed.

	@within Bloom
	@param color32 number -- Packed RGBA color.
]=]
bloom.SetClearColor = function(self: Context, color32: number): ()
	self.state.clear_color = color32
end

--[=[
	Returns the live state table. Prefer `SetViewport` over editing the viewport directly.

	@within Bloom
	@return ViewState
]=]
bloom.GetState = function(self: Context): Types.ViewState
	return self.state
end

--[=[
	Returns the live framebuffer. Call `MarkDirty` after writing to it directly.

	@within Bloom
	@return buffer
]=]
bloom.GetBuffer = function(self: Context): buffer
	return self.pixel_buffer
end

--[=[
	Registers a pipeline stage. Lower `order` values run first.

	@within Bloom
	@param name string -- Unique stage name.
	@param callback (context: Bloom, phase: string) -> ()
	@param order number? -- Defaults to 100.
]=]
bloom.RegisterStage = function(self: Context, name: string, callback: Types.StageCallback, order: number?): ()
	self.pipeline:Register(name, callback, order)
end

--[=[
	Removes a pipeline stage.

	@within Bloom
	@param name string
	@return boolean -- True when a stage was removed.
]=]
bloom.RemoveStage = function(self: Context, name: string): boolean
	return self.pipeline:Remove(name)
end

--[=[
	Queues work on the context scheduler. Call `context.async:Start()` (or `Step`) to run it.

	@within Bloom
	@param callback (...any) -> ()
	@param ... any -- Arguments forwarded to the callback.
	@return Task
]=]
bloom.Submit = function(self: Context, callback: (...any) -> (), ...: any): Types.Task
	return self.async:Submit(callback, ...)
end

--[=[
	Queues work with a priority (0 highest, 3 background) and/or an absolute `os.clock()` deadline.

	@within Bloom
	@param callback (...any) -> ()
	@param options SubmitOptions
	@param ... any -- Arguments forwarded to the callback.
	@return Task
]=]
bloom.SubmitWithOptions = function(
	self: Context,
	callback: (...any) -> (),
	options: Types.SubmitOptions,
	...: any
): Types.Task
	return self.async:SubmitWithOptions(callback, options, ...)
end

--[=[
	Returns a snapshot of the performance counters.

	@within Bloom
	@return Stats
]=]
bloom.GetStats = function(self: Context): Types.BloomStats
	local scheduler = self.async:GetStats()
	local stats = self.stats

	return {
		update_calls = stats.update_calls,
		last_update_seconds = stats.last_update_seconds,
		uploaded_tiles = stats.uploaded_tiles,
		uploaded_bytes = stats.uploaded_bytes,
		upload_seconds = stats.upload_seconds,
		shader_pixels = stats.shader_pixels,
		texture_pixels = stats.texture_pixels,
		text_glyphs = stats.text_glyphs,
		scheduler_pending = scheduler.pending,
		scheduler_active = scheduler.active,
		scheduler_completed = scheduler.completed,
		scheduler_failed = scheduler.failed,
		scheduler_cancelled = scheduler.cancelled,
		scheduler_last_step_seconds = scheduler.last_step_seconds,
		scheduler_max_step_seconds = scheduler.max_step_seconds,
	}
end

--[=[
	Resets the performance counters without touching rendering state.

	@within Bloom
]=]
bloom.ResetStats = function(self: Context): ()
	self.stats = new_stats()
end

--[=[
	Stops the scheduler and releases owned EditableImages and cloned ImageLabels.
	A destroyed context cannot be reused.

	@within Bloom
]=]
bloom.Destroy = function(self: Context): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self.async:Destroy()
	table.clear(self._scheduled_tile_tasks)
	self._pending_uploads = 0
	destroy_resources(self)
end

--[=[
	Checks whether EditableImage can be used in this experience without creating a context.
	`status` is "supported", "disabled" (Mesh / Image APIs are turned off in the experience
	settings) or "out_of_memory" (the device's EditableImage budget is exhausted).

	@within Bloom
	@return SupportReport -- `supported`, `status`, `message`, `details`.
]=]
bloom.CheckSupport = support.Check

--[=[
	Returns true when EditableImage can be created, written and read in this experience.

	@within Bloom
	@return boolean
]=]
bloom.IsSupported = support.IsSupported

--[=[
	Returns the packed RGBA color helper module.

	@within Bloom
	@return Color4
]=]
bloom.GetColor4 = function(): typeof(color4)
	return color4
end

bloom.CreateShader = shader_module.New
bloom.ApplyShader = shader_module.Apply
bloom.DrawTexture = texture_module.Draw
bloom.DrawText = font_module.DrawText

bloom.DrawPixel = elements.Pixel.DrawPixel
bloom.DrawPixelUnsafe = elements.Pixel.DrawPixelUnsafe
bloom.ReadPixel = elements.Pixel.ReadPixel
bloom.ReadPixelUnsafe = elements.Pixel.ReadPixelUnsafe
bloom.DrawLine = elements.Line.DrawLine
bloom.DrawLineAA = elements.Line.DrawLineAA
bloom.DrawHorizontalLine = elements.Line.DrawHorizontalLine
bloom.DrawVerticalLine = elements.Line.DrawVerticalLine
bloom.DrawRectangle = elements.Rect.DrawRectangle
bloom.DrawTriangle = elements.Triangle.DrawTriangle

bloom.Texture = texture_module
bloom.Shader = shader_module
bloom.Font = font_module
bloom.Async = async
bloom.Support = support

return bloom
