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
local clip = require("./clip")
local damage = require("./damage")
local texture_module = require("./texture")

type Context = Types.Context
type Glyph = Types.Glyph
type GlyphMap = Types.GlyphMap
type Texture = Types.Texture
type Font = Types.Font
export type Options = Types.FontOptions

type Point = {
	x: number,
	y: number,
	on: boolean,
}

type Contour = { Point }

type TableEntry = {
	offset: number,
	length: number,
}

type CmapInfo = {
	offset: number,
	format: number,
	length: number,
}

type FontFile = {
	data: buffer,
	tables: { [string]: TableEntry },
	units_per_em: number,
	long_loca: boolean,
	glyph_count: number,
	ascender: number,
	descender: number,
	horizontal_metric_count: number,
	cmap: CmapInfo,
}

type EdgeBuffer = {
	count: number,
	from_x: { number },
	from_y: { number },
	to_x: { number },
	to_y: { number },
}

local DEFAULT_CHARSET =
	" !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
local QUESTION_MARK = 63
local NEWLINE = 10
local TAB = 9
local SPACE = 32
local TAB_WIDTH_IN_SPACES = 4

local MIN_PIXEL_SIZE, MAX_PIXEL_SIZE = 4, 128
local MAX_ATLAS_WIDTH = 512
local MAX_ATLAS_PIXELS = 1024 * 1024
local GLYPH_PADDING = 1
local CURVE_SEGMENTS = 6
local MAX_COMPOSITE_DEPTH = 8
local WHITE_RGB = 0x00FFFFFF
local OPAQUE_WHITE = 0xFFFFFFFF
local BYTES_PER_PIXEL = 4
local SUB_SCANLINES = 4
local ALPHA_PER_SAMPLE = 255 / SUB_SCANLINES

local SFNT_VERSION_TRUETYPE = 0x00010000
local SFNT_VERSION_APPLE = 0x74727565

local FLAG_ON_CURVE = 0x01
local FLAG_REPEAT = 0x08
local FLAG_X_SHORT = 0x02
local FLAG_Y_SHORT = 0x04
local FLAG_X_SAME_OR_POSITIVE = 0x10
local FLAG_Y_SAME_OR_POSITIVE = 0x20

local COMPOSITE_ARGS_ARE_WORDS = 0x0001
local COMPOSITE_ARGS_ARE_XY = 0x0002
local COMPOSITE_HAS_SCALE = 0x0008
local COMPOSITE_MORE_COMPONENTS = 0x0020
local COMPOSITE_HAS_XY_SCALE = 0x0040
local COMPOSITE_HAS_2X2 = 0x0080

local font = {}

local read_u32 = function(data: buffer, offset: number): number
	return bit32.byteswap(buffer.readu32(data, offset))
end

local read_u16 = function(data: buffer, offset: number): number
	return bit32.rshift(bit32.byteswap(buffer.readu16(data, offset)), 16)
end

local read_i16 = function(data: buffer, offset: number): number
	local value = read_u16(data, offset)

	return if value >= 32768 then value - 65536 else value
end

local read_f2dot14 = function(data: buffer, offset: number): number
	return read_i16(data, offset) / 16384
end

local require_range = function(data: buffer, offset: number, length: number, label: string): ()
	assert(
		offset >= 0 and length >= 0 and offset + length <= buffer.len(data),
		"Invalid or truncated TrueType font: " .. label
	)
end

local read_table_directory = function(data: buffer): { [string]: TableEntry }
	require_range(data, 0, 12, "sfnt header")

	local version = read_u32(data, 0)

	assert(
		version == SFNT_VERSION_TRUETYPE or version == SFNT_VERSION_APPLE,
		"Font supports TrueType-outline TTF files only; CFF/WOFF/WOFF2 are not supported"
	)

	local table_count = read_u16(data, 4)
	require_range(data, 12, table_count * 16, "table directory")

	local tables: { [string]: TableEntry } = {}

	for index = 0, table_count - 1 do
		local record = 12 + index * 16
		local tag = buffer.readstring(data, record, 4)
		local offset = read_u32(data, record + 8)
		local length = read_u32(data, record + 12)

		require_range(data, offset, length, tag)
		tables[tag] = { offset = offset, length = length }
	end

	return tables
end

local find_unicode_cmap = function(data: buffer, cmap: TableEntry): CmapInfo
	local record_count = read_u16(data, cmap.offset + 2)
	local best_offset: number? = nil
	local best_format = 0

	for index = 0, record_count - 1 do
		local record = cmap.offset + 4 + index * 8
		local platform = read_u16(data, record)
		local subtable = cmap.offset + read_u32(data, record + 4)
		require_range(data, subtable, 4, "cmap subtable")

		local format = read_u16(data, subtable)
		local unicode_platform = platform == 0 or platform == 3

		if unicode_platform and format == 12 then
			best_offset, best_format = subtable, 12
			break
		elseif unicode_platform and format == 4 then
			best_offset, best_format = subtable, 4
		end
	end

	assert(best_offset ~= nil, "TTF has no supported Unicode cmap (format 4 or 12)")

	local offset = best_offset :: number
	local length = if best_format == 12 then read_u32(data, offset + 4) else read_u16(data, offset + 2)
	require_range(data, offset, length, "Unicode cmap")

	return { offset = offset, format = best_format, length = length }
end

local parse_font = function(data: buffer): FontFile
	local tables = read_table_directory(data)
	local head, maxp, hhea = tables.head, tables.maxp, tables.hhea

	assert(
		head and maxp and hhea and tables.hmtx and tables.loca and tables.glyf and tables.cmap,
		"TTF is missing a required TrueType table"
	)

	local file: FontFile = {
		data = data,
		tables = tables,
		units_per_em = read_u16(data, head.offset + 18),
		long_loca = read_i16(data, head.offset + 50) ~= 0,
		glyph_count = read_u16(data, maxp.offset + 4),
		ascender = read_i16(data, hhea.offset + 4),
		descender = read_i16(data, hhea.offset + 6),
		horizontal_metric_count = read_u16(data, hhea.offset + 34),
		cmap = find_unicode_cmap(data, tables.cmap),
	}

	assert(
		file.units_per_em > 0 and file.glyph_count > 0 and file.horizontal_metric_count > 0,
		"Invalid TrueType metrics"
	)

	return file
end

local lookup_format12 = function(data: buffer, cmap: CmapInfo, codepoint: number): number
	local low, high = 0, read_u32(data, cmap.offset + 12) - 1

	while low <= high do
		local middle = (low + high) // 2
		local group = cmap.offset + 16 + middle * 12
		local first, last = read_u32(data, group), read_u32(data, group + 4)

		if codepoint < first then
			high = middle - 1
		elseif codepoint > last then
			low = middle + 1
		else
			return read_u32(data, group + 8) + codepoint - first
		end
	end

	return 0
end

local lookup_format4 = function(data: buffer, cmap: CmapInfo, codepoint: number): number
	if codepoint > 0xFFFF then
		return 0
	end

	local segment_count = read_u16(data, cmap.offset + 6) // 2
	local end_codes = cmap.offset + 14
	local start_codes = end_codes + segment_count * 2 + 2
	local id_deltas = start_codes + segment_count * 2
	local id_range_offsets = id_deltas + segment_count * 2

	for segment = 0, segment_count - 1 do
		if codepoint <= read_u16(data, end_codes + segment * 2) then
			local start_code = read_u16(data, start_codes + segment * 2)

			if codepoint < start_code then
				return 0
			end

			local delta = read_i16(data, id_deltas + segment * 2)
			local range_offset_address = id_range_offsets + segment * 2
			local range_offset = read_u16(data, range_offset_address)

			if range_offset == 0 then
				return (codepoint + delta) % 65536
			end

			local glyph_address = range_offset_address + range_offset + (codepoint - start_code) * 2
			if glyph_address + 2 > cmap.offset + cmap.length then
				return 0
			end

			local glyph = read_u16(data, glyph_address)

			return glyph == 0 and 0 or (glyph + delta) % 65536
		end
	end

	return 0
end

local glyph_index_for = function(file: FontFile, codepoint: number): number
	if file.cmap.format == 12 then
		return lookup_format12(file.data, file.cmap, codepoint)
	end

	return lookup_format4(file.data, file.cmap, codepoint)
end

local glyph_offset = function(file: FontFile, glyph_index: number): number?
	if glyph_index < 0 or glyph_index >= file.glyph_count then
		return nil
	end

	local data, loca = file.data, file.tables.loca
	local start, finish

	if file.long_loca then
		start = read_u32(data, loca.offset + glyph_index * 4)
		finish = read_u32(data, loca.offset + (glyph_index + 1) * 4)
	else
		start = read_u16(data, loca.offset + glyph_index * 2) * 2
		finish = read_u16(data, loca.offset + (glyph_index + 1) * 2) * 2
	end

	if finish <= start then
		return nil
	end

	return file.tables.glyf.offset + start
end

local horizontal_metrics = function(file: FontFile, glyph_index: number): (number, number)
	local data, hmtx = file.data, file.tables.hmtx
	local metric_count = file.horizontal_metric_count

	if glyph_index < metric_count then
		local record = hmtx.offset + glyph_index * 4
		return read_u16(data, record), read_i16(data, record + 2)
	end

	local advance = read_u16(data, hmtx.offset + (metric_count - 1) * 4)
	local bearing = read_i16(data, hmtx.offset + metric_count * 4 + (glyph_index - metric_count) * 2)

	return advance, bearing
end

local glyph_bounds = function(file: FontFile, glyph_index: number): (number, number, number, number)
	local base = glyph_offset(file, glyph_index)

	if base == nil then
		return 0, 0, 0, 0
	end

	local data = file.data

	return read_i16(data, base + 2),
		read_i16(data, base + 4),
		read_i16(data, base + 6),
		read_i16(data, base + 8)
end

local read_flags = function(data: buffer, cursor: number, point_count: number): ({ number }, number)
	require_range(data, cursor, point_count, "glyph flags")
	local flags: { number } = table.create(point_count)

	while #flags < point_count do
		local flag = buffer.readu8(data, cursor)
		cursor += 1
		table.insert(flags, flag)

		if bit32.btest(flag, FLAG_REPEAT) then
			local repeat_count = buffer.readu8(data, cursor)
			cursor += 1

			for _ = 1, repeat_count do
				table.insert(flags, flag)
			end
		end
	end

	return flags, cursor
end

local read_coordinates = function(
	data: buffer,
	cursor: number,
	flags: { number },
	point_count: number,
	short_flag: number,
	same_or_positive_flag: number
): ({ number }, number)
	local values: { number } = table.create(point_count)
	local value = 0

	for index = 1, point_count do
		local flag = flags[index]

		if bit32.btest(flag, short_flag) then
			local magnitude = buffer.readu8(data, cursor)
			value += if bit32.btest(flag, same_or_positive_flag) then magnitude else -magnitude
			cursor += 1
		elseif not bit32.btest(flag, same_or_positive_flag) then
			value += read_i16(data, cursor)
			cursor += 2
		end

		values[index] = value
	end

	return values, cursor
end

local read_simple_glyph = function(data: buffer, base: number, contour_count: number): { Contour }
	local end_points: { number } = table.create(contour_count)

	for index = 0, contour_count - 1 do
		end_points[index + 1] = read_u16(data, base + 10 + index * 2)
	end

	local point_count = end_points[contour_count] + 1
	local instruction_offset = base + 10 + contour_count * 2
	local cursor = instruction_offset + 2 + read_u16(data, instruction_offset)

	local flags, xs, ys
	flags, cursor = read_flags(data, cursor, point_count)
	xs, cursor = read_coordinates(data, cursor, flags, point_count, FLAG_X_SHORT, FLAG_X_SAME_OR_POSITIVE)
	ys, cursor = read_coordinates(data, cursor, flags, point_count, FLAG_Y_SHORT, FLAG_Y_SAME_OR_POSITIVE)

	local contours: { Contour } = table.create(contour_count)
	local first_point = 1

	for _, end_point in end_points do
		local last_point = end_point + 1
		local contour: Contour = table.create(last_point - first_point + 1)

		for point = first_point, last_point do
			table.insert(contour, {
				x = xs[point],
				y = ys[point],
				on = bit32.btest(flags[point], FLAG_ON_CURVE),
			})
		end

		table.insert(contours, contour)
		first_point = last_point + 1
	end

	return contours
end

local read_outline: (file: FontFile, glyph_index: number, depth: number) -> { Contour }

local read_composite_glyph = function(file: FontFile, base: number, depth: number): { Contour }
	local data = file.data
	local contours: { Contour } = {}
	local cursor = base + 10
	local flags

	repeat
		flags = read_u16(data, cursor)
		local component_index = read_u16(data, cursor + 2)
		cursor += 4

		local arg1, arg2
		if bit32.btest(flags, COMPOSITE_ARGS_ARE_WORDS) then
			if bit32.btest(flags, COMPOSITE_ARGS_ARE_XY) then
				arg1, arg2 = read_i16(data, cursor), read_i16(data, cursor + 2)
			else
				arg1, arg2 = read_u16(data, cursor), read_u16(data, cursor + 2)
			end

			cursor += 4
		else
			if bit32.btest(flags, COMPOSITE_ARGS_ARE_XY) then
				arg1, arg2 = buffer.readi8(data, cursor), buffer.readi8(data, cursor + 1)
			else
				arg1, arg2 = buffer.readu8(data, cursor), buffer.readu8(data, cursor + 1)
			end

			cursor += 2
		end

		local a, b, c, d = 1, 0, 0, 1

		if bit32.btest(flags, COMPOSITE_HAS_SCALE) then
			a = read_f2dot14(data, cursor)
			d = a
			cursor += 2
		elseif bit32.btest(flags, COMPOSITE_HAS_XY_SCALE) then
			a, d = read_f2dot14(data, cursor), read_f2dot14(data, cursor + 2)
			cursor += 4
		elseif bit32.btest(flags, COMPOSITE_HAS_2X2) then
			a, b = read_f2dot14(data, cursor), read_f2dot14(data, cursor + 2)
			c, d = read_f2dot14(data, cursor + 4), read_f2dot14(data, cursor + 6)
			cursor += 8
		end

		if bit32.btest(flags, COMPOSITE_ARGS_ARE_XY) then
			for _, child in read_outline(file, component_index, depth + 1) do
				local transformed: Contour = table.create(#child)

				for _, point in child do
					table.insert(transformed, {
						x = a * point.x + c * point.y + arg1,
						y = b * point.x + d * point.y + arg2,
						on = point.on,
					})
				end

				table.insert(contours, transformed)
			end
		end
	until not bit32.btest(flags, COMPOSITE_MORE_COMPONENTS)

	return contours
end

read_outline = function(file: FontFile, glyph_index: number, depth: number): { Contour }
	local base = glyph_offset(file, glyph_index)

	if base == nil or depth > MAX_COMPOSITE_DEPTH then
		return {}
	end

	local contour_count = read_i16(file.data, base)

	if contour_count > 0 then
		return read_simple_glyph(file.data, base, contour_count)
	elseif contour_count < 0 then
		return read_composite_glyph(file, base, depth)
	end

	return {}
end

local midpoint = function(a: Point, b: Point): Point
	return { x = (a.x + b.x) * 0.5, y = (a.y + b.y) * 0.5, on = true }
end

local contour_to_polygon = function(contour: Contour): { Point }
	local count = #contour
	local polygon: { Point } = {}

	if count == 0 then
		return polygon
	end

	local first, last = contour[1], contour[count]
	local start: Point
	local index: number

	if first.on then
		start, index = first, 2
	elseif last.on then
		start, index = last, 1
	else
		start, index = midpoint(first, last), 1
	end

	table.insert(polygon, start)

	local current = start
	local consumed = 0

	while consumed < count do
		local point = contour[(index - 1) % count + 1]

		if point.on then
			table.insert(polygon, point)

			current = point
			index += 1
			consumed += 1
		else
			local following = contour[index % count + 1]
			local endpoint = if following.on then following else midpoint(point, following)
			local advance = if following.on then 2 else 1

			for step = 1, CURVE_SEGMENTS do
				local t = step / CURVE_SEGMENTS
				local inverse = 1 - t

				table.insert(polygon, {
					x = inverse * inverse * current.x + 2 * inverse * t * point.x + t * t * endpoint.x,
					y = inverse * inverse * current.y + 2 * inverse * t * point.y + t * t * endpoint.y,
					on = true,
				})
			end

			current = endpoint
			index += advance
			consumed += advance
		end
	end

	return polygon
end

local build_edges = function(
	edges: EdgeBuffer,
	polygons: { { Point } },
	x_min: number,
	y_max: number,
	scale: number
): ()
	local count = 0
	local from_x, from_y, to_x, to_y = edges.from_x, edges.from_y, edges.to_x, edges.to_y

	for _, polygon in polygons do
		local point_count = #polygon

		if point_count >= 2 then
			local last = polygon[point_count]
			local previous_x = (last.x - x_min) * scale
			local previous_y = (y_max - last.y) * scale

			for index = 1, point_count do
				local point = polygon[index]
				local current_x = (point.x - x_min) * scale
				local current_y = (y_max - point.y) * scale

				if current_y ~= previous_y then
					count += 1
					from_x[count] = previous_x
					from_y[count] = previous_y
					to_x[count] = current_x
					to_y[count] = current_y
				end

				previous_x, previous_y = current_x, current_y
			end
		end
	end

	edges.count = count
end

local add_span = function(coverage: { number }, width: number, start_x: number, end_x: number): ()
	if start_x > end_x then
		start_x, end_x = end_x, start_x
	end
	if start_x < 0 then
		start_x = 0
	end
	if end_x > width then
		end_x = width
	end
	if end_x <= start_x then
		return
	end

	local first = math.floor(start_x)
	local last = math.ceil(end_x) - 1

	if first < 0 then
		first = 0
	end
	if last > width - 1 then
		last = width - 1
	end

	for px = first, last do
		local left = if px > start_x then px else start_x
		local right = if px + 1 < end_x then px + 1 else end_x
		local amount = right - left

		if amount > 0 then
			coverage[px + 1] += amount
		end
	end
end

local rasterize_glyph = function(
	atlas: buffer,
	atlas_width: number,
	cell_x: number,
	cell_y: number,
	width: number,
	height: number,
	edges: EdgeBuffer
): ()
	local edge_count = edges.count

	if edge_count == 0 or width <= 0 or height <= 0 then
		return
	end

	local from_x, from_y, to_x, to_y = edges.from_x, edges.from_y, edges.to_x, edges.to_y
	local coverage = table.create(width, 0)
	local hit_x: { number } = table.create(edge_count, 0)
	local hit_dir: { number } = table.create(edge_count, 0)

	for py = 0, height - 1 do
		for index = 1, width do
			coverage[index] = 0
		end

		for sub = 0, SUB_SCANLINES - 1 do
			local sample_y = py + (sub + 0.5) / SUB_SCANLINES
			local hit_count = 0

			for edge = 1, edge_count do
				local y0, y1 = from_y[edge], to_y[edge]
				local direction = 0

				if y0 <= sample_y then
					if y1 > sample_y then
						direction = 1
					end
				elseif y1 <= sample_y then
					direction = -1
				end

				if direction ~= 0 then
					hit_count += 1
					hit_x[hit_count] = from_x[edge] + (sample_y - y0) * (to_x[edge] - from_x[edge]) / (y1 - y0)
					hit_dir[hit_count] = direction
				end
			end

			for index = 2, hit_count do
				local x = hit_x[index]
				local direction = hit_dir[index]
				local position = index - 1

				while position >= 1 and hit_x[position] > x do
					hit_x[position + 1] = hit_x[position]
					hit_dir[position + 1] = hit_dir[position]
					position -= 1
				end

				hit_x[position + 1] = x
				hit_dir[position + 1] = direction
			end

			local winding = 0
			local span_start = 0

			for index = 1, hit_count do
				local previous = winding
				winding += hit_dir[index]

				if previous == 0 and winding ~= 0 then
					span_start = hit_x[index]
				elseif previous ~= 0 and winding == 0 then
					add_span(coverage, width, span_start, hit_x[index])
				end
			end
		end

		local row_offset = (cell_y + py) * atlas_width + cell_x

		for px = 0, width - 1 do
			local amount = coverage[px + 1]

			if amount > 0 then
				local alpha = math.floor(amount * ALPHA_PER_SAMPLE + 0.5)

				if alpha > 255 then
					alpha = 255
				end

				if alpha > 0 then
					buffer.writeu32(atlas, (row_offset + px) * 4, WHITE_RGB + alpha * 16777216)
				end
			end
		end
	end
end

local destroy = function(self: Font): ()
	if not self.destroyed then
		self.destroyed = true
		self.texture:Destroy()
	end
end

font.new = function(atlas: Texture, glyphs: Types.GlyphInput, line_height: number, options: Options?): Font
	assert(not atlas.destroyed, "Font.New expects a live texture atlas")
	assert(line_height > 0, "Font.New expects a positive line height")

	local settings: Options = options or {}
	local normalized: GlyphMap = {}

	for key, glyph in glyphs do
		local codepoint = if type(key) == "number" then key else utf8.codepoint(key)
		normalized[codepoint] = glyph
	end

	return {
		texture = atlas,
		glyphs = normalized,
		line_height = math.floor(line_height),
		spacing = settings.spacing or 0,
		fallback = settings.fallback or QUESTION_MARK,
		destroyed = false,
		Destroy = destroy,
	}
end

font.from_buffer = function(
	font_buffer: buffer,
	pixel_size: number,
	charset: string?,
	options: Options?
): Font
	assert(buffer.len(font_buffer) >= 12, "Font.FromBuffer expects a non-empty binary font buffer")
	assert(
		pixel_size >= MIN_PIXEL_SIZE and pixel_size <= MAX_PIXEL_SIZE,
		`Font.FromBuffer pixel_size must be between {MIN_PIXEL_SIZE} and {MAX_PIXEL_SIZE}`
	)

	local size = math.floor(pixel_size)
	local file = parse_font(font_buffer)
	local scale = size / file.units_per_em
	local line_height = math.max(1, math.ceil((file.ascender - file.descender) * scale))

	local seen: { [number]: boolean } = {}
	local codepoints: { number } = {}

	for _, codepoint in utf8.codes(charset or DEFAULT_CHARSET) do
		if not seen[codepoint] then
			seen[codepoint] = true
			table.insert(codepoints, codepoint)
		end
	end

	if not seen[QUESTION_MARK] then
		table.insert(codepoints, QUESTION_MARK)
	end

	local cell_width = math.max(4, math.ceil(size * 1.5) + 2 * GLYPH_PADDING)
	local cell_height = line_height + 2 * GLYPH_PADDING
	local columns = math.max(1, MAX_ATLAS_WIDTH // cell_width)
	local atlas_width = columns * cell_width
	local atlas_height = math.ceil(#codepoints / columns) * cell_height

	assert(atlas_width * atlas_height <= MAX_ATLAS_PIXELS, "Font atlas is too large; reduce pixel_size or the charset")

	local atlas = buffer.create(atlas_width * atlas_height * BYTES_PER_PIXEL)
	local glyphs: GlyphMap = {}
	local edges: EdgeBuffer = {
		count = 0,
		from_x = {},
		from_y = {},
		to_x = {},
		to_y = {},
	}

	for position, codepoint in codepoints do
		local glyph_index = glyph_index_for(file, codepoint)
		local advance, bearing = horizontal_metrics(file, glyph_index)
		local x_min, y_min, x_max, y_max = glyph_bounds(file, glyph_index)

		local cell_x = ((position - 1) % columns) * cell_width + GLYPH_PADDING
		local cell_y = ((position - 1) // columns) * cell_height + GLYPH_PADDING
		local width = math.clamp(math.ceil((x_max - x_min) * scale), 0, cell_width - 2 * GLYPH_PADDING)
		local height = math.clamp(math.ceil((y_max - y_min) * scale), 0, line_height)

		local polygons: { { Point } } = {}

		for _, contour in read_outline(file, glyph_index, 0) do
			table.insert(polygons, contour_to_polygon(contour))
		end

		build_edges(edges, polygons, x_min, y_max, scale)
		rasterize_glyph(atlas, atlas_width, cell_x, cell_y, width, height, edges)

		glyphs[codepoint] = {
			x = cell_x + 1,
			y = cell_y + 1,
			width = width,
			height = height,
			xoffset = math.floor(bearing * scale),
			yoffset = math.floor((file.ascender - y_max) * scale),
			xadvance = math.floor(advance * scale + 0.5),
		}
	end

	return font.new(texture_module.new(atlas_width, atlas_height, atlas, false), glyphs, line_height, options)
end

font.from_string = function(font_data: string, pixel_size: number, charset: string?, options: Options?): Font
	assert(
		type(font_data) == "string" and #font_data >= 12,
		"Font.FromString expects a non-empty binary font string"
	)

	return font.from_buffer(buffer.fromstring(font_data), pixel_size, charset, options)
end

local layout_text = function(
	instance: Font,
	value: string,
	scale: number,
	x: number,
	y: number,
	context: Context?,
	tint: number?,
	viewport_x0: number,
	viewport_y0: number,
	viewport_x1: number,
	viewport_y1: number
): (number, number, number, number, number, number, number)
	local glyphs = instance.glyphs
	local fallback = glyphs[instance.fallback]
	local line_height = math.floor(instance.line_height * scale + 0.5)
	local spacing = instance.spacing * scale
	local space = glyphs[SPACE] or fallback
	local space_advance = if space ~= nil then (space.xadvance or space.width) else instance.line_height * 0.5
	local tab_advance = (space_advance * scale + spacing) * TAB_WIDTH_IN_SPACES

	local cursor_x, cursor_y = x, y
	local max_width = 0
	local line_count = 1
	local glyph_count = 0
	local touch_left, touch_top = math.huge, math.huge
	local touch_right, touch_bottom = -math.huge, -math.huge

	for _, codepoint in utf8.codes(value) do
		if codepoint == NEWLINE then
			local line_width = cursor_x - x

			if line_width > max_width then
				max_width = line_width
			end

			cursor_x = x
			cursor_y += line_height
			line_count += 1
		elseif codepoint == TAB then
			cursor_x += tab_advance
		else
			local glyph = glyphs[codepoint] or fallback

			if glyph ~= nil then
				glyph_count += 1

				if context ~= nil and glyph.width > 0 and glyph.height > 0 then
					local gx = math.floor(cursor_x + (glyph.xoffset or 0) * scale + 0.5)
					local gy = math.floor(cursor_y + (glyph.yoffset or 0) * scale + 0.5)
					local gw = math.max(1, math.floor(glyph.width * scale + 0.5))
					local gh = math.max(1, math.floor(glyph.height * scale + 0.5))
					local left, top, right, bottom = texture_module._DrawGlyph(
						context,
						instance.texture,
						glyph.x,
						glyph.y,
						glyph.width,
						glyph.height,
						gx,
						gy,
						gw,
						gh,
						tint or OPAQUE_WHITE,
						viewport_x0,
						viewport_y0,
						viewport_x1,
						viewport_y1
					)

					if right >= left then
						if left < touch_left then
							touch_left = left
						end
						if top < touch_top then
							touch_top = top
						end
						if right > touch_right then
							touch_right = right
						end
						if bottom > touch_bottom then
							touch_bottom = bottom
						end
					end
				end

				cursor_x += (glyph.xadvance or glyph.width) * scale + spacing
			end
		end
	end

	local line_width = cursor_x - x

	if line_width > max_width then
		max_width = line_width
	end

	return math.floor(max_width + 0.5),
		line_count * line_height,
		glyph_count,
		touch_left,
		touch_top,
		touch_right,
		touch_bottom
end

font.draw_text = function(
	context: Context,
	instance: Font,
	value: string,
	x: number,
	y: number,
	color32: number?,
	scale: number?
): (number, number)
	local resolved_scale = scale or 1
	local resolved_color = color32 or OPAQUE_WHITE

	assert(type(value) == "string", "DrawText expects a string")
	assert(resolved_scale > 0, "DrawText expects a positive scale")

	if context._destroyed or instance.destroyed then
		return 0, 0
	end

	local viewport_x0, viewport_y0, viewport_x1, viewport_y1 = clip.viewport(context)
	local width, height, glyph_count, touch_left, touch_top, touch_right, touch_bottom =
		layout_text(
			instance,
			value,
			resolved_scale,
			x,
			y,
			context,
			resolved_color,
			viewport_x0,
			viewport_y0,
			viewport_x1,
			viewport_y1
		)

	context.stats.text_glyphs += glyph_count

	if touch_right >= touch_left then
		damage.mark_rect(context, touch_left, touch_top, touch_right, touch_bottom)
	end

	return width, height
end

font.measure_text = function(instance: Font, value: string, scale: number?): (number, number)
	local resolved_scale = scale or 1

	assert(type(value) == "string", "MeasureText expects a string")
	assert(resolved_scale > 0, "MeasureText expects a positive scale")

	local width, height = layout_text(instance, value, resolved_scale, 0, 0, nil, nil, 0, 0, 0, 0)

	return width, height
end

font.destroy = destroy

font.New = font.new
font.FromBuffer = font.from_buffer
font.FromString = font.from_string
font.DrawText = font.draw_text
font.MeasureText = font.measure_text
font.Destroy = destroy

return font
