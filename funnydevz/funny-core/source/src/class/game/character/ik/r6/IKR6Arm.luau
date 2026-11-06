--!strict

const IKR6Limb = require('./IKR6Limb')
const IKR6ArmInfo = require('../../../../struct/game/IKR6ArmInfo')
const mtypes = require('../../../../../static/declare/mtypes')
const types = require('../../../../../static/declare/types')
const ftype = require('../../../../../static/ftype')

const private = {type = "ikr6arm"}
const class : ikr6arm = (IKR6Limb :: ikr6limb<ikr6arminfo>):new {
    type = private.type,
    absolute = false,

    get_target = ftype:write(function (self: ikr6arm) : vector
        return self:get <<vector>> (private.target_key) or vector.zero
    end, types.vector, private.type),

    set_target = ftype:write(function (self: ikr6arm, to: vector) : ()
        self:set(private.target_key, to)
    end, mtypes.never, private.type, types.vector)
}

do
    private.default_info = IKR6ArmInfo:new()
    private.target_key = newproxy()

    private.new = function (new: luaobject)
		const new = new:as<<ikr6arm>>(class.type)
		new:set_info(private.default_info)
    end

    private.new(class)
end

class:host(private.new)

return class
