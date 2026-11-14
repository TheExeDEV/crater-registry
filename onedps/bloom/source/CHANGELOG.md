# Changelog

## 1.5.0 - Rewrite

### Changed

- The whole library was rewritten around one flat RGBA framebuffer. Tiles now exist only to present that buffer through `EditableImage`, and every primitive clips once, writes tight loops, and marks one exact damage rectangle.
- `DrawPixel` is minimal again: floor, viewport check, one `writeu32`, one bounds update. The duplicated damage block and the hidden per-pixel caches are gone.
- Exact per-tile damage replaced the 16-mark escalation heuristic. Uploads use the full tile only when the damaged rectangle covers it.
- The TTF rasteriser uses scanline edge intersections instead of four winding tests per pixel. Glyph output can differ slightly from 1.5.0 in antialiasing detail.
- Scaled texture blits precompute column and row sampling tables; texture draws and shaders use specialised 1:1, alpha, tinted/opacity and scaled paths with hoisted locals.
- `Resize` is atomic: new resources are built first. A failure leaves the old canvas and its picture usable.
- `Update`/`UpdateAsync` share one upload path with a generation guard, so stale async work cannot upload into a new tile generation. Async updates batch up to 16 tiles per scheduler task, and both paths visit only tiles on the dirty-tile list instead of scanning the whole grid.
- `DrawText` hoists per-call text invariants and blits 1:1 glyphs through a dedicated fast path; scaled glyphs keep the general texture path.
- The public API and documented behaviour are unchanged apart from the fixes below.

### Fixed

- Removed the read-only caches in `EachPixel`, `DrawText` and `DrawTriangle`. Repeated calls always execute.
- `EachPixel` marks the exact bounding box of the pixels that actually changed, not the whole visited rectangle. A read-only pass schedules no upload and is never cached.
- Pipeline stages are isolated with `pcall`: a failing stage warns and the remaining stages still run.
- Custom shader errors propagate, and rows processed before the error stay marked for the next upload.
- Triangles and glyphs mark the rectangle actually written, not the vertex or glyph box.
- `Clear(0)` always wins over an earlier opaque clear; `GetBuffer()` still disables the repeated same-colour clear shortcut.

### Added

- `DrawCircle` and `DrawCircleAA` draw filled circles; the AA variant blends a one-pixel edge.
- `DrawPolygon` fills a convex polygon as a triangle fan from an array of points or flat coordinates.
- Tiles no longer keep a second CPU copy of their pixels: uploads stage each tile through one reusable buffer sized to the largest tile.

## 1.1.0 - Optimization

### Added

- `src/row.luau`: reusable solid-row buffer shared by rectangles, lines, triangles and clear.

### Changed

- Runtime speedups across drawing, textures, shaders and scheduling:
  - `DrawTriangle` uses an allocation-free scanline fill.
  - `DrawLineAA` uses a per-context coverage buffer with dense per-row spans instead of a global hash table.
  - `DrawTexture` has a 1:1 fast path (`buffer.copy`), inlined alpha checks and precomputed tint scales.
  - `Color4.BlendOver` uses a single division and early returns.
  - Pipeline stages are cached in a snapshot and idle `Async.Step` returns immediately.
- Tile labels now derive `Position`/`Size` from the reference label's scale, offset and anchor point, so scaled or anchored templates stay aligned. The reference geometry is captured once per resource rebuild and reused by every tile.

## 1.0.1 - Additionals

- Some rewrites to more readable code

## 1.0.0 - Release

### Added

- Textures
- Shaders
- Fonts
- Pipeline
- Support

### Changed

- Switching to [crater](https://theexedev.github.io/crater-registry/) instead of wally
- Rewrite architecture to be more closely to OpenGL
- Rewrited elements