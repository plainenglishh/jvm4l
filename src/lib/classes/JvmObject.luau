local t = require("../t")
local typechecker = require("../typechecker")
local util = require("../util")

local function hashcode_of(o: any)
    local ptr_str = string.match(tostring(o), "0x(%x+)") or error("unable to get hash code")
    local ptr = integer.fromstring(ptr_str, 16)

    local upper = integer.band(integer.idiv(ptr, 0x100000000i), 0xFFFFFFFFi)
    local lower = integer.band(ptr, 0xFFFFFFFFi)
    local folded = integer.bxor(upper, lower)

    folded = integer.idiv(folded, 8i)
    folded = integer.band(integer.mul(folded, 0x9E3779B9i), 0xFFFFFFFFi)

    if integer.ge(folded, 0x80000000i) then
        return integer.tonumber(integer.sub(folded, 0x100000000i))
    end

    return integer.tonumber(folded)
end

local JvmObject = {}
JvmObject.__type = "JvmObject"
JvmObject.__index = JvmObject

function JvmObject.__tostring(self: t.JvmObject): string
    -- at what point should this be deferred to the objects toString impl, if at all?
    local Throwable = self.jvm:resolve_class("java/lang/Throwable")
    if not self:instance_of(Throwable) then
        local bits = bit32.band(self.hash_code, 0xFFFFFFFF)
        return string.format("<JvmObject: %s@%08x>", self.class.fqcn, bits)
    end

    local message_ref = self.jvm:get_field_ref(Throwable, "message", "String")
    local message = self:get_field(message_ref) :: t.JvmObjectRef
    local message_str = ""
    if message then
        message_str = `: {message:inner_string()}`
    end

    return `{self.class.fqcn}{message_str}`
end

function JvmObject.__display(self: t.JvmObject): string
    return tostring(self)
end

function JvmObject._allocate(jvm: t.Jvm, class: t.JvmClass, magic: t._MagicValue?): t.JvmObject
    if class.name == "java/lang/String" then
        assert(
            magic and magic.kind == "string",
            `attempt to allocate {class.name} without magic value; did you use \`Jvm:create_string\`?`
        )
    elseif class.name == "java/lang/Thread" then
        assert(magic and magic.kind == "thread", `attempt to allocate {class.name} without magic value`)
    elseif string.sub(class.name, 1, 1) == "[" then
        assert(
            magic and magic.kind == "array",
            `attempt to allocate {class.name} without magic value; did you use \`Jvm:create_array\`?`
        )
    end

    local inner = {
        jvm = jvm,
        class = class,
        _monitor = { held_by = nil, waiting = {} } :: t.Monitor,
        _magic = magic,
        _field_values = {},
    }
    inner.hash_code = hashcode_of(inner)
    local self = setmetatable(inner, JvmObject)
    jvm._gc:_track(self)
    return self
end

function JvmObject._initialise(_self: t.JvmObject, ...: t.JvmValue)
    util.unimplemented()
end

function JvmObject.instance_of(self: t.JvmObject, class: t.JvmClass): boolean
    return self.class == class or self.class:inherits_from(class) or self.class:implements(class)
end

function JvmObject.implements(self: t.JvmObject, interface: t.JvmClass): boolean
    return self.class:implements(interface)
end

function JvmObject.get_field(self: t.JvmObject, field: t.FieldRef): t.JvmValue
    assert(self:instance_of(field.class))
    return self._field_values[field]
end

function JvmObject.set_field(self: t.JvmObject, field: t.FieldRef, value: t.JvmValue)
    assert(self:instance_of(field.class))
    local field_info = self.class:resolve_field(field) or error("")
    if not typechecker.check_field(self.jvm, value, self.class, field_info) then
        self.jvm:throw_exception("java/lang/IllegalArgumentException")
    end
    self._field_values[field] = value
end

function JvmObject.inner_string(self: t.JvmObject): string
    if not self._magic or self._magic.kind ~= "string" then
        error("not a string")
    end

    return self._magic.value
end

function JvmObject.inner_thread(self: t.JvmObject): t.JvmThread
    if not self._magic or self._magic.kind ~= "thread" then
        error("not a thread")
    end

    return self._magic.value
end

function JvmObject.get_array_length(self: t.JvmObject): number
    if not self._magic or self._magic.kind ~= "array" then
        error("not an array")
    end

    return self._magic.length
end

local function assert_array_bounds(self: t.JvmObject, index: number)
    assert(self._magic and self._magic.kind == "array")
    if index >= self._magic.length then
        self.jvm:throw_exception("java/lang/ArrayIndexOutOfBoundsException")
    end
end

function JvmObject.get_array_element(self: t.JvmObject, index: number): t.JvmValue
    if not self._magic or self._magic.kind ~= "array" then
        error("not an array")
    end

    assert_array_bounds(self, index)
    return self._magic.values[index + 1]
end

function JvmObject.set_array_element(self: t.JvmObject, index: number, value: t.JvmValue)
    if not self._magic or self._magic.kind ~= "array" then
        error("not an array")
    end

    if not typechecker.check_value(value, self._magic.element) then
        self.jvm:throw_exception("java/lang/IllegalArgumentException")
    end

    assert_array_bounds(self, index)
    self._magic.values[index + 1] = value
end

function JvmObject.get_array_elements(self: t.JvmObject, index: number?, count: number?): { t.JvmValue }
    if not self._magic or self._magic.kind ~= "array" then
        error("not an array")
    end

    local index = index or 0
    local count = count or self._magic.length - index

    assert_array_bounds(self, index)
    assert_array_bounds(self, index + count - 1)

    local values: { t.JvmValue } = table.create(count, nil :: any)
    table.move(self._magic.values, index + 1, index + count + 1, 1, values)
    return values
end

table.freeze(JvmObject)

return JvmObject
