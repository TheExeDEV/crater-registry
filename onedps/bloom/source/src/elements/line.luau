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
local color4 = require("../color4")

type Context = Types.self
type BrushSample = { x: number, y: number, alpha: number }

local line = {}

local brush_cache: { [number]: { BrushSample } } = {}

local coverage_scratch: { [number]: number } = {}

local function viewport_bounds(context: Context): (number, number, number, number)
	local viewport = context.state.viewport

	local left = math.max(1, viewport.x)
	local top = math.max(1, viewport.y)
	local right = math.min(context.res_x, viewport.x + viewport.w - 1)
	local bottom = math.min(context.res_y, viewport.y + viewport.h - 1)

	return left, top, right, bottom
end

local function clip_test(p: number, q: number, t0: number, t1: number): (boolean, number, number)
	if p == 0 then
		return q >= 0, t0, t1
	end

	local ratio = q / p

	if p < 0 then
		if ratio > t1 then
			return false, t0, t1
		end

		return true, math.max(t0, ratio), t1
	end

	if ratio < t0 then
		return false, t0, t1
	end

	return true, t0, math.min(t1, ratio)
end

local function clip_line(
	context: Context,
	x0: number,
	y0: number,
	x1: number,
	y1: number
): (number?, number?, number?, number?)
	local left, top, right, bottom = viewport_bounds(context)
	local dx, dy = x1 - x0, y1 - y0
	local t0, t1 = 0, 1
	local visible

	visible, t0, t1 = clip_test(-dx, x0 - left, t0, t1)

	if not visible then
		return nil
	end

	visible, t0, t1 = clip_test(dx, right - x0, t0, t1)

	if not visible then
		return nil
	end

	visible, t0, t1 = clip_test(-dy, y0 - top, t0, t1)

	if not visible then
		return nil
	end

	visible, t0, t1 = clip_test(dy, bottom - y0, t0, t1)

	if not visible then
		return nil
	end

	return x0 + t0 * dx, y0 + t0 * dy, x0 + t1 * dx, y0 + t1 * dy
end

local function get_brush(radius: number): { BrushSample }
	local cached = brush_cache[radius]

	if cached then
		return cached
	end

	local brush: { BrushSample } = {}

	for offset_y = -radius, radius do
		for offset_x = -radius, radius do
			local distance = math.sqrt(offset_x * offset_x + offset_y * offset_y)

			if distance <= radius + 0.5 then
				table.insert(brush, {
					x = offset_x,
					y = offset_y,
					alpha = math.floor(255 * math.clamp(radius + 1 - distance, 0, 1) + 0.5),
				})
			end
		end
	end

	brush_cache[radius] = brush
	return brush
end

--[=[
	Draws a one-pixel Bresenham line between two points, clipped to the viewport.

	@within Bloom
	@param x0 number -- Start X.
	@param y0 number -- Start Y.
	@param x1 number -- End X.
	@param y1 number -- End Y.
	@param color32 number -- Packed RGBA color.
]=]
line.DrawLine = function(self: Context, x0: number, y0: number, x1: number, y1: number, color32: number): ()
	local clipped_x0, clipped_y0, clipped_x1, clipped_y1 = clip_line(self, x0, y0, x1, y1)

	if clipped_x0 == nil or clipped_y0 == nil or clipped_x1 == nil or clipped_y1 == nil then
		return
	end

	local x, y = math.floor(clipped_x0 + 0.5), math.floor(clipped_y0 + 0.5)
	local end_x, end_y = math.floor(clipped_x1 + 0.5), math.floor(clipped_y1 + 0.5)
	local dx, dy = math.abs(end_x - x), math.abs(end_y - y)
	local step_x = if x < end_x then 1 else -1
	local step_y = if y < end_y then 1 else -1
	local err = dx - dy

	local pixels, stride = self.pixel_buffer, self.res_x * 4
	local min_x, max_x = math.min(x, end_x), math.max(x, end_x)
	local min_y, max_y = math.min(y, end_y), math.max(y, end_y)

	while true do
		buffer.writeu32(pixels, (y - 1) * stride + (x - 1) * 4, color32)

		if x == end_x and y == end_y then
			break
		end

		local doubled = err * 2

		if doubled > -dy then
			err -= dy
			x += step_x
		end

		if doubled < dx then
			err += dx
			y += step_y
		end
	end

	self:_MarkDirtyRect(min_x, min_y, max_x, max_y)
end

--[=[
	Draws a thick line with soft edges by stamping a cached round brush along the segment.
	Each pixel is blended once with its highest brush coverage, so overlapping stamps do not
	produce darker seams. This is a raster brush, not analytic anti-aliasing.

	@within Bloom
	@param x0 number
	@param y0 number
	@param x1 number
	@param y1 number
	@param thickness number -- Diameter in pixels.
	@param color32 number -- Packed RGBA color.
]=]
line.DrawLineAA = function(
	self: Context,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	thickness: number,
	color32: number
): ()
	local clipped_x0, clipped_y0, clipped_x1, clipped_y1 = clip_line(self, x0, y0, x1, y1)

	if clipped_x0 == nil or clipped_y0 == nil or clipped_x1 == nil or clipped_y1 == nil then
		return
	end

	local radius = math.max(0, math.floor(thickness / 2))
	local brush = get_brush(radius)
	local left, top, right, bottom = viewport_bounds(self)
	local stride = self.res_x * 4
	local length_x, length_y = clipped_x1 - clipped_x0, clipped_y1 - clipped_y0
	local steps = math.ceil(math.max(math.abs(length_x), math.abs(length_y)))

	local coverage = coverage_scratch
	for step = 0, steps do
		local t = if steps == 0 then 0 else step / steps
		local center_x = math.floor(clipped_x0 + length_x * t + 0.5)
		local center_y = math.floor(clipped_y0 + length_y * t + 0.5)

		for _, sample in brush do
			local px, py = center_x + sample.x, center_y + sample.y

			if px >= left and px <= right and py >= top and py <= bottom then
				local offset = (py - 1) * stride + (px - 1) * 4
				local current = coverage[offset]

				if current == nil or sample.alpha > current then
					coverage[offset] = sample.alpha
				end
			end
		end
	end

	local pixels = self.pixel_buffer
	local base_rgb = bit32.band(color32, 0x00FFFFFF)
	local color_alpha = bit32.extract(color32, 24, 8)

	for offset, sample_alpha in coverage do
		local alpha = math.floor(sample_alpha * color_alpha / 255 + 0.5)
		local source = bit32.bor(base_rgb, bit32.lshift(alpha, 24))

		buffer.writeu32(pixels, offset, color4.BlendOver(buffer.readu32(pixels, offset), source))
	end

	table.clear(coverage)

	self:_MarkDirtyRect(
		math.floor(math.min(clipped_x0, clipped_x1)) - radius,
		math.floor(math.min(clipped_y0, clipped_y1)) - radius,
		math.floor(math.max(clipped_x0, clipped_x1)) + radius + 1,
		math.floor(math.max(clipped_y0, clipped_y1)) + radius + 1
	)
end

--[=[
	Draws a horizontal line. Endpoints are inclusive and may be given in any order.

	@within Bloom
	@param x0 number -- Start X.
	@param y number -- Row.
	@param x1 number -- End X.
	@param color32 number -- Packed RGBA color.
]=]
line.DrawHorizontalLine = function(self: Context, x0: number, y: number, x1: number, color32: number): ()
	local left, top, right, bottom = viewport_bounds(self)
	y = math.floor(y)

	local start_x = math.max(left, math.floor(math.min(x0, x1)))
	local end_x = math.min(right, math.floor(math.max(x0, x1)))

	if y < top or y > bottom or start_x > end_x then
		return
	end

	local pixels = self.pixel_buffer
	local offset = ((y - 1) * self.res_x + start_x - 1) * 4

	for _ = start_x, end_x do
		buffer.writeu32(pixels, offset, color32)

		offset += 4
	end

	self:_MarkDirtyRect(start_x, y, end_x, y)
end

--[=[
	Draws a vertical line. Endpoints are inclusive and may be given in any order.

	@within Bloom
	@param x number -- Column.
	@param y0 number -- Start Y.
	@param y1 number -- End Y.
	@param color32 number -- Packed RGBA color.
]=]
line.DrawVerticalLine = function(self: Context, x: number, y0: number, y1: number, color32: number): ()
	local left, top, right, bottom = viewport_bounds(self)
	x = math.floor(x)

	local start_y = math.max(top, math.floor(math.min(y0, y1)))
	local end_y = math.min(bottom, math.floor(math.max(y0, y1)))

	if x < left or x > right or start_y > end_y then
		return
	end

	local pixels, stride = self.pixel_buffer, self.res_x * 4
	local offset = (start_y - 1) * stride + (x - 1) * 4

	for _ = start_y, end_y do
		buffer.writeu32(pixels, offset, color32)

		offset += stride
	end

	self:_MarkDirtyRect(x, start_y, x, end_y)
end

return line
