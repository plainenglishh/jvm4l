local class_parser = require("../class_parser")
local descriptor_parser = require("../descriptor_parser")
local jcl_classfiles = require("../jcl_classfiles")
local native_methods = require("../native_methods")
local t = require("../t")
local util = require("../util")
local GarbageCollector = require("./GarbageCollector")
local JvmClass = require("./JvmClass")

local Jvm = {}

Jvm.__type = "Jvm"
Jvm.__index = Jvm

function Jvm.__tostring(_self: t.Jvm): string
    return "<Jvm>"
end

function Jvm.__display(self: t.Jvm): string
    return tostring(self)
end

local function link_native(self: t.Jvm, class_name: string, signature: string): t.NativeMethod?
    if string.match(class_name, "^java/") or string.match(class_name, "^jvm4l/") then
        return native_methods[class_name] and native_methods[class_name][signature]
    end

    return self._link_user_native(class_name, signature)
end

local function get_members(jvm: t.Jvm, classfile: t.Classfile): ({ t.MethodInfo }, { t.FieldInfo })
    local class_name = class_parser.class_name(classfile, class_parser.class(classfile, classfile.this_class))

    local methods: { t.MethodInfo } = {}

    for _, method in classfile.methods do
        local name = class_parser.string_value(classfile, method.name_index)
        local descriptor = class_parser.string_value(classfile, method.descriptor_index)
        local signature = `{name}:{descriptor}`
        local native = bit32.band(method.access_flags, 0x0100) ~= 0
        local abstract = bit32.band(method.access_flags, 0x0400) ~= 0

        local code: t.MethodCode
        if native then
            local native_method = link_native(jvm, class_name, signature) or error("link error")

            code = {
                kind = "luau",
                closure = native_method,
            }
        elseif abstract then
            code = { kind = "abstract" }
        else
            -- TODO: extract code info
            code = { kind = "abstract" }
        end

        table.insert(methods, {
            name = name,
            descriptor = descriptor,
            signature = signature,
            code = code,

            public = bit32.band(method.access_flags, 0x0001) ~= 0,
            private = bit32.band(method.access_flags, 0x0002) ~= 0,
            protected = bit32.band(method.access_flags, 0x0004) ~= 0,
            static = bit32.band(method.access_flags, 0x0008) ~= 0,
            final = bit32.band(method.access_flags, 0x0010) ~= 0,
            synchronised = bit32.band(method.access_flags, 0x0020) ~= 0,
            bridge = bit32.band(method.access_flags, 0x0040) ~= 0,
            varargs = bit32.band(method.access_flags, 0x0080) ~= 0,
            native = native,
            abstract = abstract,
            strictfp = bit32.band(method.access_flags, 0x0800) ~= 0,
            synthetic = bit32.band(method.access_flags, 0x1000) ~= 0,
        })
    end

    local fields = {}

    for _, field in classfile.fields do
        local name = class_parser.string_value(classfile, field.name_index)
        local descriptor = class_parser.string_value(classfile, field.descriptor_index)

        table.insert(fields, {
            name = name,
            descriptor = descriptor,
            signature = `{name}:{descriptor}`,

            public = bit32.band(field.access_flags, 0x0001) ~= 0,
            private = bit32.band(field.access_flags, 0x0002) ~= 0,
            protected = bit32.band(field.access_flags, 0x0004) ~= 0,
            static = bit32.band(field.access_flags, 0x0008) ~= 0,
            final = bit32.band(field.access_flags, 0x0010) ~= 0,
            volatile = bit32.band(field.access_flags, 0x0040) ~= 0,
            transient = bit32.band(field.access_flags, 0x0080) ~= 0,
            synthetic = bit32.band(field.access_flags, 0x0100) ~= 0,
            enum = bit32.band(field.access_flags, 0x0400) ~= 0,
        })
    end

    return methods, fields
end

local function bootstrap_core_classes(self: t.Jvm)
    local object_classfile = class_parser.parse(jcl_classfiles["java/lang/Object"])
    local object_methods, object_fields = get_members(self, object_classfile)

    local object = JvmClass._allocate(
        self,
        "bootstrap",
        "java/lang/Object",
        nil,
        {},
        object_methods,
        object_fields,
        object_classfile
    )
    self._classes.bootstrap["java/lang/Object"] = object

    local class_classfile = class_parser.parse(jcl_classfiles["java/lang/Class"])
    local class_methods, class_fields = get_members(self, class_classfile)

    local class = JvmClass._allocate(
        self,
        "bootstrap",
        "java/lang/Class",
        object,
        {},
        class_methods,
        class_fields,
        class_classfile
    )
    self._classes.bootstrap["java/lang/Class"] = class

    local object_mirror = class:new_uninitialised({ kind = "class", value = object })
    object._mirror = object_mirror

    local class_mirror = class:new_uninitialised({ kind = "class", value = class })
    class._mirror = class_mirror

    self:resolve_class("java/lang/String")
    self:resolve_class("java/lang/Throwable")
    self:resolve_class("java/lang/Thread")
end

function Jvm.new(link_native: t.LinkNativeCallback): t.Jvm
    local self: t.Jvm = setmetatable({
        _classes = {
            bootstrap = {},
        },
        _threads = {},
        current_thread = nil,
        _gc = (nil :: any) :: t.GarbageCollector,
        _link_user_native = link_native,
        _interned_strings = {},
        _interned_method_refs = {},
        _interned_field_refs = {},
    }, Jvm)

    bootstrap_core_classes(self)
    self._gc = GarbageCollector._new(self)

    return self
end

function Jvm.get_loader(self: t.Jvm): t.JvmClassLoader
    local thread = self.current_thread
    if not thread or #thread._stack == 0 then
        return "bootstrap"
    end

    local root_frame = thread._stack[#thread._stack]
    return root_frame.class.loader
end

local ARRAY_METHODS = {}

local function register_class(self: t.Jvm, defining_loader: t.JvmClassLoader, class: t.JvmClass)
    if not self._classes[defining_loader] then
        self._classes[defining_loader] = {}
    end

    self._classes[defining_loader][class.name] = class
end

local function get_array_class(self: t.Jvm, name: string, initiating_loader: t.JvmClassLoader): t.JvmClass
    local element = string.sub(name, 2)
    local element_first_char = string.sub(element, 1, 1)

    local defining_loader: t.JvmClassLoader
    if element_first_char == "[" then
        local element_class = self:resolve_class(element, initiating_loader)
        defining_loader = element_class.loader
    elseif element_first_char == "L" then
        local element_class = self:resolve_class(string.sub(element, 2, #element - 1), initiating_loader)
        defining_loader = element_class.loader
    else
        defining_loader = "bootstrap"
    end

    local Object = self._classes.bootstrap["java/lang/Object"]
    local class = JvmClass._allocate(self, defining_loader, name, Object, {}, ARRAY_METHODS, {})
    register_class(self, defining_loader, class)
    return class
end

function Jvm.get_class(self: t.Jvm, name: string, initiating_loader: t.JvmClassLoader?): t.JvmClass?
    local initiating_loader: t.JvmClassLoader = initiating_loader or self:get_loader()

    if self._classes[initiating_loader][name] then
        return self._classes[initiating_loader][name]
    end

    if string.sub(name, 1, 1) == "[" then
        return get_array_class(self, name, initiating_loader)
    end

    if initiating_loader == "bootstrap" then
        if name == "java/lang/Object" or name == "java/lang/Class" then
            error("attempt to get uninitialised core class? how did you reach this point?")
        end

        local classfile = jcl_classfiles[name]
        if not classfile then
            return nil
        end

        return self:define_class(classfile, initiating_loader)
    end

    local derived_from_parent = self:get_class(name, initiating_loader.class.loader)
    if derived_from_parent then
        return derived_from_parent
    end

    local _fully_qualified_name = name:gsub("/", ".") -- to be passed to classloader
    return util.unimplemented("user class loaders are not yet supported")
end

function Jvm.resolve_class(self: t.Jvm, name: string, initiating_loader: t.JvmClassLoader?): t.JvmClass
    return self:get_class(name, initiating_loader) or error("unknown class")
end

function Jvm.define_class(self: t.Jvm, classfile: buffer, defining_loader: t.JvmClassLoader): t.JvmClass
    local classfile = class_parser.parse(classfile)

    local this_class_info = class_parser.class(classfile, classfile.this_class)
    local this_class_name = class_parser.class_name(classfile, this_class_info)

    assert(classfile.super_class ~= 0, "given classfile has no super class")

    local super_class_info = class_parser.class(classfile, classfile.super_class)
    local super_class_name = class_parser.class_name(classfile, super_class_info)
    local super_class = self:resolve_class(super_class_name, defining_loader)

    local implements = {}
    for _, interface_idx in classfile.interfaces do
        local interface_info = class_parser.class(classfile, interface_idx)
        local interface_name = class_parser.class_name(classfile, interface_info)
        local interface = self:resolve_class(interface_name, defining_loader)
        table.insert(implements, interface)
    end

    local methods, fields = get_members(self, classfile)
    local class =
        JvmClass._allocate(self, defining_loader, this_class_name, super_class, implements, methods, fields, classfile)
    register_class(self, defining_loader, class)
    return class
end

function Jvm.get_method_ref(self: t.Jvm, class: t.JvmClass, name: string, descriptor: string): t.MethodRef
    local by_class = self._interned_method_refs[class]
    if by_class then
        local by_name = by_class[name]
        if by_name then
            local ref = by_name[descriptor]
            if ref then
                return ref
            end
        end
    else
        by_class = {}
        self._interned_method_refs[class] = by_class
    end

    local by_name = by_class[name]
    if not by_name then
        by_name = {}
        by_class[name] = by_name
    end

    local ref = table.freeze({
        class = class,
        name = name,
        descriptor = descriptor,
    })

    by_name[descriptor] = ref
    return ref
end

function Jvm.get_field_ref(self: t.Jvm, class: t.JvmClass, name: string, descriptor: string): t.FieldRef
    local by_class = self._interned_field_refs[class]
    if by_class then
        local by_name = by_class[name]
        if by_name then
            local ref = by_name[descriptor]
            if ref then
                return ref
            end
        end
    else
        by_class = {}
        self._interned_field_refs[class] = by_class
    end

    local by_name = by_class[name]
    if not by_name then
        by_name = {}
        by_class[name] = by_name
    end

    local ref = table.freeze({
        class = class,
        name = name,
        descriptor = descriptor,
    })

    by_name[descriptor] = ref
    return ref
end

function Jvm.create_string(self: t.Jvm, value: string): t.JvmObject
    if self._interned_strings[value] then
        return self._interned_strings[value]
    end

    local String = self._classes.bootstrap["java/lang/String"]
    local str_obj = String:new_uninitialised({ kind = "string", value = value })
    self._interned_strings[value] = str_obj
    return str_obj
end

function Jvm.create_array(self: t.Jvm, element: t.JvmType, size: number): t.JvmObject
    local elem_descriptor = descriptor_parser.type_to_descriptor(element)
    local class_name = `[{elem_descriptor}`
    local class = self:resolve_class(class_name)
    local array = class:new_uninitialised({
        kind = "array",
        element = element,
        length = size,
        values = table.create(size, nil :: any),
    })
    return array
end

function Jvm.create_exception(self: t.Jvm, name: string, message: string?, cause: t.JvmObject?): t.JvmObject
    local Exception = self:resolve_class(name)
    local message = if message then self:create_string(message) else nil
    local e = Exception:new_uninitialised()

    local Throwable = self._classes.bootstrap["java/lang/Throwable"]
    local message_field = self:get_field_ref(Throwable, "message", "Ljava/lang/String;")
    local cause_field = self:get_field_ref(Throwable, "cause", "Ljava/lang/Throwable;")

    e:set_field(message_field, message)
    e:set_field(cause_field, cause)

    return e
end

function Jvm.throw_exception(self: t.Jvm, name: string, message: string?, cause: t.JvmObject?): never
    local e = self:create_exception(name, message, cause)
    error(e) -- Caught by the outer host if async, or the exec engine if inside bytecode
end

function Jvm.run(_self: t.Jvm, _main_path: string)
    util.unimplemented()
end

table.freeze(Jvm)

return Jvm
