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
local color4 = require("./color4")

type Context = Types.self
export type DrawOptions = Types.TextureDrawOptions

export type Texture = {
	width: number,
	height: number,
	pixels: buffer,
	destroyed: boolean,
	Destroy: (self: Texture) -> (),
	GetPixel: (self: Texture, x: number, y: number) -> number,
}

local BYTES_PER_PIXEL = 4
local OPAQUE_WHITE = 0xFFFFFFFF
local NO_OPTIONS: DrawOptions = table.freeze({})

local asset_service = game:GetService("AssetService")

--[=[
	@class Texture

	RGBA texture backed by a Luau `buffer`. Pixel coordinates are 1-based.
]=]
local texture = {}
texture.__index = texture

--[=[
	Creates a texture from an RGBA buffer.

	@within Texture
	@param width number -- Texture width in pixels.
	@param height number -- Texture height in pixels.
	@param pixels buffer -- Exactly `width * height * 4` bytes in RGBA order.
	@param copy_pixels boolean? -- Copies by default; `false` adopts `pixels` without copying.
	@return Texture
]=]
texture.New = function(width: number, height: number, pixels: buffer, copy_pixels: boolean?): Texture
	width, height = math.floor(width), math.floor(height)

	assert(width > 0 and height > 0, "Texture.New expects positive dimensions")
	assert(buffer.len(pixels) == width * height * BYTES_PER_PIXEL, "Texture.New expects width * height * 4 RGBA bytes")

	local owned_pixels = pixels

	if copy_pixels ~= false then
		owned_pixels = buffer.create(buffer.len(pixels))
		buffer.copy(owned_pixels, 0, pixels)
	end

	return setmetatable({
		width = width,
		height = height,
		pixels = owned_pixels,
		destroyed = false,
	}, texture) :: any
end

--[=[
	Copies the pixels of an `EditableImage` into a new texture. The image itself is not modified.

	@within Texture
	@param editable_image EditableImage
	@return Texture
]=]
texture.FromEditableImage = function(editable_image: EditableImage): Texture
	local size = editable_image.Size
	local pixels = editable_image:ReadPixelsBuffer(Vector2.zero, size)

	return texture.New(size.X, size.Y, pixels, false)
end

--[=[
	Loads image content into a temporary `EditableImage` (yields) and copies its pixels into a texture.
	The asset must satisfy Roblox's EditableImage permission rules.

	@within Texture
	@param content Content -- For example `Content.fromUri("rbxassetid://...")`.
	@return Texture
]=]
texture.FromContent = function(content: Content): Texture
	local editable_image: EditableImage? = asset_service:CreateEditableImageAsync(content)
	assert(editable_image, "Texture.FromContent: EditableImage memory budget is exhausted")

	local ok, result = pcall(texture.FromEditableImage, editable_image)
	editable_image:Destroy()

	if not ok then
		error(result, 2)
	end

	return result
end

--[=[
	Returns a packed RGBA pixel, or `0` outside the texture.

	@within Texture
	@param x number -- 1-based column.
	@param y number -- 1-based row.
	@return number
]=]
texture.GetPixel = function(self: Texture, x: number, y: number): number
	x, y = math.floor(x), math.floor(y)

	if self.destroyed or x < 1 or y < 1 or x > self.width or y > self.height then
		return 0
	end

	return buffer.readu32(self.pixels, ((y - 1) * self.width + x - 1) * BYTES_PER_PIXEL)
end

--[=[
	Releases the pixel buffer. The texture cannot be drawn afterwards.

	@within Texture
]=]
texture.Destroy = function(self: Texture): ()
	self.destroyed = true
	self.pixels = buffer.create(0)
end

-- Multiplies each channel of `color` by the matching channel of `tint` and alpha by `opacity`.
local function modulate(color: number, tint: number, opacity: number): number
	local r = math.floor(bit32.extract(color, 0, 8) * bit32.extract(tint, 0, 8) / 255 + 0.5)
	local g = math.floor(bit32.extract(color, 8, 8) * bit32.extract(tint, 8, 8) / 255 + 0.5)
	local b = math.floor(bit32.extract(color, 16, 8) * bit32.extract(tint, 16, 8) / 255 + 0.5)
	local a = math.floor(bit32.extract(color, 24, 8) * bit32.extract(tint, 24, 8) / 255 * opacity + 0.5)

	return bit32.bor(r, bit32.lshift(g, 8), bit32.lshift(b, 16), bit32.lshift(a, 24))
end

--[[
	Draws `source` into the destination rectangle (x, y, width, height) with nearest-neighbour
	sampling. Returns the clipped rectangle that was touched, or (0, 0, -1, -1) if nothing was drawn.
	`mark_dirty = false` lets callers such as DrawText batch dirty tracking themselves.
]]
local function draw_region(
	context: Context,
	source: Texture,
	x: number,
	y: number,
	width: number,
	height: number,
	options: DrawOptions?,
	mark_dirty: boolean
): (number, number, number, number)
	assert(not source.destroyed, "Cannot draw a destroyed Texture")
	if context._destroyed then
		return 0, 0, -1, -1
	end

	local source_pixels = source.pixels
	local destination = context.pixel_buffer
	local source_stride = source.width * BYTES_PER_PIXEL
	local destination_stride = context.res_x * BYTES_PER_PIXEL
	local viewport = context.state.viewport

	local settings = options or NO_OPTIONS
	x, y = math.floor(x), math.floor(y)

	width, height = math.floor(width), math.floor(height)
	if width <= 0 or height <= 0 then
		return 0, 0, -1, -1
	end

	local source_x = math.clamp(math.floor(settings.source_x or 1), 1, source.width)
	local source_y = math.clamp(math.floor(settings.source_y or 1), 1, source.height)
	local source_w = math.clamp(math.floor(settings.source_width or source.width), 1, source.width - source_x + 1)
	local source_h = math.clamp(math.floor(settings.source_height or source.height), 1, source.height - source_y + 1)

	local left = math.max(1, viewport.x, x)
	local top = math.max(1, viewport.y, y)
	local right = math.min(context.res_x, viewport.x + viewport.w - 1, x + width - 1)
	local bottom = math.min(context.res_y, viewport.y + viewport.h - 1, y + height - 1)
	if left > right or top > bottom then
		return 0, 0, -1, -1
	end

	local tint = settings.tint or OPAQUE_WHITE
	local opacity = math.clamp(settings.opacity or 1, 0, 1)
	local needs_modulate = tint ~= OPAQUE_WHITE or opacity < 1
	local blend = settings.blend ~= false

	local x_scale, y_scale = source_w / width, source_h / height
	local last_source_x, last_source_y = source_x + source_w - 1, source_y + source_h - 1

	for py = top, bottom do
		local sample_y = math.min(source_y + math.floor((py - y + 0.5) * y_scale), last_source_y)
		local source_row = (sample_y - 1) * source_stride
		local offset = (py - 1) * destination_stride + (left - 1) * BYTES_PER_PIXEL

		for px = left, right do
			local sample_x = math.min(source_x + math.floor((px - x + 0.5) * x_scale), last_source_x)
			local color = buffer.readu32(source_pixels, source_row + (sample_x - 1) * BYTES_PER_PIXEL)

			if needs_modulate then
				color = modulate(color, tint, opacity)
			end

			if blend then
				color = color4.BlendOver(buffer.readu32(destination, offset), color)
			end
			buffer.writeu32(destination, offset, color)

			offset += BYTES_PER_PIXEL
		end
	end

	context.stats.texture_pixels += (right - left + 1) * (bottom - top + 1)

	if mark_dirty then
		context:_MarkDirtyRect(left, top, right, bottom)
	end

	return left, top, right, bottom
end

--[=[
	Draws a texture with nearest-neighbour sampling, optional tint, opacity and alpha blending.

	@within Texture
	@param context Bloom
	@param source Texture
	@param x number -- Destination left, 1-based.
	@param y number -- Destination top, 1-based.
	@param width number? -- Destination width. Defaults to the source width.
	@param height number? -- Destination height. Defaults to the source height.
	@param options DrawOptions? -- `source_x`, `source_y`, `source_width`, `source_height`, `tint`, `opacity`, `blend`.
]=]
texture.Draw = function(
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

texture._DrawRegion = draw_region

return texture
