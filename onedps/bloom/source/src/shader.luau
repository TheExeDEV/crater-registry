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

type Context = Types.self
export type Shader = Types.ShaderLike
export type Callback = Types.ShaderCallback
export type UniformMap = Types.Uniforms

local LUMA_R, LUMA_G, LUMA_B = 0.2126, 0.7152, 0.0722
local ALPHA_MASK = 0xFF000000
local RGB_MASK = 0x00FFFFFF

--[=[
	@class Shader

	Pixel shader. The callback runs once per pixel and returns a packed RGBA color,
	or `nil` to keep the input pixel. This is not a GPU shader: keep callbacks small and
	allocation-free, and apply them to the smallest rectangle possible.
]=]
local shader = {}

local function scale_channel(color32: number, shift: number, multiplier: number): number
	return math.min(255, math.floor(bit32.extract(color32, shift, 8) * multiplier + 0.5))
end

--[=[
	Creates a custom CPU shader.

	@within Shader
	@param name string -- Debug name.
	@param callback ShaderCallback -- `(x, y, u, v, color32, uniforms) -> number?`
	@param uniforms UniformMap? -- Default parameters passed to the callback.
	@return Shader
]=]
shader.New = function(name: string, callback: Callback, uniforms: UniformMap?): Shader
	assert(type(name) == "string" and name ~= "", "Shader.New expects a name")
	assert(type(callback) == "function", "Shader.New expects a callback")

	return {
		name = name,
		callback = callback,
		uniforms = uniforms or {},
		enabled = true,
	}
end

--[=[
	Inverts RGB channels and preserves alpha.

	@within Shader
	@return Shader
]=]
shader.Invert = function(): Shader
	return shader.New("Invert", function(_, _, _, _, color32)
		return bit32.bor(bit32.band(bit32.bnot(color32), RGB_MASK), bit32.band(color32, ALPHA_MASK))
	end)
end

--[=[
	Converts RGB to Rec. 709 luminance and preserves alpha.

	@within Shader
	@return Shader
]=]
shader.Grayscale = function(): Shader
	return shader.New("Grayscale", function(_, _, _, _, color32)
		local r, g, b = bit32.extract(color32, 0, 8), bit32.extract(color32, 8, 8), bit32.extract(color32, 16, 8)
		local luma = math.floor(r * LUMA_R + g * LUMA_G + b * LUMA_B + 0.5)

		return bit32.bor(luma, bit32.lshift(luma, 8), bit32.lshift(luma, 16), bit32.band(color32, ALPHA_MASK))
	end)
end

--[=[
	Multiplies RGB by `uniforms.amount` and preserves alpha.

	@within Shader
	@param amount number? -- Initial multiplier. Defaults to 1.
	@return Shader
]=]
shader.Brightness = function(amount: number?): Shader
	local uniforms: UniformMap = { amount = amount or 1 }

	return shader.New("Brightness", function(_, _, _, _, color32, parameters)
		local value = parameters.amount
		local multiplier = if type(value) == "number" then math.max(value, 0) else 1

		return bit32.bor(
			scale_channel(color32, 0, multiplier),
			bit32.lshift(scale_channel(color32, 8, multiplier), 8),
			bit32.lshift(scale_channel(color32, 16, multiplier), 16),
			bit32.band(color32, ALPHA_MASK)
		)
	end, uniforms)
end

--[=[
	Applies a shader to an inclusive rectangle, clipped to the viewport and framebuffer.
	`u` and `v` passed to the callback run from 0 to 1 across the clipped rectangle.

	@within Shader
	@param context Bloom
	@param instance Shader
	@param x0 number
	@param y0 number
	@param x1 number
	@param y1 number
	@param uniforms UniformMap? -- Overrides the shader's uniforms for this call.
	@return number -- Number of pixels processed.
]=]
shader.Apply = function(
	context: Context,
	instance: Shader,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	uniforms: UniformMap?
): number
	if context._destroyed or not instance.enabled then
		return 0
	end

	local callback = instance.callback
	local parameters = uniforms or instance.uniforms
	local pixels = context.pixel_buffer
	local viewport = context.state.viewport

	local left = math.max(1, viewport.x, math.floor(math.min(x0, x1)))
	local top = math.max(1, viewport.y, math.floor(math.min(y0, y1)))
	local right = math.min(context.res_x, viewport.x + viewport.w - 1, math.floor(math.max(x0, x1)))
	local bottom = math.min(context.res_y, viewport.y + viewport.h - 1, math.floor(math.max(y0, y1)))

	if left > right or top > bottom then
		return 0
	end

	context.pipeline:Run(context, "beforeShader")

	local width, height = right - left + 1, bottom - top + 1
	local u_scale = if width > 1 then 1 / (width - 1) else 0
	local v_scale = if height > 1 then 1 / (height - 1) else 0
	local processed = width * height

	context:_MarkDirtyRect(left, top, right, bottom)

	for y = top, bottom do
		local v = (y - top) * v_scale
		local offset = (y - 1) * (context.res_x * 4) + (left - 1) * 4

		for x = left, right do
			local result = callback(x, y, (x - left) * u_scale, v, buffer.readu32(pixels, offset), parameters)

			if result ~= nil then
				buffer.writeu32(pixels, offset, result)
			end

			offset += 4
		end
	end

	context.stats.shader_pixels += processed
	context.pipeline:Run(context, "afterShader")

	return processed
end

return shader
