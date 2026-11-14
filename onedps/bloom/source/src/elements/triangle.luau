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

local triangle = {}

local floor = math.floor
local min = math.min
local max = math.max

triangle.draw = function(
	context: Context,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	color: number
): ()
	local ax, ay = floor(x0), floor(y0)
	local bx, by = floor(x1), floor(y1)
	local cx, cy = floor(x2), floor(y2)

	if ay > by or (ay == by and ax > bx) then
		ax, ay, bx, by = bx, by, ax, ay
	end

	if by > cy or (by == cy and bx > cx) then
		bx, by, cx, cy = cx, cy, bx, by
	end

	if ay > by or (ay == by and ax > bx) then
		ax, ay, bx, by = bx, by, ax, ay
	end

	local clip_x0, clip_y0, clip_x1, clip_y1 = clip.viewport(context)

	if clip_x1 < clip_x0 or clip_y1 < clip_y0 then
		return
	end

	if ay == cy then
		if ay < clip_y0 or ay > clip_y1 then
			return
		end

		local left = max(clip_x0, ax)
		local right = min(clip_x1, cx)

		if left <= right then
			local width = right - left + 1
			local row_buffer = row.get(context, width, color)
			buffer.copy(
				context.pixel_buffer,
				(ay - 1) * context.res_x * 4 + (left - 1) * 4,
				row_buffer,
				0,
				width * 4
			)
			damage.mark_rect(context, left, ay, right, ay)
		end

		return
	end

	local first_row = max(ay, clip_y0)
	local last_row = min(cy, clip_y1)

	if first_row > last_row then
		return
	end

	local inv_ac = (cx - ax) / (cy - ay)
	local inv_ab = if by > ay then (bx - ax) / (by - ay) else 0
	local inv_bc = if cy > by then (cx - bx) / (cy - by) else 0

	local pixels = context.pixel_buffer
	local stride = context.res_x * 4
	local mark_left, mark_top = math.huge, math.huge
	local mark_right, mark_bottom = -math.huge, -math.huge

	for y = first_row, last_row do
		local x_ac = ax + (y - ay) * inv_ac
		local other = if by > ay and y <= by
			then ax + (y - ay) * inv_ab
			else bx + (y - by) * inv_bc
		local left = floor(min(x_ac, other) + 0.5)
		local right = floor(max(x_ac, other) + 0.5)

		if left < clip_x0 then
			left = clip_x0
		end
		if right > clip_x1 then
			right = clip_x1
		end

		if left <= right then
			local width = right - left + 1
			local row_buffer = row.get(context, width, color)
			buffer.copy(pixels, (y - 1) * stride + (left - 1) * 4, row_buffer, 0, width * 4)

			if left < mark_left then
				mark_left = left
			end
			if right > mark_right then
				mark_right = right
			end
			if y < mark_top then
				mark_top = y
			end
			if y > mark_bottom then
				mark_bottom = y
			end
		end
	end

	if mark_left <= mark_right then
		damage.mark_rect(context, mark_left, mark_top, mark_right, mark_bottom)
	end
end

triangle.polygon = function(context: Context, points: { any }, color: number): ()
	local count = #points

	if count < 3 then
		return
	end

	local flat: { number } = {}

	if type(points[1]) == "table" then
		for index = 1, count do
			local point = points[index]
			local x = point.x or point.X
			local y = point.y or point.Y

			if x == nil then
				x = point[1]
				y = point[2]
			end

			if type(x) ~= "number" or type(y) ~= "number" then
				return
			end

			flat[#flat + 1] = x
			flat[#flat + 1] = y
		end
	else
		for index = 1, count do
			local value = points[index]

			if type(value) ~= "number" then
				return
			end

			flat[index] = value
		end
	end

	local vertices = #flat // 2

	if vertices < 3 then
		return
	end

	local x0 = flat[1]
	local y0 = flat[2]

	for index = 2, vertices - 1 do
		triangle.draw(
			context,
			x0,
			y0,
			flat[index * 2 - 1],
			flat[index * 2],
			flat[index * 2 + 1],
			flat[index * 2 + 2],
			color
		)
	end
end

return triangle

