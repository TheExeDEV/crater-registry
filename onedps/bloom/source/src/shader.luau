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

local Clip = require("./clip")
local Damage = require("./damage")
local Types = require("./types")

type Context = Types.Context
type UniformMap = Types.UniformMap
type Callback = Types.ShaderCallback

type Kind = "invert" | "grayscale" | "brightness" | "custom"

type Shader = {
	name: string,
	callback: Callback,
	uniforms: UniformMap,
	enabled: boolean,
	kind: Kind,
}

local LUMA_R = 0.2126
local LUMA_G = 0.7152
local LUMA_B = 0.0722

local shader = {}

local new = function(name: string, callback: Callback, uniforms: UniformMap?): Shader
	assert(type(name) == "string" and name ~= "", "Shader.New expects a name")
	assert(type(callback) == "function", "Shader.New expects a callback")

	return {
		name = name,
		callback = callback,
		uniforms = uniforms or {},
		enabled = true,
		kind = "custom",
	}
end

local clip_rect = function(context: Context, x0: number, y0: number, x1: number, y1: number): (number, number, number, number)
	local left = math.floor(math.min(x0, x1))
	local top = math.floor(math.min(y0, y1))
	local right = math.floor(math.max(x0, x1))
	local bottom = math.floor(math.max(y0, y1))

	local view_left, view_top, view_right, view_bottom = Clip.viewport(context)
	left = math.max(left, view_left)
	top = math.max(top, view_top)
	right = math.min(right, view_right)
	bottom = math.min(bottom, view_bottom)

	return left, top, right, bottom
end

local multiplier_of = function(parameters: UniformMap): number
	local value = parameters.amount

	if type(value) == "number" then
		return math.max(value, 0)
	end

	return 1
end

local brightness_lut = function(multiplier: number): { number }
	local lut = table.create(256)

	for channel = 0, 255 do
		local scaled = (channel * multiplier + 0.5) // 1
		lut[channel] = if scaled > 255 then 255 else scaled
	end

	return lut
end

shader.new = new

shader.invert = function(): Shader
	local instance = new("Invert", function(_, _, _, _, color32)
		return bit32.bxor(color32, 0x00FFFFFF)
	end)
	instance.kind = "invert"

	return instance
end

shader.grayscale = function(): Shader
	local instance = new("Grayscale", function(_, _, _, _, color32)
		local r = bit32.extract(color32, 0, 8)
		local g = bit32.extract(color32, 8, 8)
		local b = bit32.extract(color32, 16, 8)
		local luma = (r * LUMA_R + g * LUMA_G + b * LUMA_B + 0.5) // 1

		return luma * 65793 + bit32.band(color32, 0xFF000000)
	end)
	instance.kind = "grayscale"

	return instance
end

shader.brightness = function(amount: number?): Shader
	local instance = new("Brightness", function(_, _, _, _, color32, parameters)
		local multiplier = multiplier_of(parameters)
		local lut = brightness_lut(multiplier)
		local alpha = bit32.band(color32, 0xFF000000)

		return lut[bit32.extract(color32, 0, 8)]
			+ lut[bit32.extract(color32, 8, 8)] * 256
			+ lut[bit32.extract(color32, 16, 8)] * 65536
			+ alpha
	end, {
		amount = amount or 1,
	} :: UniformMap)
	instance.kind = "brightness"

	return instance
end

shader.apply = function(
	context: Context,
	instance: Types.Shader,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	uniforms: UniformMap?
): number
	if context._destroyed or not instance.enabled then
		return 0
	end

	local left, top, right, bottom = clip_rect(context, x0, y0, x1, y1)

	if left > right or top > bottom then
		return 0
	end

	local pipeline = context.pipeline
	pipeline:Run(context, "beforeShader")

	local pixels = context.pixel_buffer
	local stride = context.res_x * 4
	local start_offset = (left - 1) * 4
	local width = right - left + 1
	local height = bottom - top + 1
	local kind = (instance :: any).kind

	if kind == "invert" then
		Damage.mark_rect(context, left, top, right, bottom)

		for y = top, bottom do
			local offset = (y - 1) * stride + start_offset

			for _ = left, right do
				buffer.writeu32(pixels, offset, bit32.bxor(buffer.readu32(pixels, offset), 0x00FFFFFF))
				offset += 4
			end
		end
	elseif kind == "grayscale" then
		Damage.mark_rect(context, left, top, right, bottom)

		for y = top, bottom do
			local offset = (y - 1) * stride + start_offset

			for _ = left, right do
				local color32 = buffer.readu32(pixels, offset)
				local r = bit32.extract(color32, 0, 8)
				local g = bit32.extract(color32, 8, 8)
				local b = bit32.extract(color32, 16, 8)
				local luma = (r * LUMA_R + g * LUMA_G + b * LUMA_B + 0.5) // 1

				buffer.writeu32(pixels, offset, luma * 65793 + bit32.band(color32, 0xFF000000))
				offset += 4
			end
		end
	elseif kind == "brightness" then
		local lut = brightness_lut(multiplier_of(uniforms or instance.uniforms))
		Damage.mark_rect(context, left, top, right, bottom)

		for y = top, bottom do
			local offset = (y - 1) * stride + start_offset

			for _ = left, right do
				local color32 = buffer.readu32(pixels, offset)
				local alpha = bit32.band(color32, 0xFF000000)

				buffer.writeu32(
					pixels,
					offset,
					lut[bit32.extract(color32, 0, 8)]
						+ lut[bit32.extract(color32, 8, 8)] * 256
						+ lut[bit32.extract(color32, 16, 8)] * 65536
						+ alpha
				)
				offset += 4
			end
		end
	else
		local callback = instance.callback
		local parameters = uniforms or instance.uniforms
		local u_span = width - 1
		local v_span = height - 1
		local u_scale = if u_span > 0 then 1 / u_span else 0
		local v_scale = if v_span > 0 then 1 / v_span else 0

		for y = top, bottom do
			Damage.mark_rect(context, left, y, right, y)

			local v = (y - top) * v_scale
			local offset = (y - 1) * stride + start_offset

			for x = left, right do
				local u = (x - left) * u_scale
				local result = callback(x, y, u, v, buffer.readu32(pixels, offset), parameters)

				if result ~= nil then
					buffer.writeu32(pixels, offset, result)
				end

				offset += 4
			end
		end
	end

	local processed = width * height
	context.stats.shader_pixels += processed
	pipeline:Run(context, "afterShader")

	return processed
end

return shader
