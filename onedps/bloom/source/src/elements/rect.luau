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

local rect = {}

local function get_row(context: Context, width: number, color32: number): buffer
	local row = context._rect_row_buffer

	if row ~= nil and context._rect_row_width == width and context._rect_row_color == color32 then
		return row
	end

	local new_row = buffer.create(width * 4)

	for column = 0, width - 1 do
		buffer.writeu32(new_row, column * 4, color32)
	end

	context._rect_row_buffer = new_row
	context._rect_row_width = width
	context._rect_row_color = color32
	return new_row
end

--[=[
	Draws a filled rectangle. Corners are inclusive and may be given in any order.

	@within Bloom
	@param x0 number
	@param y0 number
	@param x1 number
	@param y1 number
	@param color32 number -- Packed RGBA color.
]=]
rect.DrawRectangle = function(self: Context, x0: number, y0: number, x1: number, y1: number, color32: number): ()
	local viewport = self.state.viewport

	local left = math.max(1, viewport.x, math.floor(math.min(x0, x1)))
	local top = math.max(1, viewport.y, math.floor(math.min(y0, y1)))
	local right = math.min(self.res_x, viewport.x + viewport.w - 1, math.floor(math.max(x0, x1)))
	local bottom = math.min(self.res_y, viewport.y + viewport.h - 1, math.floor(math.max(y0, y1)))

	if left > right or top > bottom then
		return
	end

	local width = right - left + 1
	local row = get_row(self, width, color32)
	local stride = self.res_x * 4

	for y = top, bottom do
		buffer.copy(self.pixel_buffer, (y - 1) * stride + (left - 1) * 4, row, 0, width * 4)
	end

	self:_MarkDirtyRect(left, top, right, bottom)
end

return rect
