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
local Clip = require("../clip")
local Color4 = require("../color4")
local Damage = require("../damage")
local Row = require("../row")

type Context = Types.Context

local circle = {}

local floor = math.floor
local ceil = math.ceil
local sqrt = math.sqrt
local max = math.max
local min = math.min

local mark = function(context: Context, min_x: number, min_y: number, max_x: number, max_y: number): ()
	Damage.mark_rect(context, min_x, min_y, max_x, max_y)
end

circle.draw = function(context: Context, center_x: number, center_y: number, radius: number, color: number): ()
	if radius < 0 then
		return
	end

	local cx = floor(center_x + 0.5)
	local cy = floor(center_y + 0.5)
	local r = floor(radius + 0.5)
	local view_x0, view_y0, view_x1, view_y1 = Clip.viewport(context)
	local top = max(view_y0, cy - r)
	local bottom = min(view_y1, cy + r)
	local min_x = context.res_x
	local min_y = context.res_y
	local max_x = 0
	local max_y = 0

	for y = top, bottom do
		local dy = y - cy
		local span = floor(sqrt(r * r - dy * dy) + 0.5)
		local left = max(view_x0, cx - span)
		local right = min(view_x1, cx + span)

		if left <= right then
			local width = right - left + 1
			buffer.copy(context.pixel_buffer, ((y - 1) * context.res_x + left - 1) * 4, Row.get(context, width, color), 0, width * 4)
			min_x = min(min_x, left)
			max_x = max(max_x, right)
			min_y = min(min_y, y)
			max_y = max(max_y, y)
		end
	end

	if max_x >= min_x then
		mark(context, min_x, min_y, max_x, max_y)
	end
end

circle.draw_aa = function(context: Context, center_x: number, center_y: number, radius: number, color: number): ()
	local base_alpha = bit32.extract(color, 24, 8)

	if radius < 0 or base_alpha == 0 then
		return
	end

	local view_x0, view_y0, view_x1, view_y1 = Clip.viewport(context)
	local left = max(view_x0, floor(center_x - radius - 0.5))
	local top = max(view_y0, floor(center_y - radius - 0.5))
	local right = min(view_x1, ceil(center_x + radius + 0.5))
	local bottom = min(view_y1, ceil(center_y + radius + 0.5))
	local min_x = context.res_x
	local min_y = context.res_y
	local max_x = 0
	local max_y = 0
	local pixels = context.pixel_buffer

	if base_alpha == 255 then
		local outer = radius + 0.5
		local inner = radius - 0.5
		local outer_sq = outer * outer
		local inner_sq = inner * inner

		local paint = function(x: number, y: number, row_offset: number, dy2: number): ()
			local dx = x - center_x
			local coverage = outer - sqrt(dx * dx + dy2)

			if coverage > 1 then
				coverage = 1
			end

			if coverage > 0 then
				local alpha = floor(255 * coverage + 0.5)

				if alpha > 0 then
					local offset = (row_offset + x - 1) * 4

					if alpha == 255 then
						buffer.writeu32(pixels, offset, color)
					else
						buffer.writeu32(
							pixels,
							offset,
							Color4.blend_over(Color4.set_a(color, alpha), buffer.readu32(pixels, offset))
						)
					end

					min_x = min(min_x, x)
					max_x = max(max_x, x)
					min_y = min(min_y, y)
					max_y = max(max_y, y)
				end
			end
		end

		for y = top, bottom do
			local dy = y - center_y
			local dy2 = dy * dy
			local outer_remainder = outer_sq - dy2

			if outer_remainder > 0 then
				local outer_span = ceil(sqrt(outer_remainder)) - 1
				local row_left = max(view_x0, ceil(center_x - outer_span))
				local row_right = min(view_x1, floor(center_x + outer_span))

				if row_left <= row_right then
					local row_offset = (y - 1) * context.res_x
					local inner_remainder = inner_sq - dy2
					local inner_span = if inner_remainder > 0 then floor(sqrt(inner_remainder)) else -1
					local interior_left = max(row_left, ceil(center_x - inner_span))
					local interior_right = min(row_right, floor(center_x + inner_span))

					if interior_left <= interior_right then
						local width = interior_right - interior_left + 1
						buffer.copy(
							pixels,
							(row_offset + interior_left - 1) * 4,
							Row.get(context, width, color),
							0,
							width * 4
						)
						min_x = min(min_x, interior_left)
						max_x = max(max_x, interior_right)
						min_y = min(min_y, y)
						max_y = max(max_y, y)

						for x = row_left, interior_left - 1 do
							paint(x, y, row_offset, dy2)
						end

						for x = interior_right + 1, row_right do
							paint(x, y, row_offset, dy2)
						end
					else
						for x = row_left, row_right do
							paint(x, y, row_offset, dy2)
						end
					end
				end
			end
		end

		if max_x >= min_x then
			mark(context, min_x, min_y, max_x, max_y)
		end

		return
	end

	for y = top, bottom do
		local dy = y - center_y
		local dy2 = dy * dy
		local row_offset = (y - 1) * context.res_x

		for x = left, right do
			local dx = x - center_x
			local coverage = radius + 0.5 - sqrt(dx * dx + dy2)

			if coverage > 0 then
				if coverage > 1 then
					coverage = 1
				end

				local alpha = floor(base_alpha * coverage + 0.5)

				if alpha > 0 then
					local offset = (row_offset + x - 1) * 4
					local destination = buffer.readu32(pixels, offset)
					buffer.writeu32(pixels, offset, Color4.blend_over(Color4.set_a(color, alpha), destination))
					min_x = min(min_x, x)
					max_x = max(max_x, x)
					min_y = min(min_y, y)
					max_y = max(max_y, y)
				end
			end
		end
	end

	if max_x >= min_x then
		mark(context, min_x, min_y, max_x, max_y)
	end
end

return circle
