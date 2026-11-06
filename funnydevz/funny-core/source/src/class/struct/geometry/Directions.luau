--!strict
--!native
--!optimize 2
const GeoVolume = require('./GeoVolume')
const types = require('../../../static/declare/types')
const ftype = require('../../../static/ftype')

const tname = "directions"
const class : directions = GeoVolume:new {
    type = tname,

    right = vector.zero,
    up = vector.zero,
    front = vector.zero,

    to_vector = ftype:write(function (self: directions) : vector
	    return vector.create(vector.magnitude(self.right), vector.magnitude(self.up), vector.magnitude(self.front))
    end, types.vector, tname),

    to_basis = ftype:write(function (self: directions) : basis
        const Basis: basis = require('./Basis'):: any
        return Basis:new({ rotation = self })
    end, "basis", tname),
}

return class
