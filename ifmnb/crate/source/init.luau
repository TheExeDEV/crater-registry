--!strict

--[==[
    crate — a handle over a userdata proxy.

    `crate` is a regular Luau table that simultaneously serves as:
      * the metatable of the userdata proxy (`newproxy(true)`); that is,
        it carries `__index` / `__newindex` / `__tostring` / `__iter`;
      * a trusted handle for core code: direct access to `_fields`,
        `_readable`, `_writeable`, `_extend`, `_parent`.

    The userdata (`_instance`) is the untrusted face exposed to the
    outside world; all reads/writes/iteration/`tostring` go through the
    metamethods below.

    Invariants:
      * `crates[instance] == crate`  (weak-keyed registry inside the library)
      * `crate._instance == instance`
      * `_parent` holds the *instance* of the parent (userdata), not a
        crate; the parent crate is resolved via `crates:get(crate._parent)`.
]==]
export type crate = {
	--[==[
        Parent *instance* (userdata), or `nil` for the root crate.

        IMPORTANT: it must be the instance, not the crate, because
        `crates:get(...)` takes an instance. The current `private.fill`
        stores `crates:get(parent)` here (i.e. a crate) — that is a bug:
        the walk in `__index` and `setup` does `crates:get(_parent)`,
        which returns `nil`, so the chain stops after the first level.
    ]==]
	_parent: any?,

    --[==[
        Allows to search for fields in the parent if the child does not have them.
    ]==]
    _index_relative_to_parent: boolean,
    --[==[
        Allows to write fields based on the parent's opinion
    ]==]
    _newindex_relative_to_parent: boolean,

    --[==[
        Allows to iterate over parent fields
    ]==]
    _iter_relative_to_parent: boolean,

    --[==[
        Fields that are not in readable and in this field will not pass through __iter
    ]==]
    read _iterateable: {string},

	--[==[
        The userdata proxy (`newproxy(true)`). This is the face handed
        out to untrusted code. Every `__index` / `__newindex` /
        `__iter` / `__tostring` access goes through the metatable —
        this very crate.
    ]==]
	read _instance: any,

	--[==[
        Whitelist of readable field names. A read through the proxy
        (`instance.foo`) walks the `_parent` chain and returns
        `_fields.foo` of the first crate whose `_readable` contains
        `foo`. An empty entry (name present in `_readable`, but
        `_fields.foo == nil`) means "the field exists, but its value is
        `nil`" — just like `t.foo = nil`.
    ]==]
	read _readable: { string },

	--[==[
        Value storage. Keys are always strings (constrained by
        `_readable` / `_writeable`). Untrusted code cannot read or write
        this table directly — only through the proxy metamethods.
    ]==]
	read _fields: { [string]: any },

	--[==[
        Whitelist of writable field names. A write through the proxy
        (`instance.foo = v`) walks the `_parent` chain and lands in
        `_fields.foo` of the first crate whose `_writeable` contains
        `foo`.

        At the type level `_writeable` and `_readable` are independent.
        If a field is writable but not readable on the same crate, the
        write lands in that crate's `_fields`, while the read falls
        through to the parent — see the note on `__newindex`.
    ]==]
	read _writeable: { string },

	--[==[
        Publicly reflected type: the string returned by
        `tostring(instance)` and consumed by external reflection
        (`ftype`, `mtypes`). If `type` is not passed to `new`, the
        default is `"userdata"`.

        This is *display only*: for identity checks use
        `crates:get(instance) ~= nil`, not `tostring`. `__tostring` is
        trivially spoofable — it is not an identity.
    ]==]
	_type: string,

	--[==[
        VM metamethod invoked on a proxy field read: `instance.foo`.
        Walks the `_parent` chain and returns the first `_fields.foo`
        whose `_readable` contains `foo`. If nobody permits it — `error`.

        The generic form `<T, U, E>` is a type-level escape hatch: it
        lets trusted call sites write `local n: number = instance.foo`
        without a cast, because `E` is free and unifies with the target
        type. At runtime the VM calls it as `(userdata, any) -> any`.
    ]==]
	read __index: <T, U, E>(instance: T, index: U) -> E,

	--[==[
        VM metamethod invoked on a proxy field write: `instance.foo = v`.
        Walks the `_parent` chain and writes into `_fields.foo` of the
        first crate whose `_writeable` contains `foo`. Otherwise — `error`.

        BUG in the current implementation: after a successful write
        there is no `return`, so the loop always reaches `error(...)`;
        and the iteration step uses `crate._parent` instead of
        `search._parent`, which loops forever on a multi-level chain.
        Fix: write into `search._fields[index]` and `return` immediately
        (not `crate._fields`).
    ]==]
	read __newindex: <T, U, E>(instance: T, index: U, value: E) -> (),

	--[==[
        VM metamethod for `tostring(instance)`. Returns `_type` (the
        `"userdata"` fallback is dead code, because `fill` always sets
        `_type`). Display only — never use for identity checks.
    ]==]
	read __tostring: <T>(instance: T) -> string,

	--[==[
        The `__metatable` value: what `getmetatable(instance)` returns
        to untrusted code. It is set to the parent's instance (if any)
        or to the crate's own instance — i.e. a subclass pretends to be
        its parent for `typeof` (platform-level type spoofing). The
        metatable itself cannot be overridden from outside.

        Typed `any`, because Luau has no nominal type
        "userdata with such-and-such metatable", and `newproxy` returns
        `any`.
    ]==]
	read __metatable: any,

	--[==[
        Generalized iteration metamethod (`for k, v in instance` and
        `pairs(instance)`). Returns a snapshot of visible fields: walks
        the `_parent` chain with the same shadowing rule as `__index`.
        Fields with `nil` values are skipped (`pairs` cannot yield `nil`).
    ]==]
	read __iter: <T>(instance: T) -> (any, any, any?),

	--[==[
        Spawns a child crate. The new crate inherits from `self`:
        `_parent` points at `self`, `_type` is either the explicit
        argument or `"userdata"`. Returns a *crate* (the trusted
        handle), not an instance — the caller decides when and to whom
        the child instance is exposed.
    ]==]
	read _extend: (self: crate, type: string?) -> crate,
}

--[==[
    Public module entry point. `new(type)` builds a fresh crate with an
    attached `newproxy(true)` userdata, installs the metamethods, and
    returns the crate. Usually the crate stays private and only
    `crate._instance` is exposed to the outside world.
]==]
export type library = {
	--[==[
        Creates a new root crate. `type` is reflected via `tostring`
        and defaults to `"userdata"`. Returns the crate (the trusted
        handle), not the instance.
    ]==]
	read new: (type: string?) -> crate,

    --[==[
        Checks is it a crate instance or not?
    ]==]
    read is_crate: (that: any) -> boolean
}

const private = {}
const library: library = table.freeze {
    new = function (type: string?) : crate
        const crate = private.create()
        private.fill(crate, nil, type)
        private.setup(crate)

        return crate
    end,

    is_crate = function (that: any) : boolean
        return private.crates:get(that) ~= nil
    end
}

do
    type instance = unknown


    private.fallback = "userdata"

    do
		type crates = {
			read get: (self: crates, instance: instance) -> crate?,
			read set: (self: crates, instance: instance, to: crate?) -> (),
		}

        const list = setmetatable({} :: {[instance]: crate?}, table.freeze {__mode = "ks"})

		private.crates = table.freeze {
			get = function(self, instance)
				return list[instance]
			end,

			set = function(self, instance, to)
				list[instance] = to
			end,
		} :: crates
    end

    private.create = function () : crate
        const instance = newproxy(true)
        const crate_ = getmetatable(instance)
        
        crate_._instance = instance
        crate_._readable = {}
        crate_._fields = {}
        crate_._iterateable = {}
        crate_._writeable = {}

        const crate : crate = crate_ :: any

        crate._index_relative_to_parent = false
        crate._newindex_relative_to_parent = false

        private.crates:set(instance, crate)

        return crate
    end

    private.fill = function (crate: any, parent, type) : crate
        crate._parent = parent
        crate._type = type or private.fallback
        crate._extend = private.extend

        return crate
    end

    private.setup = function (crate: crate)
        const crate_ = crate :: any
        const parent = private.crates:get(crate._parent)

        crate_.__index = private.__index
        crate_.__newindex = private.__newindex
        crate_.__iter = private.__iter
        crate_.__tostring = private.__tostring
        crate_.__metatable = parent and parent._instance or crate._instance

        return crate
    end

    private.extend = function (parent: crate, type: string?) : crate
        const new  = private.create()
        private.fill(new, parent._instance, type)
        private.setup(new)
        return new
    end

    private.__index = function <T,U,E>(instance: T, index: U) : E
        const crate = assert(private.crates:get(instance), "crate does not exist")
        local search = crate

        while search ~= nil do
            if table.find(search._readable, index) then
                return search._fields[index]
            end

            if not search._index_relative_to_parent then
                break
            end

            search = private.crates:get(search._parent)
        end

        return error(`Reading of index {tostring(index)} is not allowed`)
    end

    private.__tostring = function <T> (instance: T) : string
        const crate = assert(private.crates:get(instance), "crate does not exist")

        return crate._type or private.fallback
    end

	private.__iter = function<T>(instance: T): (any, any, any?)
		const crate = assert(private.crates:get(instance), "crate does not exist")

		local visible: { [string]: any } = {}
		local seen: { [string]: boolean } = {}

		local search: crate? = crate
		while search ~= nil do
			for _, key in search._readable do
				if not seen[key] then
					seen[key] = true

                    if not table.find(search._iterateable, key) then
                        continue
                    end

					local value = search._fields[key]
					if value ~= nil then
						visible[key] = value
					end
				end
			end

            if not search._iter_relative_to_parent then
                break
            end

			search = private.crates:get(search._parent)
		end

		return next, visible, nil
	end

    private.__newindex = function <T,U,E> (instance: T, index: U, value: E) : ()
        const crate = assert(private.crates:get(instance), "crate does not exist")
        local search = crate

        while search ~= nil do
            if (table.find(search._writeable, index)) then
                search._fields[index] = value
                return
            end

            if not search._newindex_relative_to_parent then
                break
            end

            search = private.crates:get(search._parent)
        end

        error(`Writing of index {tostring(index)} with value {tostring(value)} is not allowed`)
    end

    table.freeze(private)
end

return library