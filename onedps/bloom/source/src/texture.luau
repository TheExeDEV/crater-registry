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
local clip = require("./clip")
local damage = require("./damage")
local platform = require("./platform")

type Context = Types.Context
export type Texture = Types.Texture
export type DrawOptions = Types.TextureDrawOptions

local BYTES_PER_PIXEL = 4
local OPAQUE_WHITE = 0xFFFFFFFF
local OPAQUE_FLOOR = 0xFF000000
local NO_OPTIONS: DrawOptions = table.freeze({})
local GLYPH_OPTIONS: DrawOptions = { tint = OPAQUE_WHITE, blend = true }

local floor = math.floor
local min = math.min
local max = math.max
local clamp = math.clamp
local extract = bit32.extract
local lshift = bit32.lshift
local bor = bit32.bor

local texture = {}

local get_pixel = function(self: Texture, x: number, y: number): number
	x, y = floor(x), floor(y)

	if self.destroyed or x < 1 or y < 1 or x > self.width or y > self.height then
		return 0
	end

	return buffer.readu32(self.pixels, ((y - 1) * self.width + x - 1) * BYTES_PER_PIXEL)
end

local destroy = function(self: Texture): ()
	self.destroyed = true
	self.pixels = buffer.create(0)
end

texture.new = function(width: number, height: number, pixels: buffer, copy_pixels: boolean?): Texture
	width, height = floor(width), floor(height)

	assert(width > 0 and height > 0, "Texture.New expects positive dimensions")

	local byte_count = width * height * BYTES_PER_PIXEL
	assert(buffer.len(pixels) == byte_count, "Texture.New expects width * height * 4 RGBA bytes")

	local owned_pixels = pixels
	local opaque = true

	if copy_pixels == false then
		for offset = 0, byte_count - 1, BYTES_PER_PIXEL do
			if buffer.readu32(pixels, offset) < OPAQUE_FLOOR then
				opaque = false
				break
			end
		end
	else
		owned_pixels = buffer.create(byte_count)

		for offset = 0, byte_count - 1, BYTES_PER_PIXEL do
			local color = buffer.readu32(pixels, offset)
			buffer.writeu32(owned_pixels, offset, color)

			if color < OPAQUE_FLOOR then
				opaque = false
			end
		end
	end

	return {
		width = width,
		height = height,
		pixels = owned_pixels,
		destroyed = false,
		opaque = opaque,
		GetPixel = get_pixel,
		Destroy = destroy,
	}
end

texture.get_pixel = get_pixel
texture.destroy = destroy

texture.from_editable = function(editable: any): Texture
	local size = editable.Size
	local width, height = floor(size.X), floor(size.Y)
	local pixels = editable:ReadPixelsBuffer(platform.vector2(0, 0), platform.vector2(width, height))

	assert(pixels ~= nil, "Texture.FromEditableImage: EditableImage pixels could not be read")

	return texture.new(width, height, pixels :: buffer, false)
end

texture.from_content = function(content: any): Texture
	local editable: any = platform.service("AssetService"):CreateEditableImageAsync(content)
	assert(editable ~= nil, "Texture.FromContent: EditableImage memory budget is exhausted")

	local ok, result = pcall(texture.from_editable, editable)
	editable:Destroy()

	if not ok then
		error(result, 2)
	end

	return result :: Texture
end

local draw_region = function(
	context: Context,
	source: Texture,
	x: number,
	y: number,
	width: number,
	height: number,
	options: DrawOptions?,
	mark_damage: boolean
): (number, number, number, number)
	assert(not source.destroyed, "Cannot draw a destroyed Texture")

	if context._destroyed then
		return 0, 0, -1, -1
	end

	local destination = context.pixel_buffer
	local source_pixels = source.pixels
	local source_stride = source.width * BYTES_PER_PIXEL
	local destination_stride = context.res_x * BYTES_PER_PIXEL
	local settings = options or NO_OPTIONS

	x, y = floor(x), floor(y)
	width, height = floor(width), floor(height)

	if width <= 0 or height <= 0 then
		return 0, 0, -1, -1
	end

	local source_x = clamp(floor(settings.source_x or 1), 1, source.width)
	local source_y = clamp(floor(settings.source_y or 1), 1, source.height)
	local source_w = clamp(floor(settings.source_width or source.width), 1, source.width - source_x + 1)
	local source_h = clamp(floor(settings.source_height or source.height), 1, source.height - source_y + 1)

	local viewport_x0, viewport_y0, viewport_x1, viewport_y1 = clip.viewport(context)
	local left = max(viewport_x0, x)
	local top = max(viewport_y0, y)
	local right = min(viewport_x1, x + width - 1)
	local bottom = min(viewport_y1, y + height - 1)

	if left > right or top > bottom then
		return 0, 0, -1, -1
	end

	local tint = settings.tint or OPAQUE_WHITE
	local opacity = clamp(settings.opacity or 1, 0, 1)
	local blend = settings.blend ~= false
	local white_tint = tint == OPAQUE_WHITE
	local needs_modulate = not white_tint or opacity < 1
	local inverse_255 = 1 / 255
	local red_scale = extract(tint, 0, 8) * inverse_255
	local green_scale = extract(tint, 8, 8) * inverse_255
	local blue_scale = extract(tint, 16, 8) * inverse_255
	local alpha_scale = extract(tint, 24, 8) * inverse_255 * opacity

	local x_scale, y_scale = source_w / width, source_h / height
	local last_source_x, last_source_y = source_x + source_w - 1, source_y + source_h - 1

	if x_scale == 1 and y_scale == 1 then
		local byte_width = (right - left + 1) * BYTES_PER_PIXEL
		local first_source_x = source_x + (left - x)
		local first_source_y = source_y + (top - y)
		local source_offset = (first_source_y - 1) * source_stride + (first_source_x - 1) * BYTES_PER_PIXEL
		local offset = (top - 1) * destination_stride + (left - 1) * BYTES_PER_PIXEL

		if not needs_modulate and (source.opaque or not blend) then
			if byte_width == source_stride and byte_width == destination_stride and first_source_x == 1 and left == 1 then
				buffer.copy(destination, offset, source_pixels, source_offset, byte_width * (bottom - top + 1))
			else
				for _ = top, bottom do
					buffer.copy(destination, offset, source_pixels, source_offset, byte_width)
					source_offset += source_stride
					offset += destination_stride
				end
			end
		elseif not needs_modulate then
			for _ = top, bottom do
				local source_cursor, destination_cursor = source_offset, offset

				for _ = left, right do
					local color = buffer.readu32(source_pixels, source_cursor)
					local alpha = extract(color, 24, 8)

					if alpha == 255 then
						buffer.writeu32(destination, destination_cursor, color)
					elseif alpha ~= 0 then
						local destination_color = buffer.readu32(destination, destination_cursor)
						local destination_alpha = extract(destination_color, 24, 8)

						if destination_alpha == 0 then
							buffer.writeu32(destination, destination_cursor, color)
						else
							local destination_weight = destination_alpha * (255 - alpha) / 255
							local out_alpha = alpha + destination_weight
							local out_scale = 1 / out_alpha
							local r = floor((extract(color, 0, 8) * alpha + extract(destination_color, 0, 8) * destination_weight) * out_scale + 0.5)
							local g = floor((extract(color, 8, 8) * alpha + extract(destination_color, 8, 8) * destination_weight) * out_scale + 0.5)
							local b = floor((extract(color, 16, 8) * alpha + extract(destination_color, 16, 8) * destination_weight) * out_scale + 0.5)

							buffer.writeu32(
								destination,
								destination_cursor,
								bor(r, lshift(g, 8), lshift(b, 16), lshift(floor(out_alpha + 0.5), 24))
							)
						end
					end

					source_cursor += BYTES_PER_PIXEL
					destination_cursor += BYTES_PER_PIXEL
				end

				source_offset += source_stride
				offset += destination_stride
			end
		else
			for _ = top, bottom do
				local source_cursor, destination_cursor = source_offset, offset

				for _ = left, right do
					local color = buffer.readu32(source_pixels, source_cursor)
					local r = floor(extract(color, 0, 8) * red_scale + 0.5)
					local g = floor(extract(color, 8, 8) * green_scale + 0.5)
					local b = floor(extract(color, 16, 8) * blue_scale + 0.5)
					local alpha = floor(extract(color, 24, 8) * alpha_scale + 0.5)

					if not blend then
						buffer.writeu32(destination, destination_cursor, bor(r, lshift(g, 8), lshift(b, 16), lshift(alpha, 24)))
					elseif alpha == 255 then
						buffer.writeu32(destination, destination_cursor, bor(r, lshift(g, 8), lshift(b, 16), lshift(alpha, 24)))
					elseif alpha ~= 0 then
						local destination_color = buffer.readu32(destination, destination_cursor)
						local destination_alpha = extract(destination_color, 24, 8)

						if destination_alpha == 0 then
							buffer.writeu32(destination, destination_cursor, bor(r, lshift(g, 8), lshift(b, 16), lshift(alpha, 24)))
						else
							local destination_weight = destination_alpha * (255 - alpha) / 255
							local out_alpha = alpha + destination_weight
							local out_scale = 1 / out_alpha
							local blended_r = floor((r * alpha + extract(destination_color, 0, 8) * destination_weight) * out_scale + 0.5)
							local blended_g = floor((g * alpha + extract(destination_color, 8, 8) * destination_weight) * out_scale + 0.5)
							local blended_b = floor((b * alpha + extract(destination_color, 16, 8) * destination_weight) * out_scale + 0.5)

							buffer.writeu32(
								destination,
								destination_cursor,
								bor(blended_r, lshift(blended_g, 8), lshift(blended_b, 16), lshift(floor(out_alpha + 0.5), 24))
							)
						end
					end

					source_cursor += BYTES_PER_PIXEL
					destination_cursor += BYTES_PER_PIXEL
				end

				source_offset += source_stride
				offset += destination_stride
			end
		end
	else
		local column_count = right - left + 1
		local columns = context._texture_columns

		if columns == nil then
			columns = {}
			context._texture_columns = columns
			context._texture_columns_capacity = 0
		end

		local capacity = context._texture_columns_capacity or 0

		if capacity < column_count then
			capacity = math.max(column_count, 64, math.floor(capacity * 1.5))
			columns = table.create(capacity)
			context._texture_columns = columns
			context._texture_columns_capacity = capacity
		end

		for px = left, right do
			local sample_x = min(source_x + floor((px - x + 0.5) * x_scale), last_source_x)
			columns[px - left + 1] = (sample_x - 1) * BYTES_PER_PIXEL
		end

		for py = top, bottom do
			local sample_y = min(source_y + floor((py - y + 0.5) * y_scale), last_source_y)
			local source_row = (sample_y - 1) * source_stride
			local offset = (py - 1) * destination_stride + (left - 1) * BYTES_PER_PIXEL

			for column_index = 1, column_count do
				local color = buffer.readu32(source_pixels, source_row + columns[column_index])

				if needs_modulate then
					local r = floor(extract(color, 0, 8) * red_scale + 0.5)
					local g = floor(extract(color, 8, 8) * green_scale + 0.5)
					local b = floor(extract(color, 16, 8) * blue_scale + 0.5)
					local alpha = floor(extract(color, 24, 8) * alpha_scale + 0.5)
					color = bor(r, lshift(g, 8), lshift(b, 16), lshift(alpha, 24))
				end

				if blend then
					local alpha = extract(color, 24, 8)

					if alpha == 255 then
						buffer.writeu32(destination, offset, color)
					elseif alpha ~= 0 then
						local destination_color = buffer.readu32(destination, offset)
						local destination_alpha = extract(destination_color, 24, 8)

						if destination_alpha == 0 then
							buffer.writeu32(destination, offset, color)
						else
							local destination_weight = destination_alpha * (255 - alpha) / 255
							local out_alpha = alpha + destination_weight
							local out_scale = 1 / out_alpha
							local r = floor((extract(color, 0, 8) * alpha + extract(destination_color, 0, 8) * destination_weight) * out_scale + 0.5)
							local g = floor((extract(color, 8, 8) * alpha + extract(destination_color, 8, 8) * destination_weight) * out_scale + 0.5)
							local b = floor((extract(color, 16, 8) * alpha + extract(destination_color, 16, 8) * destination_weight) * out_scale + 0.5)

							buffer.writeu32(
								destination,
								offset,
								bor(r, lshift(g, 8), lshift(b, 16), lshift(floor(out_alpha + 0.5), 24))
							)
						end
					end
				else
					buffer.writeu32(destination, offset, color)
				end

				offset += BYTES_PER_PIXEL
			end
		end
	end

	context.stats.texture_pixels += (right - left + 1) * (bottom - top + 1)

	if mark_damage then
		damage.mark_rect(context, left, top, right, bottom)
	end

	return left, top, right, bottom
end

local draw_glyph = function(
	context: Context,
	source: Texture,
	source_x: number,
	source_y: number,
	source_width: number,
	source_height: number,
	x: number,
	y: number,
	width: number,
	height: number,
	tint: number,
	viewport_x0: number,
	viewport_y0: number,
	viewport_x1: number,
	viewport_y1: number
): (number, number, number, number)
	assert(not source.destroyed, "Cannot draw a destroyed Texture")

	if context._destroyed then
		return 0, 0, -1, -1
	end

	x, y = floor(x), floor(y)
	width, height = floor(width), floor(height)

	if width <= 0 or height <= 0 then
		return 0, 0, -1, -1
	end

	source_x = clamp(floor(source_x), 1, source.width)
	source_y = clamp(floor(source_y), 1, source.height)
	source_width = clamp(floor(source_width), 1, source.width - source_x + 1)
	source_height = clamp(floor(source_height), 1, source.height - source_y + 1)

	if source_width ~= width or source_height ~= height then
		GLYPH_OPTIONS.tint = tint
		GLYPH_OPTIONS.source_x = source_x
		GLYPH_OPTIONS.source_y = source_y
		GLYPH_OPTIONS.source_width = source_width
		GLYPH_OPTIONS.source_height = source_height

		return draw_region(context, source, x, y, width, height, GLYPH_OPTIONS, false)
	end

	local left = max(viewport_x0, x)
	local top = max(viewport_y0, y)
	local right = min(viewport_x1, x + width - 1)
	local bottom = min(viewport_y1, y + height - 1)

	if left > right or top > bottom then
		return 0, 0, -1, -1
	end

	local source_pixels = source.pixels
	local source_stride = source.width * BYTES_PER_PIXEL
	local destination = context.pixel_buffer
	local destination_stride = context.res_x * BYTES_PER_PIXEL
	local byte_width = (right - left + 1) * BYTES_PER_PIXEL
	local first_source_x = source_x + (left - x)
	local first_source_y = source_y + (top - y)
	local source_offset = (first_source_y - 1) * source_stride + (first_source_x - 1) * BYTES_PER_PIXEL
	local offset = (top - 1) * destination_stride + (left - 1) * BYTES_PER_PIXEL
	local white_tint = tint == OPAQUE_WHITE

	if white_tint and source.opaque then
		if byte_width == source_stride and byte_width == destination_stride and first_source_x == 1 and left == 1 then
			buffer.copy(destination, offset, source_pixels, source_offset, byte_width * (bottom - top + 1))
		else
			for _ = top, bottom do
				buffer.copy(destination, offset, source_pixels, source_offset, byte_width)
				source_offset += source_stride
				offset += destination_stride
			end
		end
	elseif white_tint then
		for _ = top, bottom do
			local source_cursor, destination_cursor = source_offset, offset

			for _ = left, right do
				local color = buffer.readu32(source_pixels, source_cursor)
				local alpha = extract(color, 24, 8)

				if alpha == 255 then
					buffer.writeu32(destination, destination_cursor, color)
				elseif alpha ~= 0 then
					local destination_color = buffer.readu32(destination, destination_cursor)
					local destination_alpha = extract(destination_color, 24, 8)

					if destination_alpha == 0 then
						buffer.writeu32(destination, destination_cursor, color)
					else
						local destination_weight = destination_alpha * (255 - alpha) / 255
						local out_alpha = alpha + destination_weight
						local out_scale = 1 / out_alpha
						local r = floor((extract(color, 0, 8) * alpha + extract(destination_color, 0, 8) * destination_weight) * out_scale + 0.5)
						local g = floor((extract(color, 8, 8) * alpha + extract(destination_color, 8, 8) * destination_weight) * out_scale + 0.5)
						local b = floor((extract(color, 16, 8) * alpha + extract(destination_color, 16, 8) * destination_weight) * out_scale + 0.5)

						buffer.writeu32(
							destination,
							destination_cursor,
							bor(r, lshift(g, 8), lshift(b, 16), lshift(floor(out_alpha + 0.5), 24))
						)
					end
				end

				source_cursor += BYTES_PER_PIXEL
				destination_cursor += BYTES_PER_PIXEL
			end

			source_offset += source_stride
			offset += destination_stride
		end
	else
		local inverse_255 = 1 / 255
		local red_scale = extract(tint, 0, 8) * inverse_255
		local green_scale = extract(tint, 8, 8) * inverse_255
		local blue_scale = extract(tint, 16, 8) * inverse_255
		local alpha_scale = extract(tint, 24, 8) * inverse_255

		for _ = top, bottom do
			local source_cursor, destination_cursor = source_offset, offset

			for _ = left, right do
				local color = buffer.readu32(source_pixels, source_cursor)
				local r = floor(extract(color, 0, 8) * red_scale + 0.5)
				local g = floor(extract(color, 8, 8) * green_scale + 0.5)
				local b = floor(extract(color, 16, 8) * blue_scale + 0.5)
				local alpha = floor(extract(color, 24, 8) * alpha_scale + 0.5)

				if alpha == 255 then
					buffer.writeu32(destination, destination_cursor, bor(r, lshift(g, 8), lshift(b, 16), lshift(alpha, 24)))
				elseif alpha ~= 0 then
					local destination_color = buffer.readu32(destination, destination_cursor)
					local destination_alpha = extract(destination_color, 24, 8)

					if destination_alpha == 0 then
						buffer.writeu32(destination, destination_cursor, bor(r, lshift(g, 8), lshift(b, 16), lshift(alpha, 24)))
					else
						local destination_weight = destination_alpha * (255 - alpha) / 255
						local out_alpha = alpha + destination_weight
						local out_scale = 1 / out_alpha
						local blended_r = floor((r * alpha + extract(destination_color, 0, 8) * destination_weight) * out_scale + 0.5)
						local blended_g = floor((g * alpha + extract(destination_color, 8, 8) * destination_weight) * out_scale + 0.5)
						local blended_b = floor((b * alpha + extract(destination_color, 16, 8) * destination_weight) * out_scale + 0.5)

						buffer.writeu32(
							destination,
							destination_cursor,
							bor(blended_r, lshift(blended_g, 8), lshift(blended_b, 16), lshift(floor(out_alpha + 0.5), 24))
						)
					end
				end

				source_cursor += BYTES_PER_PIXEL
				destination_cursor += BYTES_PER_PIXEL
			end

			source_offset += source_stride
			offset += destination_stride
		end
	end

	context.stats.texture_pixels += (right - left + 1) * (bottom - top + 1)

	return left, top, right, bottom
end

texture.blit = function(
	context: Context,
	source: Texture,
	x: number,
	y: number,
	width: number?,
	height: number?,
	options: DrawOptions?
): ()
	draw_region(context, source, x, y, width or source.width, height or source.height, options, true)
end

texture.New = texture.new
texture.FromEditableImage = texture.from_editable
texture.FromContent = texture.from_content
texture.GetPixel = texture.get_pixel
texture.Destroy = texture.destroy
texture.Draw = texture.blit
texture._DrawRegion = draw_region
texture._DrawGlyph = draw_glyph

return texture
