--!strict

const Event = require('../../common/signal/Event')

const private = { type = "itembehavior" }
const class: itembehavior = (Event :: event<enumitem_item_notification, itembehavior, itemcontext>):new({
	type = private.type,
})

do
	private.new = function(new: luaobject): ()
		const _new = new:as<<itembehavior>>(class.type)
	end

	private.new(class)
end

class:host(private.new)

return class
