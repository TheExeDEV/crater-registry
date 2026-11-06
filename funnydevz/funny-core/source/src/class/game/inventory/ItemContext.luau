--!strict

const Struct = require('../../core/Struct')
const ItemContextVariant = require('../../../enums/descriptor/ItemContext')

const class: itemcontext = Struct:new({
	type = "itemcontext",
	related = nil :: any,
	user = nil,
	context = ItemContextVariant.Primary,
	delta = 0,
})

return class
