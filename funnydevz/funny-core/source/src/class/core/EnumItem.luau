--!strict

const LuaObject = require('./LuaObject')
const Cryptography = require('../../vendor/import/Cryptography')

const class: enumitem = LuaObject:new({
	type = "enumitem",
	hashlink = "",
	name = "",
	enum = nil :: never,
})

class:host(function(new)
	const new = new:as<<enumitem>>(class.type)
	const tnew: any = new

	const enum = new.enum :: enumobject?
	tnew.hashlink =
		Cryptography.Hashing.Blake3.Digest(buffer.fromstring(if enum then `{enum.name}.{new.name}` else new.name))

	if not table.isfrozen(new) then
		table.freeze(new)
	end
end)

return class
