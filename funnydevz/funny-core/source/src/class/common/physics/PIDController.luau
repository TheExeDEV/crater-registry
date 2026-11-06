--!strict

const KinematicController = require('./KinematicController')

const private = { type = "pidcontroller" }
const class: pidcontroller = (KinematicController :: kinematiccontroller):new({
	type = private.type,
	integral = 0,
	integral_limit = math.huge,
	derivative = 0,
})

return class
