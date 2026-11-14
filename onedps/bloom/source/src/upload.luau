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
local Core = require("./core")
local Damage = require("./damage")
local Platform = require("./platform")

type Context = Types.Context
type Tile = Types.Tile
type Task = Types.Task

type Chunk = {
	indices: { number },
	generations: { number },
}

type Session = {
	tasks: { [number]: Task },
	chunks: { [number]: Chunk },
	scheduled: { [number]: boolean },
	next_id: number,
	started: number,
	upload_seconds: number,
}

local BYTES_PER_PIXEL = 4
local MIN_BUDGET = 0.0001
local CHUNK_SIZE = 16

local env: any = _G

local sessions: { [any]: Session } = {}
setmetatable(sessions :: any, { __mode = "k" })

local is_dirty = function(tile: Tile): boolean
	return tile.dirty_full or (tile.dmin_x <= tile.dmax_x and tile.dmin_y <= tile.dmax_y)
end

local compact_dirty = function(context: Context): ()
	local list = context._dirty_list
	local write = 1

	for read = 1, #list do
		local index = list[read]
		local tile = context.tiles[index]

		if context._dirty_tiles[index] and tile ~= nil and is_dirty(tile) then
			list[write] = index
			write += 1
			context._dirty_tiles[index] = nil
		else
			context._dirty_tiles[index] = nil
		end
	end

	for index = write, #list do
		list[index] = nil
	end

	for index = 1, write - 1 do
		context._dirty_tiles[list[index]] = true
	end
end

local report_failure = function(index: number, err: any): ()
	local message = "[Bloom] Failed to upload tile " .. index .. ": " .. tostring(err)
	local warn_fn: any = env.warn

	if warn_fn ~= nil then
		warn_fn(message)
		return
	end

	warn(message)
end

local ensure_exact = function(current: buffer?, byte_count: number): buffer
	if current ~= nil and buffer.len(current) == byte_count then
		return current
	end

	return buffer.create(byte_count)
end

local ensure_staging = function(context: Context, byte_count: number): buffer
	local staging = ensure_exact(context._upload_staging, byte_count)

	if staging ~= context._upload_staging then
		context._upload_staging = staging
		context._upload_staging_bytes = byte_count
	end

	return staging
end

local ensure_scratch = function(context: Context, byte_count: number): buffer
	local scratch = ensure_exact(context._upload_scratch, byte_count)

	if scratch ~= context._upload_scratch then
		context._upload_scratch = scratch
		context._upload_scratch_bytes = byte_count
	end

	return scratch
end

local stage_tile_pixels = function(context: Context, tile: Tile): buffer
	local source_stride = context.res_x * BYTES_PER_PIXEL
	local tile_stride = tile.w * BYTES_PER_PIXEL
	local source_offset = (tile.y * context.res_x + tile.x) * BYTES_PER_PIXEL
	local scratch = ensure_staging(context, tile_stride * tile.h)

	if tile_stride == source_stride then
		buffer.copy(scratch, 0, context.pixel_buffer, source_offset, tile_stride * tile.h)
		return scratch
	end

	for row = 0, tile.h - 1 do
		buffer.copy(scratch, row * tile_stride, context.pixel_buffer, source_offset + row * source_stride, tile_stride)
	end

	return scratch
end

local copy_tile_region = function(
	context: Context,
	tile: Tile,
	left: number,
	top: number,
	right: number,
	bottom: number
): (number, number, number, number)
	local width = right - left + 1
	local height = bottom - top + 1
	local row_bytes = width * BYTES_PER_PIXEL
	local byte_count = row_bytes * height
	local scratch_buffer = ensure_scratch(context, byte_count)
	local source_stride = context.res_x * BYTES_PER_PIXEL
	local source_offset = ((tile.y + top - 1) * context.res_x + (tile.x + left - 1)) * BYTES_PER_PIXEL

	for row = 0, height - 1 do
		buffer.copy(scratch_buffer, row * row_bytes, context.pixel_buffer, source_offset + row * source_stride, row_bytes)
	end

	return left, top, right, bottom
end

local upload_tile = function(context: Context, index: number): (number, number)
	local tile = context.tiles[index]

	if tile == nil or not is_dirty(tile) then
		return 0, 0
	end

	local full = tile.dirty_full
	local left = 0
	local top = 0
	local right = 0
	local bottom = 0

	if not full then
		left = math.max(1, math.floor(tile.dmin_x))
		top = math.max(1, math.floor(tile.dmin_y))
		right = math.min(tile.w, math.floor(tile.dmax_x))
		bottom = math.min(tile.h, math.floor(tile.dmax_y))

		if left == 1 and top == 1 and right == tile.w and bottom == tile.h then
			full = true
		end
	end

	local position: any = nil
	local size: any = nil
	local source: buffer? = nil
	local uploaded_bytes = 0

	if full then
		local scratch = stage_tile_pixels(context, tile)
		position = Platform.vector2(0, 0)
		size = Platform.vector2(tile.w, tile.h)
		source = scratch
		uploaded_bytes = tile.w * tile.h * BYTES_PER_PIXEL
	else
		local local_left, local_top, local_right, local_bottom = copy_tile_region(context, tile, left, top, right, bottom)
		local width = local_right - local_left + 1
		local height = local_bottom - local_top + 1

		position = Platform.vector2(local_left - 1, local_top - 1)
		size = Platform.vector2(width, height)
		source = context._upload_scratch :: buffer
		uploaded_bytes = width * height * BYTES_PER_PIXEL
	end

	local editable = tile.editable
	local started = os.clock()
	local ok, err = pcall(editable.WritePixelsBuffer, editable, position, size, source)
	local elapsed = os.clock() - started

	if not ok then
		report_failure(index, err)
		return 0, elapsed
	end

	Damage.reset(tile, context, index)
	context.stats.uploaded_tiles += 1
	context.stats.uploaded_bytes += uploaded_bytes

	return uploaded_bytes, elapsed
end

local finish_batch = function(context: Context, session: Session): ()
	if not context._upload_batch_active or sessions[context] ~= session then
		return
	end

	context.stats.update_calls += 1
	context.stats.last_update_seconds = os.clock() - session.started
	context.stats.upload_seconds += session.upload_seconds

	context.pipeline:Run(context, "afterUpload")

	if sessions[context] ~= session or context._pending_uploads ~= 0 then
		return
	end

	context._upload_batch_active = false
	context._upload_cancel = nil
	sessions[context] = nil
end

local finish_chunk = function(context: Context, session: Session, chunk_id: number, chunk: Chunk): ()
	local indices = chunk.indices
	local generations = chunk.generations

	for position = 1, #indices do
		if sessions[context] ~= session or context._destroyed then
			return
		end

		local index = indices[position]

		if session.scheduled[index] then
			session.scheduled[index] = nil
			local pending = context._pending_uploads - 1
			context._pending_uploads = if pending > 0 then pending else 0

			if context._tile_generations[index] == generations[position] then
				local uploaded_bytes, elapsed = upload_tile(context, index)
				session.upload_seconds += elapsed

				if uploaded_bytes > 0 then
					context.pipeline:Run(context, "tileUploaded")
				end
			end
		end
	end

	if sessions[context] ~= session then
		return
	end

	session.tasks[chunk_id] = nil
	session.chunks[chunk_id] = nil

	if context._pending_uploads == 0 then
		finish_batch(context, session)
	end
end

local submit_chunk = function(context: Context, session: Session, indices: { number }, generations: { number }): ()
	local chunk_id = session.next_id
	session.next_id = chunk_id + 1
	local chunk: Chunk = { indices = indices, generations = generations }
	session.chunks[chunk_id] = chunk
	session.tasks[chunk_id] = context.async:Submit(finish_chunk, context, session, chunk_id, chunk)
end

local session_for = function(context: Context): Session
	local session = sessions[context]

	if session == nil then
		session = {
			tasks = {},
			chunks = {},
			scheduled = {},
			next_id = 0,
			started = 0,
			upload_seconds = 0,
		}
		sessions[context] = session
	end

	return session
end

local cancel_queued = function(context: Context): ()
	local session = sessions[context]

	if session ~= nil then
		for _, task in session.tasks do
			task:Cancel()
		end

		table.clear(session.tasks)
		table.clear(session.chunks)
		table.clear(session.scheduled)
	end

	sessions[context] = nil
end

local cancel = function(context: Context): ()
	cancel_queued(context)
	Core.cancel_uploads(context)
end

local update = function(context: Context): ()
	if context._destroyed then
		return
	end

	cancel(context)
	local started = os.clock()
	context.pipeline:Run(context, "beforeUpload")

	local upload_seconds = 0
	compact_dirty(context)
	local dirty_list = context._dirty_list

	for position = 1, #dirty_list do
		local index = dirty_list[position]
		local tile = context.tiles[index]

		if tile ~= nil and is_dirty(tile) then
			local _, elapsed = upload_tile(context, index)
			upload_seconds += elapsed
		else
			context._dirty_tiles[index] = nil
		end
	end

	context.pipeline:Run(context, "afterUpload")
	context.stats.update_calls += 1
	context.stats.last_update_seconds = os.clock() - started
	context.stats.upload_seconds += upload_seconds
end

local update_async = function(context: Context, budget: number?): ()
	if context._destroyed then
		return
	end

	if budget ~= nil then
		context.async.budget = math.max(budget, MIN_BUDGET)
	end

	local session = session_for(context)
	context._upload_cancel = cancel_queued
	local generations = context._tile_generations

	for chunk_id, task in session.tasks do
		local chunk = session.chunks[chunk_id]
		local stale = chunk == nil

		if not stale then
			local indices = chunk.indices

			for position = 1, #indices do
				if generations[indices[position]] ~= chunk.generations[position] then
					stale = true
					break
				end
			end
		end

		if task:IsFinished() or stale then
			if not task:IsFinished() then
				task:Cancel()
			end

			if chunk ~= nil then
				for position = 1, #chunk.indices do
					session.scheduled[chunk.indices[position]] = nil
				end
			end

			session.tasks[chunk_id] = nil
			session.chunks[chunk_id] = nil
		end
	end

	local live = 0

	for chunk_id, task in session.tasks do
		if not task:IsFinished() then
			local chunk = session.chunks[chunk_id]

			if chunk ~= nil then
				for position = 1, #chunk.indices do
					if session.scheduled[chunk.indices[position]] then
						live += 1
					end
				end
			end
		end
	end

	context._pending_uploads = live

	local started = os.clock()
	context.pipeline:Run(context, "beforeUpload")
	compact_dirty(context)

	local dirty_list = context._dirty_list
	local dirty = 0
	local indices: { number } = {}
	local chunk_generations: { number } = {}

	for position = 1, #dirty_list do
		local index = dirty_list[position]
		local tile = context.tiles[index]

		if tile ~= nil and context._dirty_tiles[index] and is_dirty(tile) then
			dirty += 1

			if not session.scheduled[index] then
				local generation = generations[index] or 0
				generation += 1
				generations[index] = generation
				session.scheduled[index] = true
				indices[#indices + 1] = index
				chunk_generations[#chunk_generations + 1] = generation
				context._pending_uploads += 1

				if #indices == CHUNK_SIZE then
					submit_chunk(context, session, indices, chunk_generations)
					indices = {}
					chunk_generations = {}
				end
			end
		else
			context._dirty_tiles[index] = nil
		end
	end

	if #indices > 0 then
		submit_chunk(context, session, indices, chunk_generations)
	end

	if context._pending_uploads == 0 then
		if context._upload_batch_active and live == 0 and dirty == 0 then
			return
		end

		context._upload_batch_active = false
		context._upload_cancel = nil
		context.pipeline:Run(context, "afterUpload")
		sessions[context] = nil
		return
	end

	if live == 0 then
		context._upload_batch_active = true
		session.started = started
		session.upload_seconds = 0
	end

	context.async:Start()
end

return {
	update = update,
	update_async = update_async,
	cancel = cancel,
}
