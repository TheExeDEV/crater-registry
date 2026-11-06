--!strict
--!native
--!optimize 2

--[==[
    The Separating Axis Theorem (SAT) module.

    Provides the core algorithms for testing collision between two convex
    shapes (typically OBBs) by projecting them onto a set of candidate
    separating axes and checking for overlap on each axis.

    If the shapes overlap on *all* axes, they are colliding; the axis with
    the smallest overlap (the Minimum Translation Vector) gives the
    smallest push to separate them.
]==]
type SAT = {
	--[==[
	    Computes the normalized axes of both shapes combined.
	    `left` and `right` are arrays of axis vectors for each shape.
	    Returns the concatenated, normalized list of all axes.
	]==]
	read compute_axises_pack: (self: SAT, left: { vector }, right: { vector }) -> { vector },

	--[==[
	    Computes the cross products of every axis from `left` with every
	    axis from `right`. These are the additional candidate separating
	    axes needed for 3D SAT (edge-edge collisions).
	    Returns normalized, non-degenerate cross products.
	]==]
	read compute_cross_products: (self: SAT, left: { vector }, right: { vector }) -> { vector },

	--[==[
	    Builds a `generator` bundling together everything needed to project
	    two shapes: their axes, half-extents, and centers.
	]==]
	read compute_generator: (
		self: SAT,
		left: { vector },
		right: { vector },
		half_left: vector,
		half_right: vector,
		center_left: vector,
		center_right: vector
	) -> generator,

	--[==[
	    Projects both shapes onto every axis in `generator` and returns a
	    `projection` describing distances and radii on each axis.
	]==]
	read compute_projection: (self: SAT, generator: generator) -> projection,

	--[==[
	    Given a `projection`, finds the axis with the smallest overlap and
	    returns the Minimum Translation Vector (axis + magnitude).
	    If any axis shows separation (overlap < 0), returns a degenerate
	    result indicating no collision.
	]==]
	read compute_mtv: (self: SAT, project: projection) -> mtv,
}

--[==[
    The result of projecting two shapes onto a set of axes.

    For each axis, `distance` is the absolute distance between the two
    centers projected on that axis, while `left_radius` and
    `right_radius` are the projection radii (half-widths) of each shape.
    The shapes overlap on a given axis iff
    `distance <= left_radius + right_radius`.
]==]
type projection = {
	--[==[
	    Absolute distance between the two centers projected on each axis.
	    Indexed in parallel with `pack`, `left_radius`, `right_radius`.
	]==]
	read distance: { number },

	--[==[
	    Projection radius of the left shape on each axis.
	]==]
	read left_radius: { number },

	--[==[
	    Projection radius of the right shape on each axis.
	]==]
	read right_radius: { number },

	--[==[
	    The candidate separating axes used for the projection:
	    shape axes followed by cross products of axis pairs.
	]==]
	read pack: { read vector },

	--[==[
	    Vector from the right center to the left center
	    (`center_left - center_right`).
	]==]
	read center: vector,
}

--[==[
    Bundles the parameters of two convex shapes needed for projection.

    Holds each shape's axes, half-extents, and center so that
    `compute_projection` can project both shapes onto a set of axes
    without re-passing the individual values.
]==]
type generator = {
	--[==[
	    Axes of the left shape (e.g. its local-space orientation vectors).
	]==]
	read left: { vector },

	--[==[
	    Axes of the right shape.
	]==]
	read right: { vector },

	--[==[
	    Half extents of the left shape along its own axes.
	]==]
	read half_left: vector,

	--[==[
	    Half extents of the right shape along its own axes.
	]==]
	read half_right: vector,

	--[==[
	    World-space center of the left shape.
	]==]
	read center_left: vector,

	--[==[
	    World-space center of the right shape.
	]==]
	read center_right: vector,
}

--[==[
    The Minimum Translation Vector (MTV) result.

    `axis` is the separating axis with the smallest overlap (the direction
    to push the shapes apart), and `mtv` is the magnitude of the overlap
    along that axis. If the shapes are not colliding, `mtv` is
    `-math.huge` and `axis` is `vector.zero`.
]==]
type mtv = {
	--[==[
	    The axis of minimum penetration (direction to separate the shapes).
	]==]
	read axis: vector,

	--[==[
	    The magnitude of overlap along `axis`; negative means no collision.
	]==]
	read mtv: number,
}

const SAT: SAT = table.freeze({
	compute_axises_pack = function(self: SAT, left: { vector }, right: { vector }): { vector }
		const result: { vector } = {}

		for _, axis_left in left do
			table.insert(result, vector.normalize(axis_left))
		end

		for _, axis_right in right do
			table.insert(result, vector.normalize(axis_right))
		end

		return result
	end,

	compute_cross_products = function(self: SAT, left: { vector }, right: { vector }): { vector }
		const result: { vector } = {}

		for _, left_axis in left do
			for _, right_axis in right do
				const new: vector = vector.cross(left_axis, right_axis)

				if vector.dot(new, new) > 1e-8 then
					table.insert(result, vector.normalize(new))
				end
			end
		end

		return result
	end,

	compute_generator = function(
		self: SAT,
		left: { vector },
		right: { vector },
		half_left: vector,
		half_right: vector,
		center_left: vector,
		center_right: vector
	): generator
		const generator = table.freeze({
			left = left,
			right = right,
			half_left = half_left,
			half_right = half_right,
			center_left = center_left,
			center_right = center_right,
		})

		return generator
	end,

	compute_projection = function(self: SAT, generator: generator): projection
		const axises_pack = self:compute_axises_pack(generator.left, generator.right)
		const cross_products = self:compute_cross_products(generator.left, generator.right)
		const pack = table.create(#axises_pack + #cross_products, vector.zero)

		table.move(axises_pack, 1, #axises_pack, 1, pack)
		table.move(cross_products, 1, #cross_products, #axises_pack + 1, pack)

		const center = generator.center_left - generator.center_right
		const half_left = generator.half_left
		const half_right = generator.half_right
		const left = generator.left
		const right = generator.right

		const projection = table.freeze({
			distance = {},
			left_radius = {},
			right_radius = {},
			pack = pack,
			center = center,
		})

		for _, axis in pack do
			table.insert(projection.distance, math.abs(vector.dot(center, axis)))

			table.insert(
				projection.left_radius,
				(half_left.x * math.abs(vector.dot(axis, left[1])))
					+ (half_left.y * math.abs(vector.dot(axis, left[2])))
					+ (half_left.z * math.abs(vector.dot(axis, left[3])))
			)

			table.insert(
				projection.right_radius,
				(half_right.x * math.abs(vector.dot(axis, right[1])))
					+ (half_right.y * math.abs(vector.dot(axis, right[2])))
					+ (half_right.z * math.abs(vector.dot(axis, right[3])))
			)
		end

		table.freeze(projection.distance)
		table.freeze(projection.left_radius)
		table.freeze(projection.right_radius)
		table.freeze(projection.pack)

		return projection
	end,

	compute_mtv = function(self: SAT, project: projection): mtv
		local min: number = math.huge
		local axis: vector = vector.zero

		for i, cross in project.pack do
			const overlap: number = project.left_radius[i] + project.right_radius[i] - project.distance[i]

			if overlap < 0 then
				return table.freeze({
					mtv = -math.huge,
					axis = -vector.zero,
				})
			end

			if overlap < min then
				min = overlap
				axis = cross

				if vector.dot(axis, project.center) < 0 then
					axis = -axis
				end
			end
		end

		return table.freeze({
			mtv = min,
			axis = axis,
		})
	end,
})

return SAT
