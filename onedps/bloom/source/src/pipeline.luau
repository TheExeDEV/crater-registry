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

local env: any = _G

type Stage = Types.Stage
type Callback = Types.StageCallback

type Pipeline = {
	stages: { Stage },
	snapshot: { Stage },
	version: number,
	snapshot_version: number,
	Register: (self: Pipeline, name: string, callback: Callback, order: number?) -> (),
	Remove: (self: Pipeline, name: string) -> boolean,
	SetEnabled: (self: Pipeline, name: string, enabled: boolean) -> boolean,
	Run: (self: Pipeline, context: any, phase: string) -> (),
}

local DEFAULT_ORDER = 100

local compare = function(a: Stage, b: Stage): boolean
	if a.order == b.order then
		return a.name < b.name
	end
	return a.order < b.order
end

local find = function(self: Pipeline, name: string): (number?, Stage?)
	for index, stage in self.stages do
		if stage.name == name then
			return index, stage
		end
	end
	return nil, nil
end

local register = function(self: Pipeline, name: string, callback: Callback, order: number?): ()
	assert(type(name) == "string" and name ~= "", "Pipeline.Register expects a non-empty name")
	assert(type(callback) == "function", "Pipeline.Register expects a callback")

	local stage: Stage = {
		name = name,
		callback = callback,
		order = if order ~= nil then order else DEFAULT_ORDER,
		enabled = true,
	}
	local index = find(self, name)

	if index ~= nil then
		self.stages[index] = stage
	else
		self.stages[#self.stages + 1] = stage
	end

	table.sort(self.stages, compare)
	self.version += 1
end

local remove = function(self: Pipeline, name: string): boolean
	local index = find(self, name)

	if index == nil then
		return false
	end

	table.remove(self.stages, index)
	self.version += 1
	return true
end

local set_enabled = function(self: Pipeline, name: string, enabled: boolean): boolean
	local _, stage = find(self, name)

	if stage == nil then
		return false
	end

	stage.enabled = enabled
	return true
end

local run = function(self: Pipeline, context: any, phase: string): ()
	local snapshot = self.snapshot

	if self.snapshot_version ~= self.version then
		snapshot = table.clone(self.stages)
		self.snapshot = snapshot
		self.snapshot_version = self.version
	end

	for index = 1, #snapshot do
		local stage = snapshot[index]

		if stage.enabled then
			local ok, err = pcall(stage.callback :: (any, string) -> any, context, phase)

			if not ok then
				local warn_fn: any = env.warn

				if warn_fn == nil then
					warn_fn = warn
				end

				warn_fn(string.format(
					"[Bloom.Pipeline] Stage '%s' failed during '%s': %s",
					stage.name,
					phase,
					tostring(err)
				))
			end
		end
	end
end

local new = function(): Pipeline
	return {
		stages = {},
		snapshot = {},
		version = 0,
		snapshot_version = 0,
		Register = register,
		Remove = remove,
		SetEnabled = set_enabled,
		Run = run,
	}
end

return {
	new = new,
}
