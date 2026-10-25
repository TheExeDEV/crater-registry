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
local line = require("./line")

type Context = Types.self
type Point = { x: number, y: number }

local triangle = {}

local function by_y_then_x(a: Point, b: Point): boolean
	if a.y == b.y then
		return a.x < b.x
	end

	return a.y < b.y
end

local function edge_intersection(a: Point, b: Point, y: number): number?
	if a.y == b.y or y < a.y or y > b.y then
		return nil
	end

	return a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
end

--[=[
	Draws a filled triangle using horizontal scanlines.

	@within Bloom
	@param x0 number -- First vertex X.
	@param y0 number -- First vertex Y.
	@param x1 number -- Second vertex X.
	@param y1 number -- Second vertex Y.
	@param x2 number -- Third vertex X.
	@param y2 number -- Third vertex Y.
	@param color32 number -- Packed RGBA color.
]=]
triangle.DrawTriangle = function(
	self: Context,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	color32: number
): ()
	local points: { Point } = {
		{ x = math.floor(x0), y = math.floor(y0) },
		{ x = math.floor(x1), y = math.floor(y1) },
		{ x = math.floor(x2), y = math.floor(y2) },
	}

	table.sort(points, by_y_then_x)
	local top, middle, bottom = points[1], points[2], points[3]

	if top.y == bottom.y then
		line.DrawHorizontalLine(self, top.x, top.y, bottom.x, color32)
		return
	end

	local viewport = self.state.viewport
	local first_row = math.max(top.y, viewport.y, 1)
	local last_row = math.min(bottom.y, viewport.y + viewport.h - 1, self.res_y)
	local edges = { { top, middle }, { middle, bottom }, { top, bottom } }

	for y = first_row, last_row do
		local min_x, max_x = math.huge, -math.huge

		for _, edge in edges do
			local x = edge_intersection(edge[1], edge[2], y)

			if x ~= nil then
				min_x, max_x = math.min(min_x, x), math.max(max_x, x)
			end
		end

		if min_x <= max_x then
			line.DrawHorizontalLine(self, math.floor(min_x + 0.5), y, math.floor(max_x + 0.5), color32)
		end
	end
end

return triangle
