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
local Color4 = require("./color4")
local Damage = require("./damage")
local Row = require("./row")
local Support = require("./support")
local Async = require("./async")
local Pipeline = require("./pipeline")
local Platform = require("./platform")

type Context = Types.Context
type Tile = Types.Tile
type Options = Types.Options
type ViewState = Types.ViewState

type Layout = {
	base_x_scale: number,
	base_y_scale: number,
	base_x_offset: number,
	base_y_offset: number,
	size_x_scale: number,
	size_x_offset: number,
	size_y_scale: number,
	size_y_offset: number,
	inv_res_x: number,
	inv_res_y: number,
}

type Resources = {
	res_x: number,
	res_y: number,
	tile_size: number,
	size_x: number,
	size_y: number,
	tiles: { [number]: Tile },
	_col_tile: { [number]: number },
	_col_local: { [number]: number },
	_row_base: { [number]: number },
	_row_local: { [number]: number },
}

local MIN_TILE_SIZE = 2
local MAX_TILE_SIZE = 1024
local MAX_TILE_COUNT = 4096
local BYTES_PER_PIXEL = 4
local CLEAR_INVALID = math.huge

local new_stats = function(): Types.Stats
	return {
		update_calls = 0,
		last_update_seconds = 0,
		uploaded_tiles = 0,
		uploaded_bytes = 0,
		upload_seconds = 0,
		shader_pixels = 0,
		texture_pixels = 0,
		text_glyphs = 0,
		scheduler_pending = 0,
		scheduler_active = 0,
		scheduler_completed = 0,
		scheduler_failed = 0,
		scheduler_cancelled = 0,
		scheduler_last_step_seconds = 0,
		scheduler_max_step_seconds = 0,
	}
end

local full_viewport = function(res_x: number, res_y: number): Types.Viewport
	return { x = 1, y = 1, w = res_x, h = res_y }
end

local validate_resolution = function(resolution: any, caller: string): (number, number)
	local res_x = math.floor(resolution.X)
	local res_y = math.floor(resolution.Y)

	if res_x < 1 or res_y < 1 then
		error(`{caller} expects a positive resolution`, 0)
	end

	return res_x, res_y
end

local tile_grid = function(res_x: number, res_y: number, tile_size: number): (number, number)
	return -(-res_x // tile_size), -(-res_y // tile_size)
end

local resolve_tile_size = function(res_x: number, res_y: number, requested: number, caller: string): number
	local tile_size = math.clamp(math.floor(requested), MIN_TILE_SIZE, MAX_TILE_SIZE)
	local size_x, size_y = tile_grid(res_x, res_y, tile_size)

	while size_x * size_y > MAX_TILE_COUNT and tile_size < MAX_TILE_SIZE do
		tile_size += 1
		size_x, size_y = tile_grid(res_x, res_y, tile_size)
	end

	if size_x * size_y > MAX_TILE_COUNT then
		error(
			`{caller}: {res_x}x{res_y} needs more than {MAX_TILE_COUNT} tiles even at tile_size {MAX_TILE_SIZE}; use a smaller resolution`,
			0
		)
	end

	return tile_size
end

local create_editable = function(width: number, height: number): any
	local editable = Platform.create_editable_image(width, height)

	if editable == nil then
		error(`Bloom: EditableImage memory budget is exhausted ({width}x{height} tile)`, 0)
	end

	return editable
end

local layout_for = function(reference: any, res_x: number, res_y: number): Layout?
	if reference == nil then
		return nil
	end

	local position = reference.Position
	local size = reference.Size
	local anchor = reference.AnchorPoint

	return {
		base_x_scale = position.X.Scale - anchor.X * size.X.Scale,
		base_y_scale = position.Y.Scale - anchor.Y * size.Y.Scale,
		base_x_offset = position.X.Offset - anchor.X * size.X.Offset,
		base_y_offset = position.Y.Offset - anchor.Y * size.Y.Offset,
		size_x_scale = size.X.Scale,
		size_x_offset = size.X.Offset,
		size_y_scale = size.Y.Scale,
		size_y_offset = size.Y.Offset,
		inv_res_x = 1 / res_x,
		inv_res_y = 1 / res_y,
	}
end

local tile_layout = function(layout: Layout, x: number, y: number, width: number, height: number): (any, any)
	local u = x * layout.inv_res_x
	local v = y * layout.inv_res_y
	local w = width * layout.inv_res_x
	local h = height * layout.inv_res_y

	local tile_position = Platform.udim2(
		layout.base_x_scale + u * layout.size_x_scale,
		layout.base_x_offset + u * layout.size_x_offset,
		layout.base_y_scale + v * layout.size_y_scale,
		layout.base_y_offset + v * layout.size_y_offset
	)
	local tile_size = Platform.udim2(
		layout.size_x_scale * w,
		layout.size_x_offset * w,
		layout.size_y_scale * h,
		layout.size_y_offset * h
	)

	return tile_position, tile_size
end

local clone_label = function(
	context: Context,
	editable: any,
	layout: Layout?,
	x: number,
	y: number,
	width: number,
	height: number
): any
	local reference = context.reference

	if reference == nil or layout == nil then
		return nil
	end

	local position, size = tile_layout(layout, x, y, width, height)
	local image = reference:Clone()

	image.AnchorPoint = Platform.vector2(0, 0)
	image.Position = position
	image.Size = size
	image.ImageContent = Platform.content_from_object(editable)
	image.Visible = true
	image.Parent = context.parent

	return image
end

local create_tile = function(
	context: Context,
	x: number,
	y: number,
	width: number,
	height: number,
	layout: Layout?
): Tile
	local editable = create_editable(width, height)
	local image: any = nil
	local ok, err = pcall(function()
		image = clone_label(context, editable, layout, x, y, width, height)
	end)

	if not ok then
		editable:Destroy()
		error(err, 0)
	end

	return {
		x = x,
		y = y,
		w = width,
		h = height,
		editable = editable,
		image = image,
		dirty_full = true,
		dmin_x = width + 1,
		dmin_y = height + 1,
		dmax_x = 0,
		dmax_y = 0,
	}
end

local build_maps = function(
	res_x: number,
	res_y: number,
	tile_size: number,
	size_x: number
): ({ [number]: number }, { [number]: number }, { [number]: number }, { [number]: number })
	local _col_tile: { [number]: number } = {}
	local _col_local: { [number]: number } = {}
	local _row_base: { [number]: number } = {}
	local _row_local: { [number]: number } = {}

	for x = 1, res_x do
		local column = (x - 1) // tile_size
		_col_tile[x] = column
		_col_local[x] = x - column * tile_size
	end

	for y = 1, res_y do
		local row = (y - 1) // tile_size
		_row_base[y] = row * size_x
		_row_local[y] = y - row * tile_size
	end

	return _col_tile, _col_local, _row_base, _row_local
end

local destroy_tiles = function(tiles: { [number]: Tile }): ()
	for _, tile in tiles do
		if tile.image ~= nil then
			tile.image:Destroy()
		end
	end

	for _, tile in tiles do
		tile.editable:Destroy()
	end
end

local build = function(context: Context, res_x: number, res_y: number, tile_size: number): Resources
	local size_x, size_y = tile_grid(res_x, res_y, tile_size)
	local layout = layout_for(context.reference, res_x, res_y)
	local tiles: { [number]: Tile } = {}

	local ok, err = pcall(function()
		for tile_row = 0, size_y - 1 do
			local y = tile_row * tile_size
			local height = math.min(tile_size, res_y - y)

			for tile_column = 0, size_x - 1 do
				local x = tile_column * tile_size
				local width = math.min(tile_size, res_x - x)
				tiles[tile_row * size_x + tile_column] = create_tile(context, x, y, width, height, layout)
			end
		end
	end)

	if not ok then
		destroy_tiles(tiles)
		error(err, 0)
	end

	local _col_tile, _col_local, _row_base, _row_local = build_maps(res_x, res_y, tile_size, size_x)

	return {
		res_x = res_x,
		res_y = res_y,
		tile_size = tile_size,
		size_x = size_x,
		size_y = size_y,
		tiles = tiles,
		_col_tile = _col_tile,
		_col_local = _col_local,
		_row_base = _row_base,
		_row_local = _row_local,
	}
end

local build_tiles = function(context: Context): Resources
	return build(context, context.res_x, context.res_y, context.tile_size)
end

local new_context = function(
	res_x: number,
	res_y: number,
	tile_size: number,
	options: Options,
	pixel_buffer: buffer?
): Context
	local state: ViewState = {
		clear_color = options.clear_color or Color4.Zero,
		viewport = full_viewport(res_x, res_y),
	}

	return {
		res_x = res_x,
		res_y = res_y,
		tile_size = tile_size,
		size_x = 0,
		size_y = 0,
		parent = nil,
		reference = nil,
		pixel_buffer = pixel_buffer or buffer.create(res_x * res_y * BYTES_PER_PIXEL),
		tiles = {},
		auto_clip = options.auto_clip ~= false,
		state = state,
		async = Async.new(options.async_budget, options.scheduler_options),
		pipeline = Pipeline.new(),
		stats = new_stats(),
		_destroyed = false,
		_owns_resources = true,
		_clear_color_applied = Color4.Zero,
		_clear_frame_exposed = false,
		_col_tile = {},
		_col_local = {},
		_row_base = {},
		_row_local = {},
		_row_buffer = nil,
		_row_color = nil,
		_row_width = 0,
		_upload_scratch = nil,
		_upload_scratch_bytes = 0,
		_upload_staging = nil,
		_upload_staging_bytes = 0,
		_upload_cancel = nil,
		_pending_uploads = 0,
		_tile_generations = {},
		_dirty_tiles = {},
		_dirty_list = {},
		_upload_batch_active = false,
		_texture_columns = {},
		_texture_columns_capacity = 0,
		_coverage = nil,
		_aa_min = {},
		_aa_max = {},
		_aa_touched = {},
		_brush = {},
	}
end

local commit = function(context: Context, resources: Resources): ()
	context.res_x = resources.res_x
	context.res_y = resources.res_y
	context.tile_size = resources.tile_size
	context.size_x = resources.size_x
	context.size_y = resources.size_y
	context.tiles = resources.tiles
	context._col_tile = resources._col_tile
	context._col_local = resources._col_local
	context._row_base = resources._row_base
	context._row_local = resources._row_local
	context._clear_color_applied = Color4.Zero
	context._clear_frame_exposed = false
	table.clear(context._dirty_tiles)
	table.clear(context._dirty_list)

	for index, tile in context.tiles do
		if tile.dirty_full or (tile.dmin_x <= tile.dmax_x and tile.dmin_y <= tile.dmax_y) then
			context._dirty_tiles[index] = true
			context._dirty_list[#context._dirty_list + 1] = index
		end
	end
end

local cancel_uploads = function(context: Context): ()
	local cancel_hook = context._upload_cancel

	if cancel_hook ~= nil then
		context._upload_cancel = nil
		cancel_hook(context)
	end

	local generations = context._tile_generations

	for index in context.tiles do
		generations[index] = (generations[index] or 0) + 1
	end

	context._pending_uploads = 0
	context._upload_batch_active = false
end

local release_tiles = function(context: Context): ()
	if context._owns_resources then
		for _, tile in context.tiles do
			if tile.image ~= nil then
				tile.image:Destroy()
			end
		end

		for _, tile in context.tiles do
			tile.editable:Destroy()
		end
	end

	table.clear(context.tiles)
	table.clear(context._dirty_tiles)
	table.clear(context._dirty_list)
	context._upload_scratch = nil
	context._upload_scratch_bytes = 0
	context._upload_staging = nil
	context._upload_staging_bytes = 0
	context._coverage = nil
	table.clear(context._aa_min)
	table.clear(context._aa_max)
	table.clear(context._aa_touched)
end

local create = function(resolution: any, parent: any, reference: any, options: Options?): Context
	local settings: Options = options or {}
	local res_x, res_y = validate_resolution(resolution, "Bloom.Create")

	Support.assert_supported()

	local tile_size = resolve_tile_size(res_x, res_y, settings.tile_size or MAX_TILE_SIZE, "Bloom.Create")
	local context = new_context(res_x, res_y, tile_size, settings)

	context.parent = parent
	context.reference = reference

	local ok, resources = pcall(build_tiles, context)

	if not ok then
		context.async:Destroy()
		error(resources, 0)
	end

	commit(context, resources)

	if context.auto_clip and parent ~= nil and type(parent.IsA) == "function" and parent:IsA("GuiObject") then
		parent.ClipsDescendants = true
	end

	return context
end

local from_editable = function(editable: any): Context
	local size = editable.Size
	local res_x, res_y = validate_resolution(size, "Bloom.FromEditableImage")

	if res_x > MAX_TILE_SIZE or res_y > MAX_TILE_SIZE then
		error("Bloom.FromEditableImage supports images up to 1024x1024", 0)
	end

	local pixels = editable:ReadPixelsBuffer(Platform.vector2(0, 0), size)

	if pixels == nil then
		error("Bloom.FromEditableImage could not read the EditableImage pixels", 0)
	end

	local context = new_context(res_x, res_y, MAX_TILE_SIZE, { auto_clip = false }, pixels)
	context._owns_resources = false
	context._clear_color_applied = CLEAR_INVALID
	context._clear_frame_exposed = true
	context.size_x = 1
	context.size_y = 1
	context.tiles = {
		[0] = {
			x = 0,
			y = 0,
			w = res_x,
			h = res_y,
			editable = editable,
			image = nil,
			dirty_full = false,
			dmin_x = res_x + 1,
			dmin_y = res_y + 1,
			dmax_x = 0,
			dmax_y = 0,
		},
	}

	local _col_tile, _col_local, _row_base, _row_local = build_maps(res_x, res_y, MAX_TILE_SIZE, 1)
	context._col_tile = _col_tile
	context._col_local = _col_local
	context._row_base = _row_base
	context._row_local = _row_local

	return context
end

local clear = function(context: Context, color32: number?): ()
	if context._destroyed then
		return
	end

	local color = color32 or context.state.clear_color

	if context._clear_color_applied == color and not context._clear_frame_exposed then
		Damage.mark_all(context)
		return
	end

	local pixels = context.pixel_buffer
	local stride = context.res_x * BYTES_PER_PIXEL

	if color == 0 then
		buffer.fill(pixels, 0, 0, stride * context.res_y)
	else
		local row_buffer = Row.get(context, context.res_x, color)

		for row = 0, context.res_y - 1 do
			buffer.copy(pixels, row * stride, row_buffer, 0, stride)
		end
	end

	context._clear_color_applied = color
	Damage.mark_all(context)
end

local set_viewport = function(context: Context, x: number, y: number, width: number, height: number): ()
	local floor_x = math.floor(x)
	local floor_y = math.floor(y)
	local left = math.max(1, floor_x)
	local top = math.max(1, floor_y)
	local right = math.min(context.res_x, floor_x + math.floor(width) - 1)
	local bottom = math.min(context.res_y, floor_y + math.floor(height) - 1)

	context.state.viewport = {
		x = left,
		y = top,
		w = math.max(0, right - left + 1),
		h = math.max(0, bottom - top + 1),
	}
end

local reset_viewport = function(context: Context): ()
	context.state.viewport = full_viewport(context.res_x, context.res_y)
end

local mark_dirty = function(context: Context, x0: number, y0: number, x1: number, y1: number): ()
	if context._destroyed then
		return
	end

	Damage.mark_rect(context, x0, y0, x1, y1)
end

local resize = function(context: Context, resolution: any): ()
	if context._destroyed then
		return
	end

	assert(context._owns_resources, "Resize is not supported for contexts created with FromEditableImage")

	local res_x, res_y = validate_resolution(resolution, "Bloom.Resize")
	local tile_size = resolve_tile_size(res_x, res_y, context.tile_size, "Bloom.Resize")
	local resources = build(context, res_x, res_y, tile_size)
	local allocated, pixels = pcall(buffer.create, res_x * res_y * BYTES_PER_PIXEL)

	if not allocated then
		destroy_tiles(resources.tiles)
		error(pixels, 0)
	end

	cancel_uploads(context)
	release_tiles(context)

	context.pixel_buffer = pixels
	context.state.viewport = full_viewport(res_x, res_y)
	commit(context, resources)
end

local destroy = function(context: Context): ()
	if context._destroyed then
		return
	end

	context._destroyed = true
	context.async:Destroy()
	cancel_uploads(context)
	release_tiles(context)

	context._row_buffer = nil
	context._row_color = nil
	context._row_width = 0
	table.clear(context._brush)
end

local get_state = function(context: Context): any
	return context.state
end

local get_buffer = function(context: Context): buffer
	context._clear_frame_exposed = true
	return context.pixel_buffer
end

local get_stats = function(context: Context): Types.Stats
	local scheduler = context.async:GetStats()
	local stats = context.stats

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

local reset_stats = function(context: Context): ()
	context.stats = new_stats()
end

return {
	resolve_tile_size = resolve_tile_size,
	layout_for = layout_for,
	build_tiles = build_tiles,
	create_tile = create_tile,
	create = create,
	from_editable = from_editable,
	clear = clear,
	set_viewport = set_viewport,
	reset_viewport = reset_viewport,
	mark_dirty = mark_dirty,
	resize = resize,
	destroy = destroy,
	get_state = get_state,
	get_buffer = get_buffer,
	get_stats = get_stats,
	reset_stats = reset_stats,
	cancel_uploads = cancel_uploads,
}

