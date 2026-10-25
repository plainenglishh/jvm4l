local ConstantPool = require("../ConstantPool")
local execution_engine = require("../execution_engine")
local t = require("../t")
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

function JvmClass._prepare(
    jvm: t.Jvm,
    loader: t.JvmClassLoader,
    name: string,
    super: t.JvmClass?,
    interfaces: { t.JvmClass },
    methods: { t.MethodInfo },
    fields: { t.FieldInfo },
    access_flags: number,
    classfile: t.Classfile?
): t.JvmClass
    local self: t.JvmClass = setmetatable({
        jvm = jvm,
        name = name,
        fqcn = string.gsub(name, "/", "."),
        super = super,
        interfaces = interfaces,
        loader = loader,

        public = bit32.band(access_flags, 0x0001) ~= 0,
        final = bit32.band(access_flags, 0x0010) ~= 0,
        super_flag = bit32.band(access_flags, 0x0020) ~= 0,
        interface = bit32.band(access_flags, 0x0200) ~= 0,
        abstract = bit32.band(access_flags, 0x0400) ~= 0,
        synthetic = bit32.band(access_flags, 0x1000) ~= 0,
        annotation = bit32.band(access_flags, 0x2000) ~= 0,
        enum = bit32.band(access_flags, 0x4000) ~= 0,

        _methods = methods,
        _fields = fields,
        _classfile = classfile,
        _constant_pool = nil,
        _monitor = { held_by = nil, waiting = {} } :: t.Monitor,
        _mirror = (nil :: any) :: t.JvmObject,
        _state = "uninitialised",
        _static_field_values = {},
    }, JvmClass)

    if classfile then
        self._constant_pool = ConstantPool.new(self)
    end

    if name ~= "java/lang/Object" and name ~= "java/lang/Class" then
        local mirror = jvm._classes.bootstrap["java/lang/Class"]:_new_uninitialised({
            kind = "class",
            value = self,
        })

        self._mirror = mirror
    end

    return self
end

function JvmClass._ensure_initialised(self: t.JvmClass)
    -- TODO: hold the monitor during initialisation, and allow reentrancy
    if self._state == "initialised" then
        return
    elseif self._state == "initialising" then
        -- FIXME: block other threads waiting for this to be initialised ! also, allow reentrant initialiser
        error("other thread is initialising")
    elseif self._state == "error" then
        error("this class errored. cannot be used ok!") -- make this nicer
    end

    self._state = "initialising"
    self.jvm:_trace(`initialising class {self.name}`)

    if self.super then
        self.super:_ensure_initialised()
        if self.super._state == "error" then
            (self :: any)._state = "error" -- this is read only sometimes? (hence the horrid typecast)
            error("this class errored. cannot be used ok!") -- make this nicer
        end
    end

    -- TODO: interfaces here
    -- TODO: do ConstantValue here

    if self:get_method("<clinit>", "()V") then
        local clinit = self.jvm:resolve_method(self, "<clinit>", "()V")
        local dispatched_clinit = execution_engine.dispatch(self.jvm, clinit, "static", self)
        execution_engine.invoke_sync(self.jvm, dispatched_clinit, {})
    end

    self._state = "initialised"
end

function JvmClass._new_uninitialised(self: t.JvmClass, magic: t._MagicValue?): t.JvmObject
    assert(self._state ~= "error")
    return JvmObject._new(self.jvm, self, magic)
end

function JvmClass.new(self: t.JvmClass, constructor: t.MethodHandle, args: { t.JvmValue }): t.JvmObject
    local o = self:_new_uninitialised()
    local args = table.clone(args)
    table.insert(args, 1, o)
    local dispatched_constructor = execution_engine.dispatch(self.jvm, constructor, "special", self)
    execution_engine.invoke_sync(self.jvm, dispatched_constructor, args)
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

function JvmClass.get_static_field(self: t.JvmClass, field: t.FieldHandle): t.JvmValue
    assert(self._state ~= "error")
    assert(self == field.class or self:inherits_from(field.class))
    return field.class._static_field_values[field]
end

function JvmClass.set_static_field(self: t.JvmClass, field: t.FieldHandle, value: t.JvmValue)
    assert(self._state ~= "error")
    assert(self == field.class or self:inherits_from(field.class))
    field.class._static_field_values[field] = value
end

function JvmClass.invoke_static(self: t.JvmClass, method: t.MethodHandle, args: { t.JvmValue }): t.JvmValue
    local dispatched_method = execution_engine.dispatch(self.jvm, method, "static", self)
    return execution_engine.invoke_sync(self.jvm, dispatched_method, args)
end

function JvmClass.get_method(self: t.JvmClass, name: string, descriptor: string): t.MethodInfo?
    for _, method in self._methods do
        if method.name == name and method.descriptor == descriptor then
            return method
        end
    end

    return nil
end

table.freeze(JvmClass)

return JvmClass
