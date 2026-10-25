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

local Types = require("./types")

export type Callback = Types.StageCallback
export type Phase = Types.PipelinePhase

export type Stage = {
	name: string,
	callback: Callback,
	order: number,
	enabled: boolean,
}

local DEFAULT_ORDER = 100

--[=[
	@class Pipeline

	Ordered, extensible hooks around Bloom's frame, shader and upload operations.
]=]
local pipeline = {}
pipeline.__index = pipeline

export type Pipeline = typeof(setmetatable({} :: { stages: { Stage } }, pipeline))

local function compare_stages(a: Stage, b: Stage): boolean
	if a.order == b.order then
		return a.name < b.name
	end

	return a.order < b.order
end

local function find_stage(self: Pipeline, name: string): (number?, Stage?)
	for index, stage in self.stages do
		if stage.name == name then
			return index, stage
		end
	end

	return nil, nil
end

local function remove_stage(self: Pipeline, name: string): boolean
	local index = find_stage(self, name)

	if index == nil then
		return false
	end

	table.remove(self.stages, index)
	return true
end

local function run_stage(stage: Stage, context: any, phase: Phase): ()
	local ok, err = pcall(stage.callback :: (any, Phase) -> any, context, phase)

	if not ok then
		warn(string.format("[Bloom.Pipeline] Stage '%s' failed during '%s': %s", stage.name, phase, tostring(err)))
	end
end

--[=[
	Creates an empty pipeline.

	@within Pipeline
	@return Pipeline
]=]
pipeline.New = function(): Pipeline
	return setmetatable({ stages = {} }, pipeline)
end

--[=[
	Registers a stage, replacing any stage with the same name. Lower `order` values run first.

	@within Pipeline
	@param name string -- Unique stage name.
	@param callback (context: Bloom, phase: string) -> ()
	@param order number? -- Defaults to 100.
]=]
pipeline.Register = function(self: Pipeline, name: string, callback: Callback, order: number?): ()
	assert(type(name) == "string" and name ~= "", "Pipeline.Register expects a non-empty name")
	assert(type(callback) == "function", "Pipeline.Register expects a callback")

	remove_stage(self, name)
	table.insert(self.stages, {
		name = name,
		callback = callback,
		order = order or DEFAULT_ORDER,
		enabled = true,
	})

	table.sort(self.stages, compare_stages)
end

--[=[
	Removes a stage by name.

	@within Pipeline
	@return boolean -- True when a stage was removed.
]=]
pipeline.Remove = function(self: Pipeline, name: string): boolean
	return remove_stage(self, name)
end

--[=[
	Enables or disables a registered stage.

	@within Pipeline
	@return boolean -- True when the stage exists.
]=]
pipeline.SetEnabled = function(self: Pipeline, name: string, enabled: boolean): boolean
	local _, stage = find_stage(self, name)

	if stage == nil then
		return false
	end

	stage.enabled = enabled
	return true
end

--[=[
	Runs every enabled stage for `phase` in ascending order. A failing stage is reported
	with `warn` and does not stop the remaining stages.

	@within Pipeline
]=]
pipeline.Run = function(self: Pipeline, context: any, phase: Phase): ()
	if #self.stages == 0 then
		return
	end

	for _, stage in table.clone(self.stages) do
		if stage.enabled then
			run_stage(stage, context, phase)
		end
	end
end

return pipeline
