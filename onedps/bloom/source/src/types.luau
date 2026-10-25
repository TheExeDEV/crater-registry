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

-- Packed RGBA, little-endian: 0xAABBGGRR. Matches the byte order of EditableImage buffers.
export type PackedColor = number

-- 0 is highest, 3 is background.
export type Priority = number

export type TaskState = "pending" | "running" | "yielded" | "completed" | "cancelled" | "failed"

export type PipelinePhase =
	"beginFrame"
	| "endFrame"
	| "beforeUpload"
	| "afterUpload"
	| "tileUploaded"
	| "beforeShader"
	| "afterShader"
	| string

export type Viewport = {
	x: number,
	y: number,
	w: number,
	h: number,
}

export type ViewState = {
	clear_color: PackedColor,
	viewport: Viewport,
}

export type Tile = {
	x: number,
	y: number,
	w: number,
	h: number,
	editable: EditableImage,
	buffer: buffer,
	image: ImageLabel?,
}

export type Stats = {
	update_calls: number,
	last_update_seconds: number,
	uploaded_tiles: number,
	uploaded_bytes: number,
	upload_seconds: number,
	shader_pixels: number,
	texture_pixels: number,
	text_glyphs: number,
}

export type SchedulerStats = {
	pending: number,
	active: number,
	completed: number,
	failed: number,
	cancelled: number,
	last_step_seconds: number,
	max_step_seconds: number,
}

export type BloomStats = Stats & {
	scheduler_pending: number,
	scheduler_active: number,
	scheduler_completed: number,
	scheduler_failed: number,
	scheduler_cancelled: number,
	scheduler_last_step_seconds: number,
	scheduler_max_step_seconds: number,
}

export type SchedulerOptions = {
	poll_interval: number?,
	aging_interval: number?,
	max_tasks_per_step: number?,
}

export type SubmitOptions = {
	priority: Priority?,
	deadline: number?,
}

export type BloomOptions = {
	tile_size: number?,
	async_budget: number?,
	scheduler_options: SchedulerOptions?,
	auto_clip: boolean?,
	clear_color: PackedColor?,
}

export type TextureDrawOptions = {
	source_x: number?,
	source_y: number?,
	source_width: number?,
	source_height: number?,
	tint: PackedColor?,
	opacity: number?,
	blend: boolean?,
}

export type FontOptions = {
	spacing: number?,
	fallback: number?,
}

export type Glyph = {
	x: number,
	y: number,
	width: number,
	height: number,
	xoffset: number?,
	yoffset: number?,
	xadvance: number?,
}

export type GlyphMap = { [number]: Glyph }
export type GlyphInput = { [string | number]: Glyph }

export type UniformValue =
	number
	| boolean
	| string
	| Vector2
	| Vector3
	| Color3
	| ColorSequence
	| NumberSequence
	| CFrame
	| UDim
	| UDim2
	| buffer
export type Uniforms = { [string]: UniformValue }

export type ShaderCallback = (
	x: number,
	y: number,
	u: number,
	v: number,
	color32: PackedColor,
	uniforms: Uniforms
) -> PackedColor?

export type StageCallback = (context: any, phase: PipelinePhase) -> ()

export type Task = {
	callback: (...any) -> ...any,
	arguments: { n: number, [number]: any },
	state: TaskState,
	priority: Priority,
	submitted_at: number,
	started_at: number?,
	finished_at: number?,
	deadline: number?,
	error: string?,
	thread: thread?,
	Cancel: (self: Task) -> (),
	IsCancelled: (self: Task) -> boolean,
	IsFinished: (self: Task) -> boolean,
}

export type TextureLike = {
	width: number,
	height: number,
	pixels: buffer,
	destroyed: boolean,
	Destroy: (self: TextureLike) -> (),
	GetPixel: (self: TextureLike, x: number, y: number) -> PackedColor,
}

export type FontLike = {
	texture: TextureLike,
	glyphs: GlyphMap,
	line_height: number,
	spacing: number,
	fallback: number,
	destroyed: boolean,
	Destroy: (self: FontLike) -> (),
}

export type ShaderLike = {
	name: string,
	callback: ShaderCallback,
	uniforms: Uniforms,
	enabled: boolean,
}

export type SchedulerLike = {
	budget: number,
	poll_interval: number,
	aging_interval: number,
	max_tasks_per_step: number,
	pending_count: number,
	active_count: number,
	completed_count: number,
	failed_count: number,
	cancelled_count: number,
	last_step_seconds: number,
	max_step_seconds: number,
	Start: (self: SchedulerLike) -> (),
	Stop: (self: SchedulerLike) -> (),
	Step: (self: SchedulerLike, budget: number?) -> number,
	Submit: (self: SchedulerLike, callback: (...any) -> ...any, ...any) -> Task,
	SubmitWithOptions: (self: SchedulerLike, callback: (...any) -> ...any, options: SubmitOptions, ...any) -> Task,
	PendingCount: (self: SchedulerLike) -> number,
	GetStats: (self: SchedulerLike) -> SchedulerStats,
	Clear: (self: SchedulerLike) -> (),
	Destroy: (self: SchedulerLike) -> (),
}

export type PipelineLike = {
	Register: (self: PipelineLike, name: string, callback: StageCallback, order: number?) -> (),
	Remove: (self: PipelineLike, name: string) -> boolean,
	SetEnabled: (self: PipelineLike, name: string, enabled: boolean) -> boolean,
	Run: (self: PipelineLike, context: any, phase: PipelinePhase) -> (),
}
export type self = {
	res_x: number,
	res_y: number,
	tile_size: number,
	size_x: number,
	size_y: number,
	parent: Instance?,
	reference: ImageLabel?,
	pixel_buffer: buffer,
	tiles: { [number]: Tile },
	editables: { [number]: EditableImage },
	images: { [number]: ImageLabel },
	auto_clip: boolean,
	state: ViewState,
	async: SchedulerLike,
	pipeline: PipelineLike,
	stats: Stats,

	_dirty_tiles: { [number]: boolean },
	_scheduled_tile_tasks: { [number]: Task },
	_pending_uploads: number,
	_destroyed: boolean,
	_frame_active: boolean,
	_owns_resources: boolean,
	_clear_row_buffer: buffer?,
	_clear_row_color: PackedColor?,
	_rect_row_buffer: buffer?,
	_rect_row_width: number,
	_rect_row_color: PackedColor?,

	_MarkDirty: (self: self, x: number, y: number) -> (),
	_MarkDirtyRect: (self: self, x0: number, y0: number, x1: number, y1: number) -> (),
	Update: (self: self) -> (),
	UpdateAsync: (self: self, budget: number?) -> (),
	Clear: (self: self, color32: PackedColor?) -> (),
	Resize: (self: self, resolution: Vector2) -> (),
	SetViewport: (self: self, x: number, y: number, width: number, height: number) -> (),
	ResetViewport: (self: self) -> (),
	BeginFrame: (self: self, clear_color: PackedColor?) -> (),
	EndFrame: (self: self, use_async: boolean?) -> (),
	SetClearColor: (self: self, color32: PackedColor) -> (),
	GetState: (self: self) -> ViewState,
	GetBuffer: (self: self) -> buffer,
	MarkDirty: (self: self, x0: number, y0: number, x1: number, y1: number) -> (),

	DrawTexture: (
		self: self,
		source: TextureLike,
		x: number,
		y: number,
		width: number?,
		height: number?,
		options: TextureDrawOptions?
	) -> (),
	ApplyShader: (
		self: self,
		shader: ShaderLike,
		x0: number,
		y0: number,
		x1: number,
		y1: number,
		uniforms: Uniforms?
	) -> number,
	DrawText: (
		self: self,
		font: FontLike,
		value: string,
		x: number,
		y: number,
		color32: PackedColor?,
		scale: number?
	) -> (number, number),

	DrawHorizontalLine: (self: self, x0: number, y: number, x1: number, color32: PackedColor) -> (),
	DrawVerticalLine: (self: self, x: number, y0: number, y1: number, color32: PackedColor) -> (),
	DrawLine: (self: self, x0: number, y0: number, x1: number, y1: number, color32: PackedColor) -> (),
	DrawLineAA: (
		self: self,
		x0: number,
		y0: number,
		x1: number,
		y1: number,
		thickness: number,
		color32: PackedColor
	) -> (),

	DrawPixel: (self: self, x: number, y: number, color32: PackedColor) -> (),
	DrawPixelUnsafe: (self: self, x: number, y: number, color32: PackedColor) -> (),
	ReadPixel: (self: self, x: number, y: number) -> PackedColor,
	ReadPixelUnsafe: (self: self, x: number, y: number) -> PackedColor,
	DrawRectangle: (self: self, x0: number, y0: number, x1: number, y1: number, color32: PackedColor) -> (),
	DrawTriangle: (
		self: self,
		x0: number,
		y0: number,
		x1: number,
		y1: number,
		x2: number,
		y2: number,
		color32: PackedColor
	) -> (),

	RegisterStage: (self: self, name: string, callback: StageCallback, order: number?) -> (),
	RemoveStage: (self: self, name: string) -> boolean,
	Submit: (self: self, callback: (...any) -> (), ...any) -> Task,
	SubmitWithOptions: (self: self, callback: (...any) -> (), options: SubmitOptions, ...any) -> Task,
	GetStats: (self: self) -> BloomStats,
	ResetStats: (self: self) -> (),
	Destroy: (self: self) -> (),
}

return nil
