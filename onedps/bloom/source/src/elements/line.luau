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
local color4 = require("../color4")
local damage = require("../damage")
local row = require("../row")

type Context = Types.Context

type BrushRow = {
	y: number,
	min_x: number,
	alphas: { number },
	solid: boolean,
}

local line = {}

local alpha_lut: { number } = table.create(256)
local alpha_key = -1

local clip_test = function(p: number, q: number, t0: number, t1: number): (boolean, number, number)
	if p == 0 then
		return q >= 0, t0, t1
	end

	local ratio = q / p

	if p < 0 then
		if ratio > t1 then
			return false, t0, t1
		end

		if ratio > t0 then
			t0 = ratio
		end

		return true, t0, t1
	end

	if ratio < t0 then
		return false, t0, t1
	end

	if ratio < t1 then
		t1 = ratio
	end

	return true, t0, t1
end

local clip_segment = function(
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	left: number,
	top: number,
	right: number,
	bottom: number
): (boolean, number, number, number, number)
	local dx, dy = x1 - x0, y1 - y0
	local t0, t1 = 0, 1
	local visible

	visible, t0, t1 = clip_test(-dx, x0 - left, t0, t1)

	if not visible then
		return false, 0, 0, 0, 0
	end

	visible, t0, t1 = clip_test(dx, right - x0, t0, t1)

	if not visible then
		return false, 0, 0, 0, 0
	end

	visible, t0, t1 = clip_test(-dy, y0 - top, t0, t1)

	if not visible then
		return false, 0, 0, 0, 0
	end

	visible, t0, t1 = clip_test(dy, bottom - y0, t0, t1)

	if not visible then
		return false, 0, 0, 0, 0
	end

	return true, x0 + t0 * dx, y0 + t0 * dy, x0 + t1 * dx, y0 + t1 * dy
end

local build_brush = function(radius: number): { BrushRow }
	local brush: { BrushRow } = {}
	local reach = radius + 0.5

	for offset_y = -radius, radius do
		local alphas: { number } = {}
		local count = 0
		local first_x = 0

		for offset_x = -radius, radius do
			local distance = math.sqrt(offset_x * offset_x + offset_y * offset_y)

			if distance <= reach then
				if count == 0 then
					first_x = offset_x
				end

				count += 1
				alphas[count] = math.floor(255 * math.clamp(radius + 1 - distance, 0, 1) + 0.5)
			end
		end

		if count > 0 then
			brush[#brush + 1] = {
				y = offset_y,
				min_x = first_x,
				alphas = alphas,
				solid = alphas[1] == 255,
			}
		end
	end

	return brush
end

line.horizontal = function(context: Context, x0: number, y: number, x1: number, color: number): ()
	local left, top, right, bottom = clip.viewport(context)
	y = math.floor(y)

	if left > right or top > bottom or y < top or y > bottom then
		return
	end

	local start_x = math.floor(x0)
	local end_x = math.floor(x1)

	if start_x > end_x then
		start_x, end_x = end_x, start_x
	end

	if start_x < left then
		start_x = left
	end

	if end_x > right then
		end_x = right
	end

	if start_x > end_x then
		return
	end

	local width = end_x - start_x + 1
	buffer.copy(
		context.pixel_buffer,
		((y - 1) * context.res_x + start_x - 1) * 4,
		row.get(context, width, color),
		0,
		width * 4
	)
	damage.mark_rect(context, start_x, y, end_x, y)
end

line.vertical = function(context: Context, x: number, y0: number, y1: number, color: number): ()
	local left, top, right, bottom = clip.viewport(context)
	x = math.floor(x)

	if left > right or top > bottom or x < left or x > right then
		return
	end

	local start_y = math.floor(y0)
	local end_y = math.floor(y1)

	if start_y > end_y then
		start_y, end_y = end_y, start_y
	end

	if start_y < top then
		start_y = top
	end

	if end_y > bottom then
		end_y = bottom
	end

	if start_y > end_y then
		return
	end

	local pixels = context.pixel_buffer
	local offset = (start_y - 1) * context.res_x * 4 + (x - 1) * 4
	local stride = context.res_x * 4

	for _ = start_y, end_y do
		buffer.writeu32(pixels, offset, color)
		offset += stride
	end

	damage.mark_rect(context, x, start_y, x, end_y)
end

line.draw = function(context: Context, x0: number, y0: number, x1: number, y1: number, color: number): ()
	local left, top, right, bottom = clip.viewport(context)

	if left > right or top > bottom then
		return
	end

	local clipped_x0, clipped_y0, clipped_x1, clipped_y1 = x0, y0, x1, y1

	if
		not (
			x0 >= left
			and x0 <= right
			and y0 >= top
			and y0 <= bottom
			and x1 >= left
			and x1 <= right
			and y1 >= top
			and y1 <= bottom
		)
	then
		local visible
		visible, clipped_x0, clipped_y0, clipped_x1, clipped_y1 =
			clip_segment(x0, y0, x1, y1, left, top, right, bottom)

		if not visible then
			return
		end
	end

	local x, y = math.floor(clipped_x0 + 0.5), math.floor(clipped_y0 + 0.5)
	local end_x, end_y = math.floor(clipped_x1 + 0.5), math.floor(clipped_y1 + 0.5)

	if y == end_y then
		line.horizontal(context, x, y, end_x, color)
		return
	end

	if x == end_x then
		line.vertical(context, x, y, end_y, color)
		return
	end

	if x > end_x then
		x, end_x = end_x, x
		y, end_y = end_y, y
	end

	local step_y = if y < end_y then 1 else -1
	local dx, dy = math.abs(end_x - x), math.abs(end_y - y)
	local err = dx - dy
	local pixels = context.pixel_buffer
	local stride = context.res_x * 4
	local step_offset_y = step_y * stride
	local offset = (y - 1) * stride + (x - 1) * 4

	for _ = 1, math.max(dx, dy) do
		buffer.writeu32(pixels, offset, color)

		local doubled = err * 2

		if doubled > -dy then
			err -= dy
			offset += 4
		end

		if doubled < dx then
			err += dx
			offset += step_offset_y
		end
	end

	buffer.writeu32(pixels, offset, color)
	damage.mark_rect(context, math.min(x, end_x), math.min(y, end_y), math.max(x, end_x), math.max(y, end_y))
end

line.draw_aa = function(
	context: Context,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	thickness: number,
	color: number
): ()
	local radius = math.max(0, math.floor(thickness / 2))
	local color_alpha = bit32.extract(color, 24, 8)

	if color_alpha == 0 then
		return
	end

	if radius == 0 and color_alpha == 255 then
		line.draw(context, x0, y0, x1, y1, color)
		return
	end

	local left, top, right, bottom = clip.viewport(context)

	if left > right or top > bottom then
		return
	end

	local visible, clipped_x0, clipped_y0, clipped_x1, clipped_y1 =
		clip_segment(x0, y0, x1, y1, left, top, right, bottom)

	if not visible then
		return
	end

	local center_min_x = math.floor(math.min(clipped_x0, clipped_x1) + 0.5)
	local center_max_x = math.floor(math.max(clipped_x0, clipped_x1) + 0.5)
	local center_min_y = math.floor(math.min(clipped_y0, clipped_y1) + 0.5)
	local center_max_y = math.floor(math.max(clipped_y0, clipped_y1) + 0.5)

	local stamp_left = math.max(left, center_min_x - radius)
	local stamp_top = math.max(top, center_min_y - radius)
	local stamp_right = math.min(right, center_max_x + radius)
	local stamp_bottom = math.min(bottom, center_max_y + radius)

	if stamp_left > stamp_right or stamp_top > stamp_bottom then
		return
	end

	local stamp_width = stamp_right - stamp_left + 1
	local stamp_height = stamp_bottom - stamp_top + 1
	local area = stamp_width * stamp_height
	local coverage = context._coverage

	if coverage == nil or buffer.len(coverage) < area then
		local previous = if coverage == nil then 0 else buffer.len(coverage)
		local capacity = math.max(area, math.floor(previous * 1.5), 1024)
		coverage = buffer.create(capacity)
		context._coverage = coverage
	end

	local coverage_buffer = coverage :: buffer
	local brush: { BrushRow } = context._brush[radius]

	if brush == nil then
		brush = build_brush(radius)
		context._brush[radius] = brush
	end

	local row_min, row_max, touched = context._aa_min, context._aa_max, context._aa_touched

	for local_row = 0, stamp_height - 1 do
		row_min[local_row] = -1
	end

	local touched_count = 0
	local length_x, length_y = clipped_x1 - clipped_x0, clipped_y1 - clipped_y0
	local spacing = if radius > 1 then radius else 1
	local steps = math.ceil(math.max(math.abs(length_x), math.abs(length_y)) / spacing)
	local brush_count = #brush

	for step = 0, steps do
		local t = if steps == 0 then 0 else step / steps
		local center_x = math.floor(clipped_x0 + length_x * t + 0.5)
		local center_y = math.floor(clipped_y0 + length_y * t + 0.5)

		for brush_index = 1, brush_count do
			local brush_row = brush[brush_index]
			local py = center_y + brush_row.y

			if py >= stamp_top and py <= stamp_bottom then
				local alphas = brush_row.alphas
				local first_px = center_x + brush_row.min_x
				local last_px = first_px + #alphas - 1

				if last_px >= stamp_left and first_px <= stamp_right then
					local row_left = math.max(first_px, stamp_left)
					local row_right = math.min(last_px, stamp_right)
					local local_row = py - stamp_top
					local left_x, right_x = row_left - stamp_left, row_right - stamp_left

					if row_min[local_row] == -1 then
						touched_count += 1
						touched[touched_count] = local_row
						row_min[local_row] = left_x
						row_max[local_row] = right_x
					else
						if left_x < row_min[local_row] then
							row_min[local_row] = left_x
						end

						if right_x > row_max[local_row] then
							row_max[local_row] = right_x
						end
					end

					local coverage_offset = local_row * stamp_width + left_x

					if brush_row.solid then
						buffer.fill(coverage_buffer, coverage_offset, 255, right_x - left_x + 1)
					else
						local sample = row_left - first_px + 1

						for _ = left_x, right_x do
							local alpha = alphas[sample]

							if alpha > buffer.readu8(coverage_buffer, coverage_offset) then
								buffer.writeu8(coverage_buffer, coverage_offset, alpha)
							end

							sample += 1
							coverage_offset += 1
						end
					end
				end
			end
		end
	end

	local pixels = context.pixel_buffer
	local stride = context.res_x * 4
	local base_rgb = bit32.band(color, 0x00FFFFFF)

	if alpha_key ~= color_alpha then
		for sample = 0, 255 do
			alpha_lut[sample] = math.floor(sample * color_alpha / 255 + 0.5)
		end

		alpha_key = color_alpha
	end

	for index = 1, touched_count do
		local local_row = touched[index]
		local first_x, last_x = row_min[local_row], row_max[local_row]
		local pixel_offset = (stamp_top + local_row - 1) * stride + (stamp_left + first_x - 1) * 4
		local coverage_offset = local_row * stamp_width + first_x

		for _ = first_x, last_x do
			local alpha = alpha_lut[buffer.readu8(coverage_buffer, coverage_offset)]

			if alpha == 255 then
				buffer.writeu32(pixels, pixel_offset, base_rgb + 0xFF000000)
			elseif alpha ~= 0 then
				buffer.writeu32(
					pixels,
					pixel_offset,
					color4.blend_over(base_rgb + alpha * 16777216, buffer.readu32(pixels, pixel_offset))
				)
			end

			pixel_offset += 4
			coverage_offset += 1
		end

		buffer.fill(coverage_buffer, local_row * stamp_width + first_x, 0, last_x - first_x + 1)
	end

	damage.mark_rect(context, stamp_left, stamp_top, stamp_right, stamp_bottom)
end

return line

