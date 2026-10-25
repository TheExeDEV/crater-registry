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
type Context = Types.self

local pixel = {}

local function pixel_offset(context: Context, x: number, y: number): number
	return ((y - 1) * context.res_x + (x - 1)) * 4
end

local function is_inside_viewport(context: Context, x: number, y: number): boolean
	local viewport = context.state.viewport

	return x >= viewport.x and x < viewport.x + viewport.w and y >= viewport.y and y < viewport.y + viewport.h
end

local function is_inside_framebuffer(context: Context, x: number, y: number): boolean
	return x >= 1 and x <= context.res_x and y >= 1 and y <= context.res_y
end

--[=[
	Draws one pixel. Coordinates outside the viewport or framebuffer are ignored.

	@within Bloom
	@param x number -- 1-based column.
	@param y number -- 1-based row.
	@param color32 number -- Packed RGBA color.
]=]
pixel.DrawPixel = function(self: Context, x: number, y: number, color32: number): ()
	x, y = math.floor(x), math.floor(y)

	if not is_inside_viewport(self, x, y) or not is_inside_framebuffer(self, x, y) then
		return
	end

	buffer.writeu32(self.pixel_buffer, pixel_offset(self, x, y), color32)
	self:_MarkDirty(x, y)
end

--[=[
	Reads one pixel. Returns `0` outside the framebuffer.

	@within Bloom
	@param x number -- 1-based column.
	@param y number -- 1-based row.
	@return number -- Packed RGBA color.
]=]
pixel.ReadPixel = function(self: Context, x: number, y: number): number
	x, y = math.floor(x), math.floor(y)

	if not is_inside_framebuffer(self, x, y) then
		return 0
	end

	return buffer.readu32(self.pixel_buffer, pixel_offset(self, x, y))
end

--[=[
	Draws a pixel without bounds checks. `x` and `y` must be integers inside the framebuffer.

	@within Bloom
	@param x number
	@param y number
	@param color32 number
]=]
pixel.DrawPixelUnsafe = function(self: Context, x: number, y: number, color32: number): ()
	buffer.writeu32(self.pixel_buffer, pixel_offset(self, x, y), color32)

	local tile_x = (x - 1) // self.tile_size
	local tile_y = (y - 1) // self.tile_size
	self._dirty_tiles[tile_x + tile_y * self.size_x] = true
end

--[=[
	Reads a pixel without bounds checks. `x` and `y` must be integers inside the framebuffer.

	@within Bloom
	@param x number
	@param y number
	@return number
]=]
pixel.ReadPixelUnsafe = function(self: Context, x: number, y: number): number
	return buffer.readu32(self.pixel_buffer, pixel_offset(self, x, y))
end

return pixel
