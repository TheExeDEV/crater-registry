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

export type PackedColor = number

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
	editable: any,
	image: any,
	dirty_full: boolean,
	dmin_x: number,
	dmin_y: number,
	dmax_x: number,
	dmax_y: number,
}

export type Context = {
	res_x: number,
	res_y: number,
	tile_size: number,
	size_x: number,
	size_y: number,
	parent: any,
	reference: any,
	pixel_buffer: buffer,
	tiles: { [number]: Tile },
	auto_clip: boolean,
	state: ViewState,
	async: any,
	pipeline: any,
	stats: any,
	_destroyed: boolean,
	_owns_resources: boolean,
	_clear_color_applied: number,
	_clear_frame_exposed: boolean,
	_col_tile: { [number]: number },
	_col_local: { [number]: number },
	_row_base: { [number]: number },
	_row_local: { [number]: number },
	_row_buffer: buffer?,
	_row_color: number?,
	_row_width: number,
	_upload_scratch: buffer?,
	_upload_scratch_bytes: number,
	_upload_staging: buffer?,
	_upload_staging_bytes: number,
	_upload_cancel: ((context: any) -> ())?,
	_pending_uploads: number,
	_tile_generations: { [number]: number },
	_dirty_tiles: { [number]: boolean },
	_dirty_list: { number },
	_upload_batch_active: boolean,
	_texture_columns: { [number]: number },
	_texture_columns_capacity: number,
	_coverage: buffer?,
	_aa_min: { [number]: number },
	_aa_max: { [number]: number },
	_aa_touched: { number },
	_brush: { [number]: any },
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
	scheduler_pending: number,
	scheduler_active: number,
	scheduler_completed: number,
	scheduler_failed: number,
	scheduler_cancelled: number,
	scheduler_last_step_seconds: number,
	scheduler_max_step_seconds: number,
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

export type SchedulerOptions = {
	poll_interval: number?,
	aging_interval: number?,
	max_tasks_per_step: number?,
}

export type Options = {
	tile_size: number?,
	async_budget: number?,
	scheduler_options: SchedulerOptions?,
	auto_clip: boolean?,
	clear_color: PackedColor?,
}

export type SubmitOptions = {
	priority: number?,
	deadline: number?,
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

export type Texture = {
	width: number,
	height: number,
	pixels: buffer,
	opaque: boolean,
	destroyed: boolean,
	GetPixel: (self: Texture, x: number, y: number) -> PackedColor,
	Destroy: (self: Texture) -> (),
}

export type Font = {
	texture: Texture,
	glyphs: GlyphMap,
	line_height: number,
	spacing: number,
	fallback: number,
	destroyed: boolean,
	Destroy: (self: Font) -> (),
}

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

export type UniformMap = { [string]: UniformValue }

export type ShaderCallback = (
	x: number,
	y: number,
	u: number,
	v: number,
	color32: PackedColor,
	uniforms: UniformMap
) -> PackedColor?

export type Shader = {
	name: string,
	callback: ShaderCallback,
	uniforms: UniformMap,
	enabled: boolean,
}

export type TaskState = "pending" | "running" | "yielded" | "completed" | "cancelled" | "failed"

export type Task = {
	state: TaskState,
	priority: number,
	submitted_at: number,
	started_at: number?,
	finished_at: number?,
	deadline: number?,
	error: string?,
	Cancel: (self: Task) -> (),
	IsCancelled: (self: Task) -> boolean,
	IsFinished: (self: Task) -> boolean,
}

export type Scheduler = {
	Start: (self: Scheduler) -> (),
	Stop: (self: Scheduler) -> (),
	Step: (self: Scheduler, budget: number?) -> number,
	Submit: (self: Scheduler, callback: (...any) -> ...any, ...any) -> Task,
	SubmitWithOptions: (self: Scheduler, callback: (...any) -> ...any, options: SubmitOptions, ...any) -> Task,
	PendingCount: (self: Scheduler) -> number,
	GetStats: (self: Scheduler) -> SchedulerStats,
	Clear: (self: Scheduler) -> (),
	Destroy: (self: Scheduler) -> (),
}

export type StageCallback = (context: any, phase: string) -> ()

export type Stage = {
	name: string,
	callback: StageCallback,
	order: number,
	enabled: boolean,
}

export type Pipeline = {
	Register: (self: Pipeline, name: string, callback: StageCallback, order: number?) -> (),
	Remove: (self: Pipeline, name: string) -> boolean,
	SetEnabled: (self: Pipeline, name: string, enabled: boolean) -> boolean,
	Run: (self: Pipeline, context: any, phase: string) -> (),
}

export type SupportStatus = "supported" | "disabled" | "out_of_memory"

export type SupportReport = {
	supported: boolean,
	status: SupportStatus,
	message: string,
	details: string?,
}

export type PixelCallback = (x: number, y: number, color32: PackedColor) -> PackedColor?

export type Bloom = {
	res_x: number,
	res_y: number,
	tile_size: number,
	size_x: number,
	size_y: number,
	parent: any,
	reference: any,
	tiles: { [number]: Tile },
	auto_clip: boolean,
	state: ViewState,
	async: Scheduler,
	pipeline: Pipeline,
	stats: Stats,
	BeginFrame: (self: Bloom, clear_color: PackedColor?) -> (),
	EndFrame: (self: Bloom, use_async: boolean?) -> (),
	Clear: (self: Bloom, color32: PackedColor?) -> (),
	SetClearColor: (self: Bloom, color32: PackedColor) -> (),
	Update: (self: Bloom) -> (),
	UpdateAsync: (self: Bloom, budget: number?) -> (),
	Resize: (self: Bloom, resolution: Vector2) -> (),
	SetViewport: (self: Bloom, x: number, y: number, width: number, height: number) -> (),
	ResetViewport: (self: Bloom) -> (),
	MarkDirty: (self: Bloom, x0: number, y0: number, x1: number, y1: number) -> (),
	GetState: (self: Bloom) -> ViewState,
	GetBuffer: (self: Bloom) -> buffer,
	GetStats: (self: Bloom) -> Stats,
	ResetStats: (self: Bloom) -> (),
	Destroy: (self: Bloom) -> (),
	DrawPixel: (self: Bloom, x: number, y: number, color32: PackedColor) -> (),
	DrawPixelUnsafe: (self: Bloom, x: number, y: number, color32: PackedColor) -> (),
	ReadPixel: (self: Bloom, x: number, y: number) -> PackedColor,
	ReadPixelUnsafe: (self: Bloom, x: number, y: number) -> PackedColor,
	DrawLine: (self: Bloom, x0: number, y0: number, x1: number, y1: number, color32: PackedColor) -> (),
	DrawLineAA: (
		self: Bloom,
		x0: number,
		y0: number,
		x1: number,
		y1: number,
		thickness: number,
		color32: PackedColor
	) -> (),
	DrawHorizontalLine: (self: Bloom, x0: number, y: number, x1: number, color32: PackedColor) -> (),
	DrawVerticalLine: (self: Bloom, x: number, y0: number, y1: number, color32: PackedColor) -> (),
	DrawRectangle: (self: Bloom, x0: number, y0: number, x1: number, y1: number, color32: PackedColor) -> (),
	DrawTriangle: (
		self: Bloom,
		x0: number,
		y0: number,
		x1: number,
		y1: number,
		x2: number,
		y2: number,
		color32: PackedColor
	) -> (),
	DrawTexture: (
		self: Bloom,
		texture: Texture,
		x: number,
		y: number,
		width: number?,
		height: number?,
		options: TextureDrawOptions?
	) -> (),
	DrawText: (
		self: Bloom,
		font: Font,
		text: string,
		x: number,
		y: number,
		color32: PackedColor?,
		scale: number?
	) -> (number, number),
	ApplyShader: (
		self: Bloom,
		shader: Shader,
		x0: number,
		y0: number,
		x1: number,
		y1: number,
		uniforms: UniformMap?
	) -> number,
	EachPixel: (
		self: Bloom,
		callback: PixelCallback?,
		x0: number?,
		y0: number?,
		x1: number?,
		y1: number?
	) -> number,
	RegisterStage: (self: Bloom, name: string, callback: StageCallback, order: number?) -> (),
	RemoveStage: (self: Bloom, name: string) -> boolean,
	Submit: (self: Bloom, callback: (...any) -> ...any, ...any) -> Task,
	SubmitWithOptions: (self: Bloom, callback: (...any) -> ...any, options: SubmitOptions, ...any) -> Task,
}

return nil
