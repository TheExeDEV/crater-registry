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

export type Color4 = {
	R: number,
	G: number,
	B: number,
	A: number,
	To32Bit: (self: Color4) -> number,
	Lerp: (self: Color4, other: Color4, t: number) -> Color4,
}

local floor = math.floor
local clamp = math.clamp
local extract = bit32.extract
local replace = bit32.replace

local to_byte = function(value: number): number
	local result = (value + 0.5) // 1

	if result < 0 then
		return 0
	elseif result > 255 then
		return 255
	end

	return result
end

local pack = function(r: number, g: number, b: number, a: number): number
	return to_byte(r) + to_byte(g) * 256 + to_byte(b) * 65536 + to_byte(a) * 16777216
end

local unpack_color = function(color: number): (number, number, number, number)
	return extract(color, 0, 8), extract(color, 8, 8), extract(color, 16, 8), extract(color, 24, 8)
end

local Color4Class = {}

local new = function(r: number, g: number, b: number, a: number?): Color4
	local self = setmetatable({
		R = to_byte(r),
		G = to_byte(g),
		B = to_byte(b),
		A = to_byte(a or 255),
	}, Color4Class)

	return self :: any
end

local to32bit = function(self: Color4): number
	return pack(self.R, self.G, self.B, self.A)
end

local lerp = function(self: Color4, other: Color4, t: number): Color4
	t = clamp(t, 0, 1)

	return new(
		self.R + (other.R - self.R) * t,
		self.G + (other.G - self.G) * t,
		self.B + (other.B - self.B) * t,
		self.A + (other.A - self.A) * t
	)
end

Color4Class.__index = {
	To32Bit = to32bit,
	Lerp = lerp,
}

local new32bit = function(color: number): Color4
	return new(unpack_color(color))
end

local set_r = function(color: number, value: number): number
	return replace(color, value, 0, 8)
end

local set_g = function(color: number, value: number): number
	return replace(color, value, 8, 8)
end

local set_b = function(color: number, value: number): number
	return replace(color, value, 16, 8)
end

local set_a = function(color: number, value: number): number
	return replace(color, value, 24, 8)
end

local blend_over = function(source: number, destination: number): number
	local source_alpha = extract(source, 24, 8)

	if source_alpha == 255 then
		return source
	elseif source_alpha == 0 then
		return destination
	end

	local destination_alpha = extract(destination, 24, 8)

	if destination_alpha == 0 then
		return source
	end

	local destination_weight = destination_alpha * (255 - source_alpha) / 255
	local out_alpha = source_alpha + destination_weight
	local scale = 1 / out_alpha

	local r = floor((extract(source, 0, 8) * source_alpha + extract(destination, 0, 8) * destination_weight) * scale + 0.5)
	local g = floor((extract(source, 8, 8) * source_alpha + extract(destination, 8, 8) * destination_weight) * scale + 0.5)
	local b = floor((extract(source, 16, 8) * source_alpha + extract(destination, 16, 8) * destination_weight) * scale + 0.5)

	return r + g * 256 + b * 65536 + floor(out_alpha + 0.5) * 16777216
end

local from_color3 = function(color3: any, alpha: number?): Color4
	return new(color3.R * 255, color3.G * 255, color3.B * 255, alpha)
end

return {
	Zero = 0,
	pack = pack,
	new = new,
	new32bit = new32bit,
	unpack = unpack_color,
	set_r = set_r,
	set_g = set_g,
	set_b = set_b,
	set_a = set_a,
	blend_over = blend_over,
	from_color3 = from_color3,
	lerp = lerp,
}
