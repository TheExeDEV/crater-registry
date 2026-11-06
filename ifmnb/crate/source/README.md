# crate

A Luau runtime for emulating objects based on userdata — a minimal OOP system built on `newproxy(true)` userdata proxies.

## Overview

`crate` is a regular Luau table that simultaneously serves as:

* the metatable of the userdata proxy (`newproxy(true)`) — it carries `__index`, `__newindex`, `__tostring`, and `__iter`;
* a trusted handle for core code — direct access to `_fields`, `_readable`, `_writeable`, `_extend`, and `_parent`.

The userdata (`_instance`) is the untrusted face exposed to the outside world; all reads, writes, iteration, and `tostring` go through the metamethods defined on the crate.

## Core concepts

### `crate`

A trusted handle over a userdata proxy. Each crate holds:

* `_parent` — the parent *instance* (userdata), or `nil` for the root crate. The parent crate is resolved via the weak-keyed registry `crates:get(_parent)`.
* `_instance` — the userdata proxy handed out to untrusted code.
* `_readable` — whitelist of readable field names. Reads walk the `_parent` chain and return the first `_fields[name]` whose `_readable` contains `name`.
* `_writeable` — whitelist of writable field names. Writes walk the `_parent` chain and land in the first crate whose `_writeable` contains `name`.
* `_fields` — value storage; keys are always strings. Untrusted code cannot touch this directly.
* `_type` — publicly reflected type string (returned by `tostring(instance)`; defaults to `"userdata"`).
* `__index` / `__newindex` / `__iter` / `__tostring` / `__metatable` — the VM metamethods.

### `library`

The public module entry point:

* `library.new(type?)` — creates a fresh root crate with an attached `newproxy(true)` userdata, installs the metamethods, and returns the crate (the trusted handle). Usually the crate stays private and only `crate._instance` is exposed.
* `library.is_crate(that)` — checks whether `that` is a crate instance.

## Inheritance

`crate._extend(type?)` spawns a child crate. The new crate inherits from `self`:

* `_parent` points at `self` (well, at `self._instance`, resolved through the registry).
* `_type` is either the explicit argument or `"userdata"`.

Field resolution walks the parent chain: a read of `instance.foo` returns the first `_fields.foo` found in a crate whose `_readable` contains `foo`; a write lands in the first crate whose `_writeable` contains `foo`. This allows shadowing and selective exposure across a hierarchy.

## Usage example

```lua
--!strict

local crate = require("crate")

-- Create a root object
local object = crate.new("part")

-- Whitelist readable and writable fields
object._readable = {"position", "size"}
object._writeable = {"position", "size"}

-- Store values in the trusted _fields table
object._fields.position = Vector3.new(0, 0, 0)
object._fields.size = Vector3.new(1, 1, 1)

-- Expose the userdata to untrusted code
local instance = object._instance

-- Untrusted code can read through the proxy
print(instance.position)   -- works: position is in _readable
instance.position = Vector3.new(1, 2, 3)  -- works: position is in _writeable
instance.hidden = 42       -- errors: not in _writeable
```

## Design invariants

* `crates[instance] == crate` — weak-keyed registry inside the library maps each userdata to its crate.
* `crate._instance == instance`.
* `_parent` holds the *instance* of the parent (userdata), not a crate; the parent crate is resolved via `crates:get(crate._parent)`.
* `__tostring` is display-only — never use it for identity checks; use `crates:get(instance) ~= nil` instead.

## License

MPLv2 — see `LICENSE.md`.
