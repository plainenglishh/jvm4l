local t = require("../t")
local util = require("../util")
local JvmObject = require("./JvmObject")

local JvmClass = {}
JvmClass.__type = "JvmClass"
JvmClass.__index = JvmClass

function JvmClass.__tostring(self: t.JvmClass): string
    return `<JvmClass: {self.fqcn}>`
end

function JvmClass.__display(self: t.JvmClass): string
    return tostring(self)
end

function JvmClass._allocate(
    jvm: t.Jvm,
    loader: t.JvmClassLoader,
    name: string,
    super: t.JvmClass?,
    interfaces: { t.JvmClass },
    methods: { t.MethodInfo },
    fields: { t.FieldInfo },
    classfile: t.Classfile?
): t.JvmClass
    local self: t.JvmClass = setmetatable({
        jvm = jvm,
        name = name,
        fqcn = string.gsub(name, "/", "."),
        super = super,
        interfaces = interfaces,
        loader = loader,
        _methods = {},
        _fields = {},
        _classfile = classfile,
        _monitor = { held_by = nil, waiting = {} } :: t.Monitor,
        _mirror = (nil :: any) :: t.JvmObject,
        _state = "uninitialised",
        _static_field_values = {},
    }, JvmClass)

    local seen_methods: { [string]: boolean } = {}

    for _, method in methods do
        local ref = jvm:get_method_ref(self, method.name, method.descriptor)

        self._methods[ref] = method
        seen_methods[method.signature] = true
    end

    local current = self.super

    while current do
        for ref, method in current._methods do
            if seen_methods[method.signature] then
                continue
            end

            self._methods[ref] = method
            seen_methods[method.signature] = true
        end

        current = current.super
    end

    for _, field in fields do
        local ref = jvm:get_field_ref(self, field.name, field.descriptor)

        self._fields[ref] = field
    end

    current = self.super

    while current do
        for ref, field in current._fields do
            self._fields[ref] = field
        end

        current = current.super
    end

    if name ~= "java/lang/Object" and name ~= "java/lang/Class" then
        local mirror = jvm._classes.bootstrap["java/lang/Class"]:new_uninitialised({
            kind = "class",
            value = self,
        })

        self._mirror = mirror
    end

    return self
end

function JvmClass._initialise(self: t.JvmClass)
    assert(self._state ~= "error")

    if self._state ~= "uninitialised" then
        return
    end

    local clinit_ref = self.jvm:get_method_ref(self, "<clinit>", "()V")
    local clinit_info = self:resolve_method(clinit_ref)
    if not clinit_info then
        return
    end

    util.unimplemented("clinit not implemented")
end

function JvmClass.new_uninitialised(self: t.JvmClass, magic: t._MagicValue?): t.JvmObject
    assert(self._state ~= "error")
    return JvmObject._allocate(self.jvm, self, magic)
end

function JvmClass.new(self: t.JvmClass, _constructor: t.MethodRef, ...: t.JvmValue): t.JvmObject
    local o = self:new_uninitialised()
    -- TODO: Select and call initialiser.
    return o
end

function JvmClass.inherits_from(self: t.JvmClass, other: t.JvmClass): boolean
    local current: t.JvmClass? = self

    while current do
        if current == other then
            return true
        end

        current = current.super
    end

    return false
end

function JvmClass.implements(self: t.JvmClass, interface: t.JvmClass): boolean
    for _, implemented in self.interfaces do
        if implemented == interface or implemented:implements(interface) then
            return true
        end
    end

    if self.super then
        return self.super:implements(interface)
    end

    return false
end

function JvmClass.resolve_method(self: t.JvmClass, ref: t.MethodRef): t.MethodInfo?
    assert(self._state ~= "error")
    return self._methods[ref]
end

function JvmClass.resolve_field(self: t.JvmClass, ref: t.FieldRef): t.FieldInfo?
    assert(self._state ~= "error")
    return self._fields[ref]
end

function JvmClass.get_static_field(self: t.JvmClass, field: t.FieldRef): t.JvmValue
    assert(self._state ~= "error")
    assert(self == field.class or self:inherits_from(field.class))
    return field.class._static_field_values[field]
end

function JvmClass.set_static_field(self: t.JvmClass, field: t.FieldRef, value: t.JvmValue)
    assert(self._state ~= "error")
    assert(self == field.class or self:inherits_from(field.class))
    field.class._static_field_values[field] = value
end

table.freeze(JvmClass)

return JvmClass
