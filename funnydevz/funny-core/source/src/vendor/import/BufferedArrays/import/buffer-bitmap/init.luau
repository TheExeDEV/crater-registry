--!strict
--!native
--!optimize 2

export type BitMap = buffer

export type Library = {
	read get: (of: BitMap, index: number, offset: number?) -> boolean,
	read set: (of: BitMap, index: number, offset: number?) -> (),
	read toggle: (of: BitMap, index: number, offset: number?) -> (),

	read clear: (of: BitMap, index: number, offset: number?) -> (),
	read find: (of: BitMap, from: number?, to: number?, offset: number?, inverse: boolean?) -> number?,
	read find_free: (of: BitMap, from: number?, to: number?, offset: number?, inverse: boolean?) -> number?,
}

const BYTE_BITS = 8
const BYTE_MASK = 0xFF

const M_MIN = math.min

const B32_BAND = bit32.band
const B32_BOR = bit32.bor
const B32_BNOT = bit32.bnot
const B32_LSHIFT = bit32.lshift
const B32_RSHIFT = bit32.rshift
const B32_BXOR = bit32.bxor
const B32_COUNTRZ = bit32.countrz
const B32_COUNTLZ = bit32.countlz

const WRITE_BYTE = buffer.writeu8
const READ_BYTE = buffer.readu8
const BUFFER_LEN = buffer.len

const function range_mask(first: number, last: number): number
	local mask = BYTE_MASK

	if first > 0 then
		mask = B32_BAND(mask, B32_BNOT(B32_LSHIFT(1, first) - 1))
	end

	if last < 7 then
		mask = B32_BAND(mask, B32_LSHIFT(1, last + 1) - 1)
	end

	return mask
end

const library: Library = table.freeze {
	get = function(of: BitMap, index: number, offset: number?): boolean
		return B32_BAND(READ_BYTE(of, B32_RSHIFT(index, 3) + (offset or 0)),  B32_LSHIFT(1, B32_BAND(index, 7))) ~= 0
	end,

	set = function(of: BitMap, index: number, offset: number?): ()
		const byte = B32_RSHIFT(index, 3) + (offset or 0)
		const value = READ_BYTE(of, byte)

    	WRITE_BYTE(of, byte, B32_BOR(value, B32_LSHIFT(1, B32_BAND(index, 7))))
	end,

	toggle = function(of: BitMap, index: number, offset: number?): ()
		const byte = B32_RSHIFT(index, 3) + (offset or 0)
		const value = READ_BYTE(of, byte)

    	WRITE_BYTE(of, byte, B32_BXOR(value, B32_LSHIFT(1, B32_BAND(index, 7))))
	end,

	clear = function(of: BitMap, index: number, offset: number?): ()
		const byte = B32_RSHIFT(index, 3) + (offset or 0)
		const value = READ_BYTE(of, byte)

		WRITE_BYTE(of, byte, B32_BAND(value, B32_BNOT( B32_LSHIFT(1, B32_BAND(index, 7)))))
	end,

	find = function(of: BitMap, from: number?, to: number?, offset: number?, inverse: boolean?): number?
		offset = offset or 0

		const max = BUFFER_LEN(of) * BYTE_BITS - 1
		const first = from and from > 0 and from or 0
		const last = M_MIN(to or max, max)

		if first > last then
			return nil
		end

		const first_byte = B32_RSHIFT(first, 3)
		const last_byte = B32_RSHIFT(last, 3)

		if not inverse then
			for byte = first_byte, last_byte do
				const value = B32_BAND(
					READ_BYTE(of, byte + offset),
					range_mask(
						if byte == first_byte then B32_BAND(first, 7) else 0,
						if byte == last_byte then B32_BAND(last, 7) else 7
					)
				)

				if value ~= 0 then
					return byte * BYTE_BITS + B32_COUNTRZ(value)
				end
			end
		else
			for byte = last_byte, first_byte, -1 do
				const value = B32_BAND(
					READ_BYTE(of, byte + offset),
					range_mask(
						if byte == first_byte then B32_BAND(first, 7) else 0,
						if byte == last_byte then B32_BAND(last, 7) else 7
					)
				)

				if value ~= 0 then
					return byte * BYTE_BITS + (7 - B32_COUNTLZ(B32_LSHIFT(value, 24)))
				end
			end
		end


		return nil
	end,

	find_free = function(of: BitMap, from: number?, to: number?, offset: number?, inverse: boolean?): number?
		offset = offset or 0

		const max = BUFFER_LEN(of) * BYTE_BITS - 1
	    const first = from and from > 0 and from or 0
		const last = M_MIN(to or max, max)

		if first > last then
			return nil
		end

		const first_byte = B32_RSHIFT(first, 3)
		const last_byte = B32_RSHIFT(last, 3)

		if not inverse then
			for byte = first_byte, last_byte do
				const value = READ_BYTE(of, byte + offset)
				const low = if byte == first_byte then B32_BAND(first, 7) else 0
				const high = if byte == last_byte then B32_BAND(last, 7) else 7
				const mask = range_mask(low, high)
				const free = B32_BAND(B32_BNOT(value), mask)

				if free ~= 0 then
					return byte * BYTE_BITS + B32_COUNTRZ(free)
				end
			end
		else
			for byte = last_byte, first_byte, -1 do
				const value = READ_BYTE(of, byte + offset)

				const low = if byte == first_byte then B32_BAND(first, 7) else 0
				const high = if byte == last_byte then B32_BAND(last, 7) else 7

				const mask = range_mask(low, high)
				const free = B32_BAND(B32_BNOT(value), mask)

				if free ~= 0 then
					return byte * BYTE_BITS + (7 - B32_COUNTLZ(B32_LSHIFT(free, 24)))
				end
			end
		end

		return nil
	end,
}

return library