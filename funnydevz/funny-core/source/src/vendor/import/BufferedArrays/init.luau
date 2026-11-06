--!native
--!optimize 2

const BitMap = require("@self/import/buffer-bitmap")

export type supported = number | nil | boolean | string | vector | Array
export type supported_types = "integer" | "boolean" | "vector" | "float" | "number" | "normal" | "short"
export type array_settings = "freeze" | "spoof" | "convert"

type Byte = number
type Index = number
type Type = number

export type Integer = number
export type Float = number

export type Array<unknown = supported> = buffer
export type Library = {
    read create:  (of: supported_types, max: number?) -> Array,

	read read: <T...>(of: Array, pos: number?) -> T...,
	read write: (of: Array, pos: number?, value: supported?) -> (),

	read put: (of: Array, value: supported, inverse: boolean?) -> number,
	read pick: <T...>(of: Array, inverse: boolean?) -> T...,
	read next: <T> (of: Array, pos: number?, inverted: boolean?) -> (number?, T),
    read iter: <T> (of: Array, previous: number?, inverted: boolean?) -> () -> (number?, T),

	read type: (of: Array) -> supported_types,
	read max: (of: Array) -> number,
	read count: (of: Array) -> number,
	read size: (of: Array, slot: boolean?) -> number,
	read set: (of: Array, setting: array_settings, to: boolean) -> (),
    read get: (of: Array, setting: array_settings) -> boolean,
    read dsize: (of: Array) -> number,
    read exist: (of: Array, pos: number?) -> boolean
}

game = game :: any
const RBX: any = game
const RBXR: any = RBX and RBX:GetService("RunService")
const DEBUG: boolean = RBXR and RBXR:IsStudio() or false

const STATIC_SIZE_SLOT_VECTOR: Byte = 12 -- f32 (1/3)
const STATIC_SIZE_SLOT_NORMAL: Byte = 4 -- u32 (rad f32 }{ f32)
const STATIC_SIZE_SLOT_BOOLEAN: Byte = 1 -- BitMap storage unit (1 bit per element)
const STATIC_SIZE_SLOT_INTEGER: Byte = 4
const STATIC_SIZE_SLOT_FLOAT: Byte = 4 -- f32 TODO f16
const STATIC_SIZE_SLOT_SHORT: Byte = 2 -- u16

const WRITE_INTEGER = buffer.writei32
const WRITE_FLOAT = buffer.writef32
const WRITE_DOUBLE = buffer.writef64
const WRITE_VECTOR = buffer.writef32
const WRITE_NORMAL = buffer.writeu32
const WRITE_CHAR = buffer.writeu8
const WRITE_SHORT = buffer.writeu16
const WRITE_UINTEGER = buffer.writeu32

const READ_INTEGER = buffer.readi32
const READ_FLOAT = buffer.readf32
const READ_DOUBLE = buffer.readf64
const READ_VECTOR = buffer.readf32
const READ_NORMAL = buffer.readu32
const READ_CHAR = buffer.readu8
const READ_SHORT = buffer.readu16
const READ_UINTEGER = buffer.readu32

const B32_BAND = bit32.band
const B32_RSHIFT = bit32.rshift

const M_ROUND = math.round
const M_CEIL = math.ceil
const M_ABSOLUTE = math.abs
const M_SQRT = math.sqrt

const BM_GET = BitMap.get
const BM_SET = BitMap.set
const BM_CLEAR = BitMap.clear
const BM_FIND = BitMap.find
const BM_FIND_FREE = BitMap.find_free

const ARRAY_SETTINGS: Index = 0
const SETTINGS_FREEZE: Index = 0
const SETTINGS_NULLIFE: Index = 1 -- unused
const SETTINGS_SPOOF: Index = 2
const SETTINGS_CHANGED: Index = 3 -- unused
const SETTINGS_CONVERT: Index = 4

const ARRAY_TYPE: Index = 1 -- u8
const ARRAY_MAX: Index = 5 -- u32
const ARRAY_OFFSET: Index = 9 -- u32
const ARRAY_BITMAP: Index = 13 -- BitMap ceil N/8
const ARRAY_STATIC_PART_ENDS_AT: Index = ARRAY_BITMAP

const LIBRARY_INDEX_STARTS_AT = 1
const LIBRARY_DEFAULT_MAX = LIBRARY_INDEX_STARTS_AT + 1
const LIBRARY_OFFSET_AFTER_HEADER: Index = 0
const LIBRARY_OFFSET_BITMAP = 0

const TYPE_VECTOR: Type = 0
const TYPE_INTEGER: Type = 1
const TYPE_FLOAT: Type = 6
const TYPE_BOOLEAN: Type = 3
const TYPE_STRING: Type = 5
const TYPE_DOUBLE: Type = 7
const TYPE_NORMAL: Type = 8
const TYPE_SHORT: Type = 9

const STYPE_VECTOR: "vector" = "vector"
const STYPE_STRING: "string" = "string"
const STYPE_NUMBER: "double" = "double"
const STYPE_FLOAT: "float" = "float"
const STYPE_INTEGER: "integer" = "integer"
const STYPE_NORMAL: "normal" = "normal"
const STYPE_BOOLEAN: "boolean" = "boolean"
const STYPE_SHORT: "short" = "short"
const STYPE_NIL: "nil" = "nil"
const SPEC_DUMMY: "dummy" = "dummy"

const MAP = table.freeze {
	[STYPE_VECTOR] = TYPE_VECTOR,
	[STYPE_STRING] = TYPE_STRING,
	[STYPE_NUMBER] = TYPE_DOUBLE,
	[STYPE_INTEGER] = TYPE_INTEGER,
	[STYPE_FLOAT] = TYPE_FLOAT,
	[STYPE_BOOLEAN] = TYPE_BOOLEAN,
    [STYPE_NORMAL] = TYPE_NORMAL,
    [STYPE_SHORT] = TYPE_SHORT,
    [STYPE_NIL] = SPEC_DUMMY,

	[TYPE_BOOLEAN] = STATIC_SIZE_SLOT_BOOLEAN,
	[TYPE_FLOAT] = STATIC_SIZE_SLOT_FLOAT,
	[TYPE_INTEGER] = STATIC_SIZE_SLOT_INTEGER,
	[TYPE_VECTOR] = STATIC_SIZE_SLOT_VECTOR,
    [TYPE_NORMAL] = STATIC_SIZE_SLOT_NORMAL,
    [TYPE_SHORT] = STATIC_SIZE_SLOT_SHORT,

    [tostring(TYPE_BOOLEAN)] = STYPE_BOOLEAN,
    [tostring(TYPE_FLOAT)] = STYPE_FLOAT,
    [tostring(TYPE_INTEGER)] = STYPE_INTEGER,
    [tostring(TYPE_DOUBLE)] = STYPE_NUMBER,
    [tostring(TYPE_NORMAL)] = STYPE_NORMAL,
    [tostring(TYPE_VECTOR)] = STYPE_VECTOR,
    [tostring(TYPE_STRING)] = STYPE_STRING,
    [tostring(TYPE_SHORT)] = STYPE_SHORT,

    nullify = SETTINGS_NULLIFE,
    freeze = SETTINGS_FREEZE,
    spoof = SETTINGS_SPOOF,
    changed = SETTINGS_CHANGED,
    convert = SETTINGS_CONVERT
} :: { [string | number]: number }

const BYTE_POP_SEARCH = function(tbl: { Byte })
	for i = 1, #tbl do
		local count = 0
		local n = i - 1

		while n > 0 do
			count += B32_BAND(n, 1)
			n = B32_RSHIFT(n, 1)
		end

		tbl[i] = count
	end

	table.freeze(tbl)

	return tbl
end

--const POPCOUNT_8: {Byte} = BYTE_POP_SEARCH(table.create(2 ^ 8, 0))
const POPCOUNT_16: {Byte} = BYTE_POP_SEARCH(table.create(2 ^ 16, 0))
--const POPCOUNT_32: {Byte} = BYTE_POP_SEARCH(table.create(2 ^ 32, 0))
--const POPCOUNT_64: {Byte} = BYTE_POP_SEARCH(table.create(2 ^ 64, 0))



local self: Library
const library: Library = {
	create = function(of: supported_types, max: number?): Array
		max = max or LIBRARY_DEFAULT_MAX

		const array_type = MAP[of]
		const array_bitmap_size = M_CEIL(max / 8)
        const array_bitmap_size_scaled = M_CEIL(array_bitmap_size / 4) * 4
        local new: Array

        if of == STYPE_BOOLEAN then
            new = buffer.create(
                ARRAY_STATIC_PART_ENDS_AT +
                LIBRARY_OFFSET_AFTER_HEADER +
                LIBRARY_OFFSET_BITMAP + 
                array_bitmap_size_scaled            
            )
        else
            new = buffer.create(
                ARRAY_STATIC_PART_ENDS_AT +
                LIBRARY_OFFSET_AFTER_HEADER + 
                LIBRARY_OFFSET_BITMAP + 
                array_bitmap_size_scaled + 
                MAP[array_type] * max
            )
        end

        WRITE_UINTEGER(new, ARRAY_OFFSET, ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP + array_bitmap_size_scaled + LIBRARY_OFFSET_AFTER_HEADER + LIBRARY_OFFSET_BITMAP)
		WRITE_INTEGER(new, ARRAY_MAX, max)
		WRITE_CHAR(new, ARRAY_TYPE, array_type)

		return new
	end,

	read = function <T...>(of: Array, pos: number?): T...
        pos = pos or LIBRARY_INDEX_STARTS_AT

        const index = pos - LIBRARY_INDEX_STARTS_AT
        const unknown = READ_CHAR(of, ARRAY_TYPE)

        if unknown == TYPE_BOOLEAN then
            return BM_GET(of, index, ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP)
        end

        if not BM_GET(of, index, ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP) then
            if BM_GET(of, SETTINGS_SPOOF, ARRAY_SETTINGS) then
                const bit_index = BM_FIND(of, 0, READ_INTEGER(of, ARRAY_MAX) - LIBRARY_INDEX_STARTS_AT, ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP, false)
                if bit_index then
                    return self.read(of, bit_index + LIBRARY_INDEX_STARTS_AT)
                end
            end
            return nil
        end

        const label = index * MAP[unknown]
        const offset = READ_UINTEGER(of, ARRAY_OFFSET)
        const sector = offset + label

        if unknown == TYPE_FLOAT then return READ_FLOAT(of, sector)
        elseif unknown == TYPE_INTEGER then return READ_INTEGER(of, sector)
        elseif unknown == TYPE_SHORT then return READ_SHORT(of, sector)
        elseif unknown == TYPE_DOUBLE then return READ_DOUBLE(of, sector)
        elseif unknown == TYPE_NORMAL then 
            const p = READ_NORMAL(of, sector)
            const u = B32_BAND(p, 0xFFFF)
            const v = B32_RSHIFT(p, 16)

            local x = u / 65535 * 2 - 1
            local y = v / 65535 * 2 - 1
            local z = 1 - M_ABSOLUTE(x) - M_ABSOLUTE(y)

            if z < 0 then
                const old_x = x
                const old_y = y

                x = (1 - M_ABSOLUTE(old_y)) * (old_x >= 0 and 1 or -1)
                y = (1 - M_ABSOLUTE(old_x)) * (old_y >= 0 and 1 or -1)
            end

            if BM_GET(of, SETTINGS_CONVERT, ARRAY_SETTINGS) then
                return x,y,z
            else
                return vector.create(x, y, z)
            end
        elseif unknown == TYPE_VECTOR then
            const slot_size = STATIC_SIZE_SLOT_VECTOR / 3
            const x = READ_VECTOR(of, sector)
            const y = READ_VECTOR(of, sector + slot_size)
            const z = READ_VECTOR(of, sector + slot_size * 2)

            if BM_GET(of, SETTINGS_CONVERT, ARRAY_SETTINGS) then
                return x,y,z
            else
                return vector.create(x, y, z)
            end
        end

        return nil
    end,

	write = function(of: Array, pos: number?, value: supported?): ()
        if BM_GET(of, SETTINGS_FREEZE, ARRAY_SETTINGS) then
            error("cannot write to frozen array")
        end
        
        pos = pos or LIBRARY_INDEX_STARTS_AT

        const index = pos - LIBRARY_INDEX_STARTS_AT
        const unknown = READ_CHAR(of, ARRAY_TYPE)

        if value then
            BM_SET(of, index, ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP)
        else
            BM_CLEAR(of, index, ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP)
        end

        if unknown == TYPE_BOOLEAN then return end

        const label = index * MAP[unknown]
        const offset = READ_UINTEGER(of, ARRAY_OFFSET)
        const sector = offset + label

        if unknown == TYPE_FLOAT then WRITE_FLOAT(of, sector, value :: number or 0)
            return
        elseif unknown == TYPE_INTEGER then WRITE_INTEGER(of, sector, value :: number or 0)
            return
        elseif unknown == TYPE_DOUBLE then WRITE_DOUBLE(of, sector, value :: number or 0)
            return
        elseif unknown == TYPE_SHORT then WRITE_SHORT(of, sector, value :: number or 0)
            return

        elseif unknown == TYPE_NORMAL then 
            const var = (value or vector.zero) :: vector
            const length = M_SQRT(var.x * var.x + var.y * var.y + var.z * var.z)

            if length == 0 then 
                WRITE_NORMAL(of, sector, 0)
                return 
            end

            local x = var.x / length
            local y = var.y / length
            local z = var.z / length

            const inv_l = 1 / (M_ABSOLUTE(x) + M_ABSOLUTE(y) + M_ABSOLUTE(z))
            x *= inv_l
            y *= inv_l
            z *= inv_l

            if z < 0 then
                const old = x
                x = (1 - M_ABSOLUTE(y)) * (old >= 0 and 1 or -1)
                y = (1 - M_ABSOLUTE(old)) * (y >= 0 and 1 or -1)
            end

            const u = M_ROUND((x * 0.5 + 0.5) * 65535)
            const v = M_ROUND((y * 0.5 + 0.5) * 65535)
            const p = bit32.bor(u,bit32.lshift(v, 16))

            WRITE_NORMAL(of, sector, p)
            return
        elseif unknown == TYPE_VECTOR then
            const slot_size = STATIC_SIZE_SLOT_VECTOR / 3
            const var = (value or vector.zero) :: vector

            WRITE_VECTOR(of, sector, var.x)
            WRITE_VECTOR(of, sector + slot_size, var.y)
            WRITE_VECTOR(of, sector + slot_size * 2, var.z)

            return
        end

        return
	end,

	pick = function <T...> (of: Array, inverse: boolean?): T...
		const index = BM_FIND(of, 0, READ_INTEGER(of, ARRAY_MAX) - LIBRARY_INDEX_STARTS_AT, ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP, inverse)
		return index and self.read(of, index + LIBRARY_INDEX_STARTS_AT) or nil
	end,

	put = function(of: Array, value: supported, inverse: boolean?): number
		const index = assert (BM_FIND_FREE(of, 0, READ_INTEGER(of, ARRAY_MAX) - LIBRARY_INDEX_STARTS_AT, ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP, inverse), "array is full")
		const position = index + LIBRARY_INDEX_STARTS_AT
        self.write(of, position, value)
        return position
	end,

	next = function <T...> (of: Array, previous: number?, inverted: boolean?): (number?, T...)
        const max = READ_INTEGER(of, ARRAY_MAX) - LIBRARY_INDEX_STARTS_AT

        local from: number
        local to: number

        if previous == nil then
            from = 0
            to = max
        else
            const previous_index = previous - LIBRARY_INDEX_STARTS_AT

            if inverted then
                from = 0
                to = previous_index - 1
            else
                from = previous_index + 1
                to = max
            end
        end

        if from < 0 or from > max or to < 0 or to > max or from > to then
            return nil, nil
        end

        const index = BM_FIND(
            of,
            from,
            to,
            ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP,
            inverted
        )

        if not index then
            return nil, nil
        end

        const position = index + LIBRARY_INDEX_STARTS_AT
        return position, self.read(of, position)
	end,

    iter = function <T...> (of: Array, previous: number?, inverted: boolean?): () -> (number?, T...)
        local post = previous
        
        local cached_T = READ_CHAR(of, ARRAY_TYPE)
        local cached_offset = READ_UINTEGER(of, ARRAY_OFFSET)
        local cached_type_size = MAP[cached_T]
        local bitmap_offset = ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP
        local max_index = READ_INTEGER(of, ARRAY_MAX) - LIBRARY_INDEX_STARTS_AT

        return function()
            local from: number
            local to: number

            if post == nil then
                from = 0
                to = max_index
            else
                local prev_idx = post - LIBRARY_INDEX_STARTS_AT
                if inverted then
                    from = 0
                    to = prev_idx - 1
                else
                    from = prev_idx + 1
                    to = max_index
                end
            end

            if from < 0 or from > max_index or to < 0 or to > max_index or from > to then
                return nil, nil
            end

            const index = BM_FIND(of, from, to, bitmap_offset, inverted)
            if not index then return nil, nil end

            const position = index + LIBRARY_INDEX_STARTS_AT
            const sector = cached_offset + index * cached_type_size
            local value: supported?
            
            if cached_T == TYPE_INTEGER then value = READ_INTEGER(of, sector) :: any
            elseif cached_T == TYPE_FLOAT then value = READ_FLOAT(of, sector) :: any
            elseif cached_T == TYPE_DOUBLE then value = READ_DOUBLE(of, sector) :: any
            elseif cached_T == TYPE_SHORT then value = READ_SHORT(of, sector) :: any
            elseif cached_T == TYPE_NORMAL then 
                local p = READ_NORMAL(of, sector)
                local u = B32_BAND(p, 0xFFFF)
                local v = B32_RSHIFT(p, 16)
                local x = u / 65535 * 2 - 1
                local y = v / 65535 * 2 - 1
                local z = 1 - M_ABSOLUTE(x) - M_ABSOLUTE(y)
                if z < 0 then
                    local old_x, old_y = x, y
                    x = (1 - M_ABSOLUTE(old_y)) * (old_x >= 0 and 1 or -1)
                    y = (1 - M_ABSOLUTE(old_x)) * (old_y >= 0 and 1 or -1)
                end
                value = vector.create(x, y, z) :: any
            elseif cached_T == TYPE_VECTOR then
                local slot_size = STATIC_SIZE_SLOT_VECTOR / 3
                value = vector.create(READ_VECTOR(of, sector), READ_VECTOR(of, sector + slot_size), READ_VECTOR(of, sector + slot_size * 2)) :: any
            elseif cached_T == TYPE_BOOLEAN then
                value = BM_GET(of, index, bitmap_offset) :: any
            end

            post = position
            return position, value
        end
    end,

	type = function(of: Array): supported_types
        return MAP[tostring(READ_CHAR(of, ARRAY_TYPE))] :: any
	end,

	count = function(of: Array): number
        local total_count = 0

        const array_bitmap_offset = ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP
        const u32_count = B32_RSHIFT(READ_INTEGER(of, ARRAY_MAX) + 31, 5)

        for i = 0, u32_count - 1 do
            const val = READ_UINTEGER(of, array_bitmap_offset + i * 4)
            total_count += POPCOUNT_16[bit32.band(val, 0xFFFF) + 1] + POPCOUNT_16[bit32.rshift(val, 16) + 1]
        end

        BM_CLEAR(of, SETTINGS_CHANGED, ARRAY_SETTINGS)
        return total_count
    end,

    max = function(of: Array): number
         return READ_INTEGER(of, ARRAY_MAX)
    end,

	size = function(of: Array, slot: boolean?): number
        return slot and MAP[MAP[READ_CHAR(of, ARRAY_TYPE)]] or buffer.len(of)
    end,

	set = function(of: Array, setting: array_settings, to: boolean): ()
        if BM_GET(of, SETTINGS_FREEZE, ARRAY_SETTINGS) then
            error("cannot modify settings of frozen array")
        end

        if to then
            BM_SET(of, assert(MAP[setting], `unknown {setting}`), ARRAY_SETTINGS)
        else
            BM_CLEAR(of, assert(MAP[setting], `unknown {setting}`), ARRAY_SETTINGS)
        end
    end,

    get = function(of: Array, setting: array_settings): boolean
        return BM_GET(of, MAP[setting], ARRAY_SETTINGS)
    end,

    dsize = function(of: Array): number
        return M_CEIL(READ_INTEGER(of, ARRAY_MAX) / 8) + LIBRARY_OFFSET_AFTER_HEADER + LIBRARY_OFFSET_BITMAP
    end,

    exist = function (of: Array, pos: number?) : boolean
        pos = pos or LIBRARY_INDEX_STARTS_AT

        const index = pos - LIBRARY_INDEX_STARTS_AT
        const unknown = READ_CHAR(of, ARRAY_TYPE)

        if unknown == TYPE_BOOLEAN then
            if BM_GET(of, index, ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP) then 
                return true
            else
                return false
            end
        end

        if not BM_GET(of, index, ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP) then
            if BM_GET(of, SETTINGS_SPOOF, ARRAY_SETTINGS) then
                const bit_index = BM_FIND(
                    of,
                    0,
                    READ_INTEGER(of, ARRAY_MAX) - LIBRARY_INDEX_STARTS_AT,
                    ARRAY_BITMAP + LIBRARY_OFFSET_BITMAP,
                    false
                )
                if bit_index then
                    return self.exist(of, bit_index + LIBRARY_INDEX_STARTS_AT)
                end
            end
        end

        return false
    end
}

table.freeze(library)

if DEBUG then
    print [[ For buffered arrays (ifmnb/array-buffer), 
    
    DEBUG mod is always active in rbx studio with increased protection against incorrect actions with arrays.
    Every array operation is checked for correct type, position, and value. 
    Optimization can be HEAVILY affected by these checks (from 3.27~ sec effectively to 16 sec)
    (Except runtime settings checks)
    
    These checks are disabled in the production code. (!)
    ]]

    const debug_library = setmetatable({}, table.freeze {__index = library})

    debug_library.write = function(of: Array, pos: number?, value: supported?)
		assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)

        if pos then
            assert(type(pos) == "number", `position must be a number, got {type(pos)}`)
            assert(pos >= LIBRARY_INDEX_STARTS_AT , `position {pos} is out of bounds for array, indexes starts at {LIBRARY_INDEX_STARTS_AT}`)
            assert(pos <= library.max(of), `position {pos} is out of bounds for array with max {library.max(of)}`)
        end

        assert(MAP[type(value)] ~= nil, `value of type {type(value)} is not supported`)

        return library.write(of, pos, value)
    end

    debug_library.read = function(of: Array, pos: number?)
		assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)

        if pos then
            assert(type(pos) == "number", `position must be a number, got {type(pos)}`)
            assert(pos >= LIBRARY_INDEX_STARTS_AT , `position {pos} is out of bounds for array, indexes starts at {LIBRARY_INDEX_STARTS_AT}`)
            assert(pos <= library.max(of), `position {pos} is out of bounds for array with max {library.max(of)}`)
        end

        return library.read(of, pos)
    end

    debug_library.type = function(of: Array): supported_types
		assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
        return assert (library.type(of), "array damaged, error reading type")
    end

    debug_library.set = function(of: Array, setting: array_settings, to: boolean): ()
        assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
        assert(MAP[setting], `unknown setting {setting}`)
        assert(type(setting) == "string", `setting must be a string, got {type(setting)}`)
        assert(type(to) == "boolean", `to must be a boolean, got {type(to)}`)

        return library.set(of, setting, to)
    end

    debug_library.get = function(of: Array, setting: array_settings): boolean
        assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
        assert(MAP[setting], `unknown setting {setting}`)
        assert(type(setting) == "string", `setting must be a string, got {type(setting)}`)

        return library.get(of, setting)
    end

    debug_library.dsize = function(of: Array): number
        assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
        return library.dsize(of)
    end

    debug_library.max = function(of: Array): number
        assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
        return library.max(of)
    end

    debug_library.count = function(of: Array): number
        assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
        return library.count(of)
    end

    debug_library.next = function(of: Array, previous: number?, inverted: boolean?): (number?, supported)
        assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
       
        if previous then
            assert(type(previous) == "number", `previous must be a number, got {type(previous)}`)
            assert(previous >= LIBRARY_INDEX_STARTS_AT , `previous {previous} is out of bounds for array, indexes starts at {LIBRARY_INDEX_STARTS_AT}`)
            assert(previous <= library.max(of), `previous {previous} is out of bounds for array with max {library.max(of)}`)
        end
       
        if inverted then
            assert(type(inverted) == "boolean", `inverted must be a boolean, got {type(inverted)}`)
        end

        return library.next(of, previous, inverted)
    end

    debug_library.iter = function(of: Array, previous: number?, inverted: boolean?): () -> (number?, supported)
        assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
       
        if previous then
            assert(type(previous) == "number", `previous must be a number, got {type(previous)}`)
            assert(previous >= LIBRARY_INDEX_STARTS_AT , `previous {previous} is out of bounds for array, indexes starts at {LIBRARY_INDEX_STARTS_AT}`)
            assert(previous <= library.max(of), `previous {previous} is out of bounds for array with max {library.max(of)}`)
        end
       
        if inverted then
            assert(type(inverted) == "boolean", `inverted must be a boolean, got {type(inverted)}`)
        end

        return library.iter(of, previous, inverted)
    end

    debug_library.put = function(of: Array, value: supported, inverse: boolean?): number
        assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
        assert(MAP[type(value)] ~= nil, `value of type {type(value)} is not supported`)
       
        if inverse then
            assert(type(inverse) == "boolean", `inverse must be a boolean, got {type(inverse)}`)
        end

        return library.put(of, value, inverse)
    end

    debug_library.pick = function(of: Array, inverse: boolean?)
        assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
       
        if inverse then
            assert(type(inverse) == "boolean", `inverse must be a boolean, got {type(inverse)}`)
        end

        return library.pick(of, inverse)
    end

    debug_library.size = function(of: Array, slot: boolean?): number
        assert(type(of) == "buffer", `of must be a buffer, got {type(of)}`)
       
        if slot then
            assert(type(slot) == "boolean", `slot must be a boolean, got {type(slot)}`)
        end

        return library.size(of, slot)
    end

    debug_library.create = function(of: supported_types, max: number?): Array
        assert(type(of) == "string", `of must be a string, got {type(of)}`)
        assert(MAP[of], `unknown type {of}`)
       
        if max then
            assert(type(max) == "number", `max must be a number, got {type(max)}`)
            assert(max >= LIBRARY_INDEX_STARTS_AT, `max {max} is invalid for array creation`)
        end

        return library.create(of, max)
    end

    table.freeze(debug_library)

    return debug_library :: Library
end

self = library
return library