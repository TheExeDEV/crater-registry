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
local Clip = require("./clip")
local Damage = require("./damage")

type Context = Types.Context
type PixelCallback = Types.PixelCallback

local floor = math.floor
local max = math.max
local min = math.min
local readu32 = buffer.readu32
local writeu32 = buffer.writeu32

local each = {}

each.each_pixel = function(
	context: Context,
	callback: PixelCallback?,
	x0: number?,
	y0: number?,
	x1: number?,
	y1: number?
): number
	if context._destroyed then
		return 0
	end

	local viewport_x0, viewport_y0, viewport_x1, viewport_y1 = Clip.viewport(context)
	if viewport_x1 < viewport_x0 or viewport_y1 < viewport_y0 then
		return 0
	end

	local left: number
	local right: number
	local top: number
	local bottom: number

	if x0 == nil and x1 == nil then
		left, right = viewport_x0, viewport_x1
	else
		local first = if x0 == nil then x1 :: number else x0
		local second = if x1 == nil then first else x1
		left = floor(min(first, second))
		right = floor(max(first, second))
	end

	if y0 == nil and y1 == nil then
		top, bottom = viewport_y0, viewport_y1
	else
		local first = if y0 == nil then y1 :: number else y0
		local second = if y1 == nil then first else y1
		top = floor(min(first, second))
		bottom = floor(max(first, second))
	end

	if left < viewport_x0 then
		left = viewport_x0
	end
	if right > viewport_x1 then
		right = viewport_x1
	end
	if top < viewport_y0 then
		top = viewport_y0
	end
	if bottom > viewport_y1 then
		bottom = viewport_y1
	end

	if left > right or top > bottom then
		return 0
	end

	local visited = (right - left + 1) * (bottom - top + 1)
	if callback == nil then
		return visited
	end

	local pixels = context.pixel_buffer
	local stride = context.res_x * 4
	local changed_x0 = math.huge
	local changed_y0 = math.huge
	local changed_x1 = -math.huge
	local changed_y1 = -math.huge
	local row_offset = (top - 1) * stride + (left - 1) * 4

	for y = top, bottom do
		local offset = row_offset

		for x = left, right do
			local color = readu32(pixels, offset)
			local replacement = callback(x, y, color)

			if replacement ~= nil and replacement ~= color then
				writeu32(pixels, offset, replacement)

				if x < changed_x0 then
					changed_x0 = x
				end
				if x > changed_x1 then
					changed_x1 = x
				end
				if y < changed_y0 then
					changed_y0 = y
				end
				if y > changed_y1 then
					changed_y1 = y
				end
			end

			offset += 4
		end

		row_offset += stride
	end

	if changed_x0 <= changed_x1 then
		Damage.mark_rect(context, changed_x0, changed_y0, changed_x1, changed_y1)
	end

	return visited
end

return each
