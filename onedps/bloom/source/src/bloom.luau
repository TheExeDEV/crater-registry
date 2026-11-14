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

export type Bloom = Types.Bloom
export type Options = Types.Options
export type Stats = Types.Stats
export type TextureDrawOptions = Types.TextureDrawOptions
export type FontOptions = Types.FontOptions
export type SchedulerOptions = Types.SchedulerOptions
export type SubmitOptions = Types.SubmitOptions
export type UniformMap = Types.UniformMap
export type SupportReport = Types.SupportReport
export type Task = Types.Task
export type Viewport = Types.Viewport

local Color4Module = require("./color4")
local Core = require("./core")
local Upload = require("./upload")
local Pixel = require("./elements/pixel")
local Line = require("./elements/line")
local Rect = require("./elements/rect")
local Triangle = require("./elements/triangle")
local Circle = require("./elements/circle")
local TextureModule = require("./texture")
local FontModule = require("./font")
local ShaderModule = require("./shader")
local Each = require("./each")
local AsyncModule = require("./async")
local SupportModule = require("./support")

local floor = math.floor
local band = bit32.band
local lshift = bit32.lshift
local bor = bit32.bor

local new32bit = function(red: number, green: number, blue: number, alpha: number?): number
	local a = alpha or 255

	return bor(
		band(floor(red), 0xFF),
		lshift(band(floor(green), 0xFF), 8),
		lshift(band(floor(blue), 0xFF), 16),
		lshift(band(floor(a), 0xFF), 24)
	)
end

local blend_over = function(destination: number, source: number): number
	return Color4Module.blend_over(source, destination)
end

local Color4 = {
	New = Color4Module.new,
	New32Bit = new32bit,
	Unpack = Color4Module.unpack,
	SetR = Color4Module.set_r,
	SetG = Color4Module.set_g,
	SetB = Color4Module.set_b,
	SetA = Color4Module.set_a,
	BlendOver = blend_over,
	From32Bit = Color4Module.new32bit,
	FromColor3 = Color4Module.from_color3,
	To32Bit = Color4Module.pack,
	Lerp = Color4Module.lerp,
	Zero = Color4Module.Zero,
}

local Texture = {
	New = TextureModule.new,
	FromEditableImage = TextureModule.from_editable,
	FromContent = TextureModule.from_content,
	GetPixel = TextureModule.get_pixel,
	Destroy = TextureModule.destroy,
	Draw = TextureModule.blit,
}

local Shader = {
	New = ShaderModule.new,
	Invert = ShaderModule.invert,
	Grayscale = ShaderModule.grayscale,
	Brightness = ShaderModule.brightness,
	Apply = ShaderModule.apply,
}

local Font = {
	New = FontModule.new,
	FromString = FontModule.from_string,
	FromBuffer = FontModule.from_buffer,
	DrawText = FontModule.draw_text,
	MeasureText = FontModule.measure_text,
	Destroy = FontModule.destroy,
}

local Async = {
	New = AsyncModule.new,
	Yield = AsyncModule.yield,
	Submit = AsyncModule.submit,
	SubmitWithOptions = AsyncModule.submit_with_options,
	Step = AsyncModule.step,
	Start = AsyncModule.start,
	Stop = AsyncModule.stop,
	Clear = AsyncModule.clear,
	PendingCount = AsyncModule.pending_count,
	GetStats = AsyncModule.get_stats,
	Destroy = AsyncModule.destroy,
}

local Support = {
	Check = SupportModule.check,
	IsSupported = SupportModule.is_supported,
	Assert = SupportModule.assert_supported,
}

local methods: { [string]: any } = {}

methods.BeginFrame = function(self: any, color: number?): ()
	if color ~= nil then
		Core.clear(self, color)
	end

	self.pipeline:Run(self, "beginFrame")
end

methods.EndFrame = function(self: any, use_async: boolean?): ()
	self.pipeline:Run(self, "endFrame")

	if use_async then
		Upload.update_async(self)
	else
		Upload.update(self)
	end
end

methods.Clear = Core.clear
methods.SetViewport = Core.set_viewport
methods.ResetViewport = Core.reset_viewport
methods.SetClearColor = function(self: any, color: number): ()
	self.state.clear_color = color
end
methods.Resize = Core.resize
methods.GetState = Core.get_state
methods.GetBuffer = Core.get_buffer
methods.MarkDirty = Core.mark_dirty
methods.EachPixel = Each.each_pixel
methods.Update = Upload.update
methods.UpdateAsync = Upload.update_async
methods.DrawPixel = Pixel.draw
methods.DrawPixelUnsafe = Pixel.draw_unsafe
methods.ReadPixel = Pixel.read
methods.ReadPixelUnsafe = Pixel.read_unsafe
methods.DrawLine = Line.draw
methods.DrawLineAA = Line.draw_aa
methods.DrawHorizontalLine = Line.horizontal
methods.DrawVerticalLine = Line.vertical
methods.DrawRectangle = Rect.draw
methods.DrawTriangle = Triangle.draw
methods.DrawPolygon = Triangle.polygon
methods.DrawCircle = Circle.draw
methods.DrawCircleAA = Circle.draw_aa
methods.DrawTexture = TextureModule.blit
methods.DrawText = FontModule.draw_text
methods.ApplyShader = ShaderModule.apply
methods.RegisterStage = function(self: any, name: string, callback: any, order: number?): ()
	self.pipeline:Register(name, callback, order)
end
methods.RemoveStage = function(self: any, name: string): boolean
	return self.pipeline:Remove(name)
end
methods.Submit = function(self: any, callback: any, ...: any): any
	return self.async:Submit(callback, ...)
end
methods.SubmitWithOptions = function(self: any, callback: any, options: any, ...: any): any
	return self.async:SubmitWithOptions(callback, options, ...)
end
methods.GetStats = Core.get_stats
methods.ResetStats = Core.reset_stats
methods.Destroy = Core.destroy

local methods_meta: any = { __index = methods }

local attach = function(context: any): any
	setmetatable(context, methods_meta)
	return context
end

local bloom = {
	Create = function(resolution: any, parent: any?, reference: any?, options: any?): any
		return attach(Core.create(resolution, parent, reference, options))
	end,
	FromEditableImage = function(editable: any, holder: any): any
		local context = Core.from_editable(editable)
		context.parent = holder.Parent
		context.reference = holder
		context.tiles[0].image = holder

		return attach(context)
	end,
	CheckSupport = SupportModule.check,
	IsSupported = SupportModule.is_supported,
	Texture = Texture,
	Shader = Shader,
	Font = Font,
	Async = Async,
	Support = Support,
	GetColor4 = function(): any
		return Color4
	end,
	CreateShader = ShaderModule.new,
}

return bloom
