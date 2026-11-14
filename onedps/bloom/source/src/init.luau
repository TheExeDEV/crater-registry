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

local Types = require("@self/types")

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

return require("@self/bloom")
