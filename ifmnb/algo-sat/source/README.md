# Separating Axis Theorem (SAT)

A Luau module for collision detection between convex shapes (typically OBBs) using the Separating Axis Theorem.

## Overview

The Separating Axis Theorem states that two convex shapes are **not** colliding if there exists at least one axis along which their projections do not overlap. If their projections overlap on **every** candidate axis, the shapes are colliding.

This module provides the core algorithms:

1. **Compute axes** — gather and normalize all candidate separating axes (shape axes + cross products of axis pairs for 3D edge-edge collisions).
2. **Build a generator** — bundle both shapes' axes, half-extents, and centers.
3. **Project** — project both shapes onto every axis and compute distances and radii.
4. **MTV** — find the axis with the smallest overlap (Minimum Translation Vector) to separate the shapes.

## Types

### `SAT`

The module table exposing five methods:

| Method | Purpose |
|--------|---------|
| `compute_axises_pack(left, right)` | Normalized axes of both shapes combined. |
| `compute_cross_products(left, right)` | Cross products of every left axis with every right axis (3D edge-edge candidates). |
| `compute_generator(left, right, half_left, half_right, center_left, center_right)` | Bundles shape data into a `generator`. |
| `compute_projection(generator)` | Projects both shapes onto all axes; returns a `projection`. |
| `compute_mtv(project)` | Returns the Minimum Translation Vector (`mtv`) from a `projection`. |

### `generator`

Bundles the parameters of two convex shapes needed for projection:

| Field | Meaning |
|-------|---------|
| `left` | Axes of the left shape (e.g. local-space orientation vectors). |
| `right` | Axes of the right shape. |
| `half_left` | Half extents of the left shape along its axes. |
| `half_right` | Half extents of the right shape along its axes. |
| `center_left` | World-space center of the left shape. |
| `center_right` | World-space center of the right shape. |

### `projection`

The result of projecting two shapes onto a set of axes. For each axis:

* `distance` — absolute distance between the two centers projected on that axis.
* `left_radius` — projection radius (half-width) of the left shape.
* `right_radius` — projection radius (half-width) of the right shape.
* `pack` — the candidate separating axes used (shape axes followed by cross products).
* `center` — vector from the right center to the left center (`center_left - center_right`).

The shapes overlap on a given axis iff:
```
distance <= left_radius + right_radius
```

### `mtv`

The Minimum Translation Vector result:

| Field | Meaning |
|-------|---------|
| `axis` | The axis of minimum penetration (direction to separate the shapes). |
| `mtv` | The magnitude of overlap along `axis`; negative means no collision. |

## Usage example

```lua
--!strict

local SAT = require("algorithm-separating-axis-theoreme")

-- Build generators for two OBBs
local gen = SAT:compute_generator(
    leftAxes, rightAxes,
    halfLeft, halfRight,
    centerLeft, centerRight
)

-- Project onto all candidate axes
local proj = SAT:compute_projection(gen)

-- Get the minimum translation vector
local mtv = SAT:compute_mtv(proj)

if mtv.mtv >= 0 then
    -- Shapes are colliding; push apart along mtv.axis by mtv.mtv
    local push = mtv.axis * mtv.mtv
else
    -- No collision
end
```

## Notes

* All tables returned by the module methods are frozen (`table.freeze`).
* `compute_cross_products` skips degenerate cross products (dot product with itself <= 1e-8).
* The MTV axis is oriented so that `vector.dot(axis, project.center) >= 0`, pointing from the right shape toward the left shape.
* This is designed for convex shapes (OBBs). For concave shapes, decompose into convex parts first.

## License

See the parent repository `LICENSE.md`.
