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

local asset_service = game:GetService("AssetService")

export type Status = "supported" | "disabled" | "out_of_memory"

export type Report = {
	supported: boolean,
	status: Status,
	message: string,
	details: string?,
}

local PROBE_SIZE = Vector2.one
local PROBE_BYTES = 4

local DISABLED_MESSAGE = table.concat({
	"Bloom: EditableImage is not available in this experience.",
	"In Studio open File > Experience Settings > Security and enable 'Allow Mesh / Image APIs'.",
	"For a published experience open Creator Dashboard > Configure > Settings and enable 'Enable Mesh / Image APIs'.",
	"The toggle requires a 13+ ID-verified account.",
}, " ")

local OUT_OF_MEMORY_MESSAGE =
	"Bloom: EditableImage memory budget is exhausted on this device; destroy unused EditableImages and try again."

--[=[
	@class Support

	Checks whether this experience may use `EditableImage` before Bloom allocates any tiles.

	Roblox disables the Mesh / Image APIs by default for published experiences. Creating,
	writing and reading an image can each fail independently, so the probe exercises all three
	on a 1x1 image and destroys it afterwards.
]=]
local support = {}

local cached_report: Report? = nil

local function report(status: Status, message: string, details: string?): Report
	return table.freeze({
		supported = status == "supported",
		status = status,
		message = message,
		details = details,
	})
end

local function exercise(editable: EditableImage): buffer
	editable:WritePixelsBuffer(Vector2.zero, PROBE_SIZE, buffer.create(PROBE_BYTES))

	return editable:ReadPixelsBuffer(Vector2.zero, PROBE_SIZE)
end

local function probe(): Report
	local created, result = pcall(asset_service.CreateEditableImage, asset_service, { Size = PROBE_SIZE })

	if not created then
		return report("disabled", DISABLED_MESSAGE, tostring(result))
	end

	local editable: EditableImage? = result

	if editable == nil then
		return report("out_of_memory", OUT_OF_MEMORY_MESSAGE)
	end

	local usable, result_or_error = pcall(exercise, editable)
	editable:Destroy()

	if not usable then
		return report("disabled", DISABLED_MESSAGE, tostring(result_or_error))
	end

	return report("supported", "Bloom: EditableImage is available.")
end

--[=[
	Probes the EditableImage API. A successful result is cached; failures are re-checked on the
	next call because the memory budget can recover.

	@within Support
	@return Report -- `supported`, `status` ("supported" | "disabled" | "out_of_memory"), `message`, `details`.
]=]
support.Check = function(): Report
	if cached_report ~= nil then
		return cached_report
	end

	local result = probe()

	if result.supported then
		cached_report = result
	end

	return result
end

--[=[
	Returns true when EditableImage can be created, written and read.

	@within Support
	@return boolean
]=]
support.IsSupported = function(): boolean
	return support.Check().supported
end

--[=[
	Raises the report's message unless EditableImage is available.

	@within Support
]=]
support.Assert = function(): ()
	local result = support.Check()
	if not result.supported then
		local suffix = if result.details then ` ({result.details})` else ""
		error(result.message .. suffix, 3)
	end
end

--[=[
	@private
	Forgets the cached result. Used by tests.
]=]
support._Reset = function(): ()
	cached_report = nil
end

return support
