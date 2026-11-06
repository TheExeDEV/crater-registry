--!strict

const LuaObject = require('../../core/LuaObject')
const mtypes = require('../../../static/declare/mtypes')
const tables = require('../../../static/declare/tables')
const types = require('../../../static/declare/types')
const std = require('../../../extension/std')
const ftype = require('../../../static/ftype')

const private = {type = "stack"}
const class: stack = LuaObject:new({
	type = private.type,
	max = 10000,

	pick = ftype:write(function<T>(self: stack): T?
		const stack = private.stacks[self]
		const index = #stack
		const value = stack[index]
		stack[index] = nil
		return value
	end, ftype:opt(mtypes.anyt), private.type),

	put = ftype:write(function<T>(self: stack, item: T): ()
		const stack = private.stacks[self]

		if not std:check(#stack + 1 <= self.max, "stack limit capacity reached") then
			return
		end

		stack[#stack + 1] = item
	end, mtypes.never, private.type, mtypes.anyt),

	count = ftype:write(function(self: stack): number
		return #private.stacks[self]
	end, types.number, private.type),
})

class:host(function(new)
	const new = new:as <<stack>> (class.type)
	private.stacks[new] = {}
end)

do
	private.stacks = setmetatable({} :: { [stack]: { any } }, tables.__mode_ks)
end

return class
