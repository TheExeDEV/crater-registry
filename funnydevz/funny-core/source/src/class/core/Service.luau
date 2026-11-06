--!strict

const LuaObject = require('./LuaObject')

const class: service = LuaObject:new({
	type = "service",
	name = "*service-missed-name*",
	enabled = false,
})

return class
