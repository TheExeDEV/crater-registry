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

local row = {}

local MIN_CAPACITY = 64

local refill = function(target: buffer, from: number, count: number, color: number): ()
	for pixel = from, from + count - 1 do
		buffer.writeu32(target, pixel * 4, color)
	end
end

row.get = function(context: Context, width: number, color: number): buffer
	local target = context._row_buffer

	if target == nil or buffer.len(target) < width * 4 then
		local previous = if target == nil then 0 else buffer.len(target) // 4
		local capacity = math.max(width, MIN_CAPACITY, math.floor(previous * 1.5))
		target = buffer.create(capacity * 4)
		context._row_buffer = target
		context._row_width = 0
		context._row_color = nil
	end

	local result = target :: buffer

	if context._row_color ~= color then
		refill(result, 0, width, color)
		context._row_color = color
		context._row_width = width
	elseif context._row_width < width then
		refill(result, context._row_width, width - context._row_width, color)
		context._row_width = width
	end

	return result
end

return row
