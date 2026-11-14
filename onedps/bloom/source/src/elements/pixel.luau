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

local Types = require("../types")

type Context = Types.Context

local pixel = {}

local floor = math.floor
local huge = math.huge
local writeu32 = buffer.writeu32
local readu32 = buffer.readu32

pixel.draw = function(context: Context, x: number, y: number, color: number): ()
	if context._destroyed then
		return
	end

	local pixel_x = floor(x)
	local pixel_y = floor(y)
	local viewport = context.state.viewport

	if pixel_x < viewport.x or pixel_y < viewport.y then
		return
	end
	if pixel_x >= viewport.x + viewport.w or pixel_y >= viewport.y + viewport.h then
		return
	end

	writeu32(context.pixel_buffer, ((pixel_y - 1) * context.res_x + pixel_x - 1) * 4, color)
	context._clear_color_applied = huge

	local tile_index = context._col_tile[pixel_x] + context._row_base[pixel_y]
	local tile = context.tiles[tile_index]
	if tile.dirty_full then
		return
	end

	local had_damage = tile.dmin_x <= tile.dmax_x and tile.dmin_y <= tile.dmax_y
	local local_x = context._col_local[pixel_x]
	local local_y = context._row_local[pixel_y]

	if local_x < tile.dmin_x then
		tile.dmin_x = local_x
	end
	if local_y < tile.dmin_y then
		tile.dmin_y = local_y
	end
	if local_x > tile.dmax_x then
		tile.dmax_x = local_x
	end
	if local_y > tile.dmax_y then
		tile.dmax_y = local_y
	end

	if not had_damage then
		local dirty_tiles = context._dirty_tiles

		if dirty_tiles ~= nil and not dirty_tiles[tile_index] then
			dirty_tiles[tile_index] = true
			context._dirty_list[#context._dirty_list + 1] = tile_index
		end
	end
end

pixel.draw_unsafe = function(context: Context, x: number, y: number, color: number): ()
	if context._destroyed then
		return
	end

	local pixel_x = floor(x)
	local pixel_y = floor(y)

	writeu32(context.pixel_buffer, ((pixel_y - 1) * context.res_x + pixel_x - 1) * 4, color)
	context._clear_color_applied = huge

	local tile_index = context._col_tile[pixel_x] + context._row_base[pixel_y]
	local tile = context.tiles[tile_index]
	if tile.dirty_full then
		return
	end

	local had_damage = tile.dmin_x <= tile.dmax_x and tile.dmin_y <= tile.dmax_y
	local local_x = context._col_local[pixel_x]
	local local_y = context._row_local[pixel_y]

	if local_x < tile.dmin_x then
		tile.dmin_x = local_x
	end
	if local_y < tile.dmin_y then
		tile.dmin_y = local_y
	end
	if local_x > tile.dmax_x then
		tile.dmax_x = local_x
	end
	if local_y > tile.dmax_y then
		tile.dmax_y = local_y
	end

	if not had_damage then
		local dirty_tiles = context._dirty_tiles

		if dirty_tiles ~= nil and not dirty_tiles[tile_index] then
			dirty_tiles[tile_index] = true
			context._dirty_list[#context._dirty_list + 1] = tile_index
		end
	end
end

pixel.read = function(context: Context, x: number, y: number): number
	local pixel_x = floor(x)
	local pixel_y = floor(y)

	if pixel_x < 1 or pixel_y < 1 or pixel_x > context.res_x or pixel_y > context.res_y then
		return 0
	end

	return readu32(context.pixel_buffer, ((pixel_y - 1) * context.res_x + pixel_x - 1) * 4)
end

pixel.read_unsafe = function(context: Context, x: number, y: number): number
	local pixel_x = floor(x)
	local pixel_y = floor(y)

	return readu32(context.pixel_buffer, ((pixel_y - 1) * context.res_x + pixel_x - 1) * 4)
end

return pixel


