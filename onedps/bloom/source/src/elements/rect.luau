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
local clip = require("../clip")
local damage = require("../damage")
local row = require("../row")

type Context = Types.Context

local rect = {}

rect.draw = function(context: Context, x0: number, y0: number, x1: number, y1: number, color: number): ()
	local clip_x0, clip_y0, clip_x1, clip_y1 = clip.viewport(context)

	if clip_x1 < clip_x0 or clip_y1 < clip_y0 then
		return
	end

	local left = math.max(clip_x0, math.floor(math.min(x0, x1)))
	local top = math.max(clip_y0, math.floor(math.min(y0, y1)))
	local right = math.min(clip_x1, math.floor(math.max(x0, x1)))
	local bottom = math.min(clip_y1, math.floor(math.max(y0, y1)))

	if left > right or top > bottom then
		return
	end

	local width = right - left + 1
	local row_bytes = width * 4
	local stride = context.res_x * 4
	local offset = (top - 1) * stride + (left - 1) * 4
	local pixels = context.pixel_buffer
	local row_buffer = row.get(context, width, color)

	for _ = top, bottom do
		buffer.copy(pixels, offset, row_buffer, 0, row_bytes)
		offset += stride
	end

	damage.mark_rect(context, left, top, right, bottom)
end

return rect

