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

type Context = Types.Context

local clip = {}

clip.viewport = function(context: Context): (number, number, number, number)
	local viewport = context.state.viewport
	local origin_x = math.floor(viewport.x)
	local origin_y = math.floor(viewport.y)
	local width = math.floor(viewport.w)
	local height = math.floor(viewport.h)
	local x0 = math.max(origin_x, 1)
	local y0 = math.max(origin_y, 1)
	local x1 = math.min(origin_x + width - 1, context.res_x)
	local y1 = math.min(origin_y + height - 1, context.res_y)
	return x0, y0, x1, y1
end

return clip
