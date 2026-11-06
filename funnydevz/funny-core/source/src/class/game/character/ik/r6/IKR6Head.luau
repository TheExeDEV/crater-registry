--!strict

const IKR6Limb = require('./IKR6Limb')
const IKR6HeadInfo = require('../../../../struct/game/IKR6HeadInfo')

const private = {type = "ikr6head"}
const class : ikr6head = IKR6Limb:new {
    type = private.type
}

do
    private.default_info = IKR6HeadInfo:new()

    private.new = function (new: luaobject)
		const new = new:as<<ikr6head>>(class.type)
		new:set_info(private.default_info)
    end

    private.new(class)
end

class:host(private.new)

return class
