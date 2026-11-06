--!strict

const Observer = require('../../core/Observer')
const Variable = require('../../core/Variable')
const ItemBehavior = require('./ItemBehavior')
const mtypes = require('../../../static/declare/mtypes')
const ftype = require('../../../static/ftype')

const private = { type = "iteminstance" }
const class: iteminstance = (Observer :: observer<enumitem_list_notification>):new({
	type = private.type,

	get_item = ftype:write(function(self: iteminstance): variable<item>
		return self:get <<variable<item>>> (private.item_key)
	end, Variable.type, private.type),

	get_behavior = ftype:write(function(self: iteminstance): itembehavior?
		return self:get <<itembehavior?>> (private.behavior_key)
	end, ftype:opt(ItemBehavior.type), private.type),

	set_behavior = ftype:write(function(self: iteminstance, to: itembehavior?): ()
		self:set(private.behavior_key, to)
	end, mtypes.never, private.type, ftype:opt(ItemBehavior.type)),
})

do
	private.item_key = newproxy()
	private.behavior_key = newproxy()

	private.new = function(new: luaobject)
		const new = new:as<<iteminstance>>(class.type)
		new:set(private.item_key, Variable:new())
		new:set(private.behavior_key, nil)
	end

	private.new(class)
end

class:host(private.new)

return class
