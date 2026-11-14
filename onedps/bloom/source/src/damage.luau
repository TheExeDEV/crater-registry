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

type Context = Types.Context
type Tile = Types.Tile

local damage = {}

local add = function(context: Context, index: number): ()
	local dirty_tiles = context._dirty_tiles

	if dirty_tiles == nil then
		return
	end

	if not dirty_tiles[index] then
		dirty_tiles[index] = true
		context._dirty_list[#context._dirty_list + 1] = index
	end
end

local expand = function(tile: Tile, x0: number, y0: number, x1: number, y1: number): ()
	if tile.dirty_full then
		return
	end

	local local_x0 = math.max(x0, tile.x + 1) - tile.x
	local local_y0 = math.max(y0, tile.y + 1) - tile.y
	local local_x1 = math.min(x1, tile.x + tile.w) - tile.x
	local local_y1 = math.min(y1, tile.y + tile.h) - tile.y

	if local_x0 < tile.dmin_x then
		tile.dmin_x = local_x0
	end
	if local_y0 < tile.dmin_y then
		tile.dmin_y = local_y0
	end
	if local_x1 > tile.dmax_x then
		tile.dmax_x = local_x1
	end
	if local_y1 > tile.dmax_y then
		tile.dmax_y = local_y1
	end
end

damage.mark_rect = function(context: Context, x0: number, y0: number, x1: number, y1: number): ()
	if context._destroyed then
		return
	end

	local left = math.floor(x0)
	local top = math.floor(y0)
	local right = math.floor(x1)
	local bottom = math.floor(y1)

	if left > right then
		left, right = right, left
	end
	if top > bottom then
		top, bottom = bottom, top
	end
	if left < 1 then
		left = 1
	end
	if top < 1 then
		top = 1
	end
	if right > context.res_x then
		right = context.res_x
	end
	if bottom > context.res_y then
		bottom = context.res_y
	end
	if left > right or top > bottom then
		return
	end

	context._clear_color_applied = math.huge

	local tile_size = context.tile_size
	local size_x = context.size_x
	local column_start = (left - 1) // tile_size
	local column_end = (right - 1) // tile_size
	local row_start = (top - 1) // tile_size
	local row_end = (bottom - 1) // tile_size

	for tile_row = row_start, row_end do
		local base = tile_row * size_x
		for tile_column = column_start, column_end do
			local index = base + tile_column
			expand(context.tiles[index], left, top, right, bottom)
			add(context, index)
		end
	end
end

damage.mark_all = function(context: Context): ()
	for index, tile in context.tiles do
		tile.dirty_full = true
		tile.dmin_x = tile.w + 1
		tile.dmin_y = tile.h + 1
		tile.dmax_x = 0
		tile.dmax_y = 0
		add(context, index)
	end
end

damage.reset = function(tile: Tile, context: Context?, index: number?): ()
	tile.dirty_full = false
	tile.dmin_x = tile.w + 1
	tile.dmin_y = tile.h + 1
	tile.dmax_x = 0
	tile.dmax_y = 0

	if context ~= nil and index ~= nil and context._dirty_tiles ~= nil then
		context._dirty_tiles[index] = nil
	end
end

damage.forget = function(context: Context, index: number): ()
	if context._dirty_tiles ~= nil then
		context._dirty_tiles[index] = nil
	end
end

return damage

