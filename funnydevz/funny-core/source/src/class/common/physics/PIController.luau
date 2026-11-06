--!strict

const KinematicController = require('./KinematicController')

const private = { type = "picontroller" }
const class: picontroller = (KinematicController :: kinematiccontroller):new({
	type = private.type,
	integral = 0,
	integral_limit = math.huge,
})

return class
