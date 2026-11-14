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

local platform = require("./platform")
local types = require("./types")

local PROBE_SIZE = 1
local PROBE_BYTES = 4

local DISABLED_MESSAGE = table.concat({
	"Bloom: EditableImage is not available in this experience.",
	"In Studio open File > Experience Settings > Security and enable 'Allow Mesh / Image APIs'.",
	"For a published experience open Creator Dashboard > Configure > Settings and enable 'Enable Mesh / Image APIs'.",
	"The toggle requires a 13+ ID-verified account.",
}, " ")

local OUT_OF_MEMORY_MESSAGE =
	"Bloom: EditableImage memory budget is exhausted on this device; destroy unused EditableImages and try again."

local SUPPORTED_MESSAGE = "Bloom: EditableImage is available."

local SERVICE_MESSAGE = "Bloom: AssetService:CreateEditableImage is unavailable in this environment."

local cached: types.SupportReport? = nil

local report = function(status: types.SupportStatus, message: string, details: string?): types.SupportReport
	return table.freeze({
		supported = status == "supported",
		status = status,
		message = message,
		details = details,
	})
end

local exercise = function(editable: any): string?
	local position = platform.vector2(0, 0)
	local size = platform.vector2(PROBE_SIZE, PROBE_SIZE)
	editable:WritePixelsBuffer(position, size, buffer.create(PROBE_BYTES))
	local read_back = editable:ReadPixelsBuffer(position, size)

	if read_back == nil then
		return "Bloom: EditableImage probe read back no pixel data."
	end

	local length = buffer.len(read_back)

	if length ~= PROBE_BYTES then
		return `Bloom: EditableImage probe read back {length} bytes; expected {PROBE_BYTES}.`
	end

	return nil
end

local probe = function(): types.SupportReport
	local found, service = pcall(platform.service, "AssetService")

	if not found then
		return report("disabled", DISABLED_MESSAGE, tostring(service))
	end

	if service == nil or type(service.CreateEditableImage) ~= "function" then
		return report("disabled", DISABLED_MESSAGE, SERVICE_MESSAGE)
	end

	local created, result =
		pcall(service.CreateEditableImage, service, { Size = platform.vector2(PROBE_SIZE, PROBE_SIZE) })

	if not created then
		return report("disabled", DISABLED_MESSAGE, tostring(result))
	end

	if result == nil then
		return report("out_of_memory", OUT_OF_MEMORY_MESSAGE)
	end

	local ok, problem = pcall(exercise, result)
	pcall(result.Destroy, result)

	if not ok then
		return report("disabled", DISABLED_MESSAGE, tostring(problem))
	end

	if problem ~= nil then
		return report("disabled", DISABLED_MESSAGE, problem)
	end

	return report("supported", SUPPORTED_MESSAGE)
end

local support = {}

support.check = function(): types.SupportReport
	if cached ~= nil then
		return cached
	end

	local result = probe()

	if result.supported then
		cached = result
	end

	return result
end

support.is_supported = function(): boolean
	return support.check().supported
end

support.assert_supported = function(): ()
	local result = support.check()

	if not result.supported then
		local details = result.details
		error(if details ~= nil then `{result.message} ({details})` else result.message, 3)
	end
end

support.reset = function(): ()
	cached = nil
end

return support
