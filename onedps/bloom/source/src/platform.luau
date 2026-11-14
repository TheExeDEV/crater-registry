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

local env: any = _G

local game_value: any = nil
local vector2_value: any = nil
local udim2_value: any = nil
local instance_value: any = nil
local content_value: any = nil

local resolve = function(cached: any, value: any): any
	if cached ~= nil then
		return cached
	end
	return value
end

local game_instance = function(): any
	game_value = resolve(game_value, env.game or game)
	return game_value
end

local service = function(name: string): any
	return game_instance():GetService(name)
end

local vector2 = function(x: number, y: number): any
	vector2_value = resolve(vector2_value, env.Vector2 or Vector2)
	return vector2_value.new(x, y)
end

local udim2 = function(x_scale: number, x_offset: number, y_scale: number, y_offset: number): any
	udim2_value = resolve(udim2_value, env.UDim2 or UDim2)
	return udim2_value.new(x_scale, x_offset, y_scale, y_offset)
end

local new_instance = function(class_name: string, parent: any): any
	instance_value = resolve(instance_value, env.Instance or Instance)
	local instance = instance_value.new(class_name)
	instance.Parent = parent
	return instance
end

local create_editable_image = function(width: number, height: number): any
	return service("AssetService"):CreateEditableImage({ Size = vector2(width, height) })
end

local content_from_object = function(object: any): any
	content_value = resolve(content_value, env.Content or Content)
	return content_value.fromObject(object)
end

local task_value: any = env.task or task or require("@lune/task")

return {
	service = service,
	create_editable_image = create_editable_image,
	new_instance = new_instance,
	vector2 = vector2,
	udim2 = udim2,
	content_from_object = content_from_object,
	task = task_value,
}
