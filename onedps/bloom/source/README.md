

# Bloom

Bloom is a low-level graphics library for Roblox built around `EditableImage` and `buffer`. The API is inspired by OpenGL's context/state/pipeline model, but it does **not** run GPU shaders. It keeps RGBA pixels in a Luau buffer and uploads changed regions to Roblox `EditableImage` objects.

## Quick start

```lua
local Bloom = require(path.to.Bloom)
local Color4 = Bloom.GetColor4()

local canvas = Bloom.Create(
    Vector2.new(512, 512),
    screenGui,
    imageTemplate,
    {
        tile_size = 512,
        async_budget = 0.002,
        clear_color = Color4.New32Bit(18, 24, 32, 255),
    }
)

canvas:BeginFrame()
canvas:DrawRectangle(20, 20, 140, 90, Color4.New32Bit(40, 180, 255, 255))
canvas:DrawLine(1, 1, 512, 512, Color4.New32Bit(255, 255, 255, 255))
canvas:EndFrame(true)
```

Enable **Experience Settings → Security → Allow Mesh / Image APIs** for published experiences. `Bloom.Create` probes the API first and raises a descriptive error when it is disabled; call `Bloom.CheckSupport()` (returns `{ supported, status, message, details }`, where `status` is `"supported"`, `"disabled"` or `"out_of_memory"`) or `Bloom.IsSupported()` to check without creating a canvas. Roblox restricts editable image access and memory use:

- every `EditableImage` is at most 1024×1024, so Bloom splits larger framebuffers into tiles (`tile_size`, default 1024);
- `AssetService:CreateEditableImage()` returns `nil` when the device's editable memory budget is exhausted - Bloom then raises a clear error and releases the tiles it already created;
- only one `EditableImage` is updated per frame on the display side, so N dirty tiles may need N frames to appear.

`parent` may be any GUI container (`Frame`, `ScreenGui`, …). `ClipsDescendants` is only set when `auto_clip` is on and the parent is a `GuiObject`. Without `parent`/`reference` the context renders off-screen.

## Core model

- **Context** - `Bloom.Create()` owns the CPU framebuffer, tile resources, state, scheduler and pipeline.
- **State** - `SetViewport()`, `ResetViewport()`, `SetClearColor()`.
- **Draw commands** - pixels, lines, rectangles, triangles, textures and bitmap text.
- **CPU shaders** - `Bloom.CreateShader()` and `canvas:ApplyShader()` transform pixels in a chosen rectangle.
- **Presentation** - `Update()` uploads dirty tiles immediately; `UpdateAsync()` queues tile uploads through an independent cooperative worker loop, without connecting to frame or physics events.
- **Open pipeline** - `RegisterStage(name, callback, order)` exposes lifecycle hooks for custom CPU work.
- **Profiling** - `GetStats()` reports upload bytes/time, processed shader/texture pixels and glyph counts.

## Textures

```lua
local Texture = Bloom.Texture

-- Read from an EditableImage without changing or destroying it.
local imageTexture = Texture.FromEditableImage(existingEditableImage)

canvas:DrawTexture(imageTexture, 32, 32, 128, 128, {
    tint = Color4.New32Bit(255, 255, 255, 255),
    opacity = 1,
    blend = true,
})
```

`Texture.New(width, height, pixels)` accepts a buffer containing exactly `width * height * 4` RGBA bytes. It copies by default; pass `false` as the fourth argument to avoid a copy and transfer responsibility for the buffer to the caller. `Texture.FromContent(content)` uses Roblox's `AssetService:CreateEditableImageAsync()` and therefore obeys Roblox asset permissions.

`DrawTexture` supports scaling, source rectangles, packed RGBA tint, opacity, alpha blending, and direct replacement (`blend = false`). Nearest-neighbor sampling is used intentionally to keep the CPU path predictable and fast.

## CPU shaders

```lua
local Shader = Bloom.Shader
local invert = Shader.Invert()
canvas:ApplyShader(invert, 1, 1, canvas.res_x, canvas.res_y)

local posterize = Bloom.CreateShader("Posterize", function(x, y, u, v, color32, uniforms)
    local step = uniforms.step or 32
    local r = bit32.band(color32, 0xFF)
    local g = bit32.band(bit32.rshift(color32, 8), 0xFF)
    local b = bit32.band(bit32.rshift(color32, 16), 0xFF)
    local a = bit32.band(bit32.rshift(color32, 24), 0xFF)
    r = math.floor(r / step + 0.5) * step
    g = math.floor(g / step + 0.5) * step
    b = math.floor(b / step + 0.5) * step
    return bit32.bor(math.min(r, 255), bit32.lshift(math.min(g, 255), 8), bit32.lshift(math.min(b, 255), 16), bit32.lshift(a, 24))
end, { step = 32 })

canvas:ApplyShader(posterize, 1, 1, canvas.res_x, canvas.res_y)
```

A custom callback runs once for every pixel in the target rectangle. Keep it allocation-free: do not create tables, `Color3`, `Vector2`, or closures inside the pixel loop. Use `u` and `v` for normalized coordinates, `color32` for packed RGBA, and `uniforms` for parameters.

Built-ins: `Bloom.Shader.Invert()`, `Bloom.Shader.Grayscale()`, `Bloom.Shader.Brightness(amount)`.

## Fonts

Bloom supports both user-provided bitmap atlases and rasterization from binary TrueType-outline `.ttf` data.

```lua
-- fontBytes is the original binary file contents represented as a Luau string.
local font = Bloom.Font.FromString(
    fontBytes,
    18,
    " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!?.,:-_"
)

canvas:DrawText(font, "Hello Bloom!", 12, 12, Color4.New32Bit(255, 255, 255, 255), 1)
local width, height = Bloom.Font.MeasureText(font, "Hello Bloom!", 1)
font:Destroy()
```

Use `Bloom.Font.FromBuffer(fontBuffer, pixelSize, charset, options)` if the bytes are already in a Luau `buffer`. `buffer.fromstring(fontBytes)` converts a binary string to a buffer; it does not decode Base64. `charset` determines which glyphs are rasterized up front. Loading and rasterization should happen once during initialization, never inside the render loop.

`Bloom.Font.New(atlasTexture, glyphs, lineHeight, options)` remains available for custom bitmap atlases. Binary loading supports TrueType-outline TTF fonts with Unicode cmap format 4 or 12, including composite glyphs that use XY offsets and simple transforms. CFF OpenType, WOFF/WOFF2, variable-font axes, and point-attached composite components are not supported; convert those files to a static TrueType-outline TTF first.

## Async tasks and stages

```lua
canvas:RegisterStage("custom-stage", function(context, phase)
    if phase == "beforeUpload" then
        -- Keep custom work short and avoid recursively calling Update().
    end
end, 50)

canvas:Submit(function()
    -- One short, non-yielding unit of work.
end)
canvas.async:Start()
canvas:UpdateAsync(0.001)
```

The scheduler is cooperative and independent of `RunService`: `Start()` uses a `task.spawn` worker loop with `task.wait`, while `Step()` can be driven manually by a host scheduler. It uses four priority levels (0 is highest), FIFO ordering within a level, aging to prevent starvation, optional absolute deadlines, cancellation, cooperative yielding, and runtime counters. It checks its time budget between coroutine resumes; it cannot preempt a callback that does not yield. The pipeline phases include `beginFrame`, `endFrame`, `beforeUpload`, `afterUpload`, `tileUploaded`, `beforeShader`, and `afterShader`.

```lua
-- High-priority task with an absolute os.clock() deadline.
canvas:SubmitWithOptions(function()
    -- Keep each chunk short.
    performSmallChunk()
    Bloom.Async.Yield() -- let other queued work run before this task resumes
    performNextChunk()
end, {
    priority = 0,
    deadline = os.clock() + 0.05,
})

-- Background work uses priority 3.
canvas:SubmitWithOptions(function()
    buildCacheInSmallChunks()
end, { priority = 3 })

canvas.async:Start()
```

**Important concurrency boundary:** this scheduler is cooperative, not a claim of multi-core execution. Bloom's drawing methods mutate one shared CPU framebuffer, so they must not be called concurrently against the same context. Real parallel CPU work needs Actor workers with a serializable job protocol and independent tile-local buffers; results must be merged and sent to `EditableImage` from a permitted serial context. The current scheduler provides fair, frame-independent scheduling and cancellation without pretending that `task.spawn` itself creates parallel CPU execution.

## Performance notes

- Prefer opaque textures and `blend = false` when alpha blending is not required.
- Restrict shaders to the smallest rectangle possible; a full 1024×1024 shader calls Luau code over one million times.
- Prefer rectangles or texture blits to thousands of individual `DrawPixel()` calls.
- Use `UpdateAsync()` to spread tile uploads across scheduler steps, but remember that it spreads work rather than making a single upload cheaper.
- Reuse `Texture` and `Font` objects instead of rebuilding atlases per frame.
- `GetStats()` returns counters; use Roblox MicroProfiler/Script Profiler for device-specific timing.
- `EditableImage` display updates are rate-limited by Roblox. Tiling helps manage larger CPU framebuffers, but it does not turn the API into an unrestricted GPU upload queue.

## Coordinate and ownership rules

- Coordinates are 1-based and rectangle endpoints are inclusive.
- Pixel bytes are RGBA, as in `EditableImage:ReadPixelsBuffer()`. Packed colors use `Color4.New32Bit(r, g, b, a?)`; alpha defaults to 255.
- `GetBuffer()` returns the live framebuffer. After direct buffer writes, call `MarkDirty(x0, y0, x1, y1)`.
- `DrawPixelUnsafe()` and `ReadPixelUnsafe()` skip bounds checks and rounding; use only with valid integer coordinates.
- `Resize()` discards existing pixels and recreates owned presentation resources. Resizing a `FromEditableImage()` wrapper is intentionally rejected because the wrapped image is externally owned.
- Call `Destroy()` when finished to release owned `EditableImage` objects, cloned labels and scheduler workers.

## Development

Tools are pinned in `rokit.toml` (`lune`, `luau-lsp`).

```bash
rokit install
luau-lsp analyze --platform=roblox --definitions=<path to globalTypes.d.luau> src
lune run tests/run
```

`tests/roblox_mock.luau` loads the modules with Roblox's require-by-string rules and mocks `AssetService`/`EditableImage` according to their documented contract (size limit, `nil` on exhausted budget, 4 bytes per pixel).

## Documentation

Step-by-step documentation in Russian ([`docs/ru`](docs/ru/README.md)) and English ([`docs/en`](docs/en/README.md)): every function, every option and every possible outcome, plus a full list of error messages ([ru](docs/ru/13-errors.md) · [en](docs/en/13-errors.md)).

The same docs are published at **https://framebuffer-studio.github.io/Bloom/**: a terminal-style site with Discord-like slash commands (`/help`, `/canvas`, `/fn DrawLine`, `/search ...`) and a RU/EN switch. The site is built from this `docs/` folder.

## Luau types

Public option tables are explicitly typed (`Bloom.Options`, `Bloom.SubmitOptions`, `Bloom.Texture.DrawOptions`, `Bloom.Font.Options`). See [docs/en/14-types.md](docs/en/14-types.md) for examples.
