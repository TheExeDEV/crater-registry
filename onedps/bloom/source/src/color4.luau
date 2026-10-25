--[[
	██████╗ ██╗      ██████╗  ██████╗ ███╗   ███╗
	██╔══██╗██║     ██╔═══██╗██╔═══██╗████╗ ████║
	██████╔╝██║     ██║   ██║██║   ██║██╔████╔██║
	██╔══██╗██║     ██║   ██║██║   ██║██║╚██╔╝██║
	██████╔╝███████╗╚██████╔╝╚██████╔╝██║ ╚═╝ ██║
	╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝     ╚═╝

	Low-level graphics library for EditableImage
]]

--!strict
--!native
--!optimize 2

--[=[
	@class Color4

	RGBA color helpers. Bloom stores pixels as packed 32-bit integers in the same byte
	order that `EditableImage:ReadPixelsBuffer()` and `WritePixelsBuffer()` use:
	red in the lowest byte, alpha in the highest (`0xAABBGGRR`).
]=]
local Color4 = {}
Color4.__index = Color4

export type Color4 = {
	R: number,
	G: number,
	B: number,
	A: number,

	To32Bit: (self: Color4) -> number,
	Lerp: (self: Color4, other: Color4, t: number) -> Color4,
}

local function to_byte(value: number): number
	return math.clamp(math.floor(value + 0.5), 0, 255)
end

local function pack(r: number, g: number, b: number, a: number): number
	return bit32.bor(
		bit32.band(r, 0xFF),
		bit32.lshift(bit32.band(g, 0xFF), 8),
		bit32.lshift(bit32.band(b, 0xFF), 16),
		bit32.lshift(bit32.band(a, 0xFF), 24)
	)
end

local function mix_channel(
	source: number,
	destination: number,
	shift: number,
	source_alpha: number,
	destination_weight: number,
	out_alpha: number
): number
	local source_channel = bit32.extract(source, shift, 8)
	local destination_channel = bit32.extract(destination, shift, 8)

	return math.floor((source_channel * source_alpha + destination_channel * destination_weight) / out_alpha + 0.5)
end

--[=[
	Creates a `Color4` object. Channels are rounded and clamped to 0..255.

	@within Color4
	@param R number -- Red.
	@param G number -- Green.
	@param B number -- Blue.
	@param A number? -- Alpha. Defaults to 255 (opaque).
	@return Color4
]=]
Color4.New = function(R: number, G: number, B: number, A: number?): Color4
	local self = setmetatable({
		R = to_byte(R),
		G = to_byte(G),
		B = to_byte(B),
		A = to_byte(A or 255),
	}, Color4)

	return (self :: any) :: Color4
end

--[=[
	Packs RGBA channels into a 32-bit color.

	@within Color4
	@param R number -- Red, 0..255.
	@param G number -- Green, 0..255.
	@param B number -- Blue, 0..255.
	@param A number? -- Alpha, 0..255. Defaults to 255 (opaque).
	@return number -- Packed RGBA color.
]=]
Color4.New32Bit = function(R: number, G: number, B: number, A: number?): number
	return pack(R, G, B, A or 255)
end

--[=[
	Unpacks a 32-bit color into its channels.

	@within Color4
	@param color number -- Packed RGBA color.
	@return (number, number, number, number) -- Red, green, blue, alpha.
]=]
Color4.Unpack = function(color: number): (number, number, number, number)
	return bit32.extract(color, 0, 8),
		bit32.extract(color, 8, 8),
		bit32.extract(color, 16, 8),
		bit32.extract(color, 24, 8)
end

--[=[
	Replaces the red channel of a packed color.

	@within Color4
	@param color number -- Packed RGBA color.
	@param value number -- New red value, 0..255.
	@return number
]=]
Color4.SetR = function(color: number, value: number): number
	return bit32.replace(color, value, 0, 8)
end

--[=[
	Replaces the green channel of a packed color.

	@within Color4
	@param color number -- Packed RGBA color.
	@param value number -- New green value, 0..255.
	@return number
]=]
Color4.SetG = function(color: number, value: number): number
	return bit32.replace(color, value, 8, 8)
end

--[=[
	Replaces the blue channel of a packed color.

	@within Color4
	@param color number -- Packed RGBA color.
	@param value number -- New blue value, 0..255.
	@return number
]=]
Color4.SetB = function(color: number, value: number): number
	return bit32.replace(color, value, 16, 8)
end

--[=[
	Replaces the alpha channel of a packed color.

	@within Color4
	@param color number -- Packed RGBA color.
	@param value number -- New alpha value, 0..255.
	@return number
]=]
Color4.SetA = function(color: number, value: number): number
	return bit32.replace(color, value, 24, 8)
end

--[=[
	Composites `source` over `destination` (straight, non-premultiplied alpha).

	@within Color4
	@param destination number -- Packed RGBA color already in the framebuffer.
	@param source number -- Packed RGBA color being drawn.
	@return number -- Packed RGBA result.
]=]
Color4.BlendOver = function(destination: number, source: number): number
	local source_alpha = bit32.extract(source, 24, 8)

	if source_alpha == 255 then
		return source
	elseif source_alpha == 0 then
		return destination
	end

	local destination_alpha = bit32.extract(destination, 24, 8)
	local destination_weight = destination_alpha * (255 - source_alpha) / 255
	local out_alpha = source_alpha + destination_weight

	if out_alpha <= 0 then
		return 0
	end

	local r = mix_channel(source, destination, 0, source_alpha, destination_weight, out_alpha)
	local g = mix_channel(source, destination, 8, source_alpha, destination_weight, out_alpha)
	local b = mix_channel(source, destination, 16, source_alpha, destination_weight, out_alpha)

	return pack(r, g, b, math.floor(out_alpha + 0.5))
end

--[=[
	Converts a `Color4` object to a packed 32-bit color.

	@within Color4
	@return number -- Packed RGBA color.
]=]
Color4.To32Bit = function(self: Color4): number
	return pack(self.R, self.G, self.B, self.A)
end

--[=[
	Converts a packed 32-bit color to a `Color4` object.

	@within Color4
	@param color number -- Packed RGBA color.
	@return Color4
]=]
Color4.From32Bit = function(color: number): Color4
	return Color4.New(Color4.Unpack(color))
end

--[=[
	Creates a `Color4` object from a `Color3` (channels 0..1).

	@within Color4
	@param color Color3
	@param alpha number? -- Alpha, 0..255. Defaults to 255 (opaque).
	@return Color4
]=]
Color4.FromColor3 = function(color: Color3, alpha: number?): Color4
	return Color4.New(color.R * 255, color.G * 255, color.B * 255, alpha)
end

--[=[
	Linearly interpolates between two colors.

	@within Color4
	@param other Color4 -- Target color.
	@param t number -- Interpolation factor, clamped to 0..1.
	@return Color4
]=]
Color4.Lerp = function(self: Color4, other: Color4, t: number): Color4
	t = math.clamp(t, 0, 1)

	return Color4.New(
		self.R + (other.R - self.R) * t,
		self.G + (other.G - self.G) * t,
		self.B + (other.B - self.B) * t,
		self.A + (other.A - self.A) * t
	)
end

--[=[
	@prop Zero number
	@within Color4
	Packed fully transparent black (`0`).
]=]
Color4.Zero = 0

return Color4
