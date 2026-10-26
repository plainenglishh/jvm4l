local class_parser = require("../class_parser")
local jvm_type = require("../jvm_type")
local jcl_classfiles = require("../jcl_classfiles")
local native_methods = require("../native_methods")
local t = require("../t")
local util = require("../util")
local GarbageCollector = require("../GarbageCollector")
local Lazy = require("../Lazy")
local dbg = require("../dbg")
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
    return (native_methods[class_name] and native_methods[class_name][signature])
        or self._settings.link_native(class_name, signature)
end

local function get_members(
    jvm: t.Jvm,
    classfile: t.Classfile,
    defining_loader: t.JvmClassLoader
): ({ t.MethodInfo }, { t.FieldInfo })
    local class_name = class_parser.class_name(classfile, class_parser.class(classfile, classfile.this_class))

    local methods: { t.MethodInfo } = {}

    for _, method in classfile.methods do
        local name = class_parser.utf8_value(classfile, method.name_index)
        local descriptor = class_parser.utf8_value(classfile, method.descriptor_index)
        local signature = `{name}:{descriptor}`
        local native = bit32.band(method.access_flags, 0x0100) ~= 0
        local abstract = bit32.band(method.access_flags, 0x0400) ~= 0

        local code: t.MethodCode
        if native then
            local native_method = link_native(jvm, class_name, signature)
                or jvm:throw_exception(
                    "java/lang/UnsatisfiedLinkError",
                    `unable to link native method {class_name}.{signature}`
                )

            code = {
                kind = "luau",
                closure = native_method,
            }
        elseif abstract then
            code = { kind = "abstract" }
        else
            local code_attribute = class_parser.get_code_attribute(classfile, method)
                or jvm:throw_exception("java/lang/ClassFormatError")

            local exceptions = {}

            for _, exception_info in code_attribute.exceptions do
                local catch_type = nil
                if exception_info.catch_type ~= 0 then
                    local class_info = class_parser.class(classfile, exception_info.catch_type)
                    local class_name = class_parser.class_name(classfile, class_info)
                    catch_type = jvm:resolve_class(class_name, defining_loader)
                end

                table.insert(exceptions, {
                    start_pc = exception_info.start_pc,
                    end_pc = exception_info.end_pc,
                    handler_pc = exception_info.handler_pc,
                    catch_type = catch_type,
                })
            end

            local line_numbers = class_parser.get_line_number_table_attribute(classfile, code_attribute)

            code = {
                kind = "java",
                max_stack = code_attribute.max_stack,
                max_locals = code_attribute.max_locals,
                code = code_attribute.code,
                exceptions = exceptions,
                line_numbers = line_numbers,
            }
        end

        table.insert(methods, {
            name = name,
            descriptor = descriptor,
            signature = signature,
            code = code,
            type = Lazy.new(function()
                return jvm_type.resolve_method_descriptor(jvm, descriptor, defining_loader)
            end),

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
        local name = class_parser.utf8_value(classfile, field.name_index)
        local descriptor = class_parser.utf8_value(classfile, field.descriptor_index)

        table.insert(fields :: { any }, {
            name = name,
            descriptor = descriptor,
            signature = `{name}:{descriptor}`,
            type = Lazy.new(function()
                local value = jvm_type.resolve_field_descriptor(jvm, descriptor, defining_loader)
                return value
            end),

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
    local object_methods, object_fields = get_members(self, object_classfile, "bootstrap")

    local object = JvmClass._prepare(
        self,
        "bootstrap",
        "java/lang/Object",
        nil,
        {},
        object_methods,
        object_fields,
        0x0001,
        object_classfile
    )
    self._classes.bootstrap["java/lang/Object"] = object

    local class_classfile = class_parser.parse(jcl_classfiles["java/lang/Class"])
    local class_methods, class_fields = get_members(self, class_classfile, "bootstrap")

    local class = JvmClass._prepare(
        self,
        "bootstrap",
        "java/lang/Class",
        object,
        {},
        class_methods,
        class_fields,
        0x0001,
        class_classfile
    )
    self._classes.bootstrap["java/lang/Class"] = class

    local object_mirror = class:_new_uninitialised({ kind = "class", value = object })
    object._mirror = object_mirror

    local class_mirror = class:_new_uninitialised({ kind = "class", value = class })
    class._mirror = class_mirror

    self:resolve_class("java/lang/String")
    self:resolve_class("java/lang/Throwable")
    self:resolve_class("java/lang/Thread")
end

function Jvm.new(into_settings: t.IntoJvmSettings): t.Jvm
    local settings = {
        quantum = into_settings.quantum or 500,
        interrupt = into_settings.interrupt,
        link_native = into_settings.link_native,
        trace = into_settings.trace,
    }

    local self: t.Jvm = setmetatable({
        _settings = settings,
        _classes = {
            bootstrap = {},
        },
        _threads = {},
        _next_thread_id = 0,
        current_thread = nil,
        _exec_depth = 0,
        _gc = (nil :: any) :: t.GarbageCollector,
        _interned_strings = {},
        _interned_field_handles = {},
        _interned_method_handles = {},
    }, Jvm)

    self._gc = GarbageCollector._new(self)
    bootstrap_core_classes(self)

    return self
end

function Jvm._interrupt(self: t.Jvm)
    if self._settings.interrupt then
        self._settings.interrupt(self)
    end
end

function Jvm.create_thread(self: t.Jvm, daemon: boolean, runnable: t.MethodInfo?): t.Thread
    local thread: t.Thread = {
        id = self._next_thread_id,
        stack = {},
        state = "new",
        daemon = daemon,
        mirror = (nil :: any) :: t.JvmObject,
        budget = 0,
    }
    self._next_thread_id += 1
    local mirror = self._classes.bootstrap["java/lang/Thread"]:_new_uninitialised({ kind = "thread", value = thread })
    thread.mirror = mirror

    if runnable then
        util.unimplemented("runnable thread targets not yet implemented")
    end

    table.insert(self._threads, thread)
    dbg.trace(self, "created thread #%i", thread.id)
    return thread
end

function Jvm.get_loader(self: t.Jvm): t.JvmClassLoader
    local thread = self.current_thread
    if not thread or #thread.stack == 0 then
        return "bootstrap"
    end

    local root_frame = thread.stack[#thread.stack]
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
    local element_class: t.JvmClass?
    if element_first_char == "[" then
        element_class = self:resolve_class(element, initiating_loader)
        defining_loader = element_class.loader
    elseif element_first_char == "L" then
        element_class = self:resolve_class(string.sub(element, 2, #element - 1), initiating_loader)
        defining_loader = element_class.loader
    else
        defining_loader = "bootstrap"
    end

    local Object = self._classes.bootstrap["java/lang/Object"]
    local class = JvmClass._prepare(self, defining_loader, name, Object, {}, ARRAY_METHODS, {}, 0x0001)
    register_class(self, defining_loader, class)
    dbg.trace(self, "created array class %s", name)
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
            self:internal_error("attempt to get uninitialised core class? how did you reach this point?")
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
    return self:get_class(name, initiating_loader) or self:throw_exception("java/lang/NoClassDefFoundError", name)
end

function Jvm.define_class(self: t.Jvm, classfile: buffer, defining_loader: t.JvmClassLoader): t.JvmClass
    local parse_ok, classfile = pcall(class_parser.parse, classfile)
    if not parse_ok then
        self:throw_exception("java/lang/ClassFormatError", tostring(classfile))
    end

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

    local methods, fields = get_members(self, classfile, defining_loader)
    local source_file = class_parser.get_sourcefile_attribute(classfile)

    local class = JvmClass._prepare(
        self,
        defining_loader,
        this_class_name,
        super_class,
        implements,
        methods,
        fields,
        classfile.access_flags,
        classfile,
        source_file
    )
    register_class(self, defining_loader, class)

    dbg.trace(self, "loaded class %s from loader %*", this_class_name, defining_loader)

    return class
end

local function get_interned_field(jvm: t.Jvm, class: t.JvmClass, name: string, descriptor: string): t.FieldHandle?
    local by_class = jvm._interned_field_handles[class]
    if not by_class then
        return nil
    end

    local by_name = by_class[name]
    if not by_name then
        return nil
    end

    return by_name[descriptor]
end

local function set_interned_field(jvm: t.Jvm, class: t.JvmClass, name: string, descriptor: string, field: t.FieldHandle)
    local by_class = jvm._interned_field_handles[class]
    if not by_class then
        by_class = {}
        jvm._interned_field_handles[class] = by_class
    end

    local by_name = by_class[name]
    if not by_name then
        by_name = {}
        by_class[name] = by_name
    end

    by_name[descriptor] = field
end

local function create_interned_field_handle(class: t.JvmClass, field_info: t.FieldInfo): t.FieldHandle
    local handle: t.FieldHandle = table.freeze({
        class = class,
        field_info = field_info,
    })

    set_interned_field(class.jvm, class, field_info.name, field_info.descriptor, handle)
    return handle
end

function Jvm.resolve_field(self: t.Jvm, class: t.JvmClass, name: string, descriptor: string): t.FieldHandle
    local interned_field = get_interned_field(self, class, name, descriptor)
    if interned_field then
        return interned_field
    end

    for _, field in class._fields do
        if field.name == name and field.descriptor == descriptor then
            -- CHECK ACCESS
            return create_interned_field_handle(class, field)
        end
    end

    local function deep_search_field(class_or_interface: t.JvmClass): (t.JvmClass?, t.FieldInfo?)
        for _, field in class_or_interface._fields do
            if field.name == name and field.descriptor == descriptor then
                return class_or_interface, field
            end
        end

        for _, interface in class_or_interface.interfaces do
            local found_class, found_field = deep_search_field(interface)
            if found_class and found_field then
                return found_class, found_field
            end
        end

        return nil, nil
    end

    for _, interface in class.interfaces do
        local found_class, found_field = deep_search_field(interface)
        if found_class and found_field then
            -- CHECK ACCESS
            return create_interned_field_handle(found_class, found_field)
        end
    end

    local current = class.super
    while current do
        for _, field in current._fields do
            if field.name == name and field.descriptor == descriptor then
                -- CHECK ACCESS
                return create_interned_field_handle(current, field)
            end
        end
        current = current.super
    end

    return self:throw_exception("java/lang/NoSuchFieldError", `{class.fqcn} has no field {name}:{descriptor}`)
end

local function get_interned_method(jvm: t.Jvm, class: t.JvmClass, name: string, descriptor: string): t.MethodHandle?
    local by_class = jvm._interned_method_handles[class]
    if not by_class then
        return nil
    end

    local by_name = by_class[name]
    if not by_name then
        return nil
    end

    return by_name[descriptor]
end

local function set_interned_method(
    jvm: t.Jvm,
    class: t.JvmClass,
    name: string,
    descriptor: string,
    field: t.MethodHandle
)
    local by_class = jvm._interned_method_handles[class]
    if not by_class then
        by_class = {}
        jvm._interned_field_handles[class] = by_class
    end

    local by_name = by_class[name]
    if not by_name then
        by_name = {}
        by_class[name] = by_name
    end

    by_name[descriptor] = field
end

local function create_interned_method_handle(class: t.JvmClass, method_info: t.MethodInfo): t.MethodHandle
    local handle: t.MethodHandle = table.freeze({
        class = class,
        info = method_info,
    })

    set_interned_method(class.jvm, class, method_info.name, method_info.descriptor, handle)
    return handle
end

function Jvm._create_method_handle(self: t.Jvm, class: t.JvmClass, method_info: t.MethodInfo): t.MethodHandle
    return get_interned_method(self, class, method_info.name, method_info.descriptor)
        or create_interned_method_handle(class, method_info)
end

function Jvm.resolve_method(self: t.Jvm, class: t.JvmClass, name: string, descriptor: string): t.MethodHandle
    local interned_method = get_interned_method(self, class, name, descriptor)
    if interned_method then
        return interned_method
    end

    if class.interface then
        return self:throw_exception("java/lang/IncompatibleClassChangeError", `{class.fqcn} is an interface`)
    end

    for _, method in class._methods do
        if method.name == name and method.descriptor == descriptor then
            -- CHECK ACCESS
            return create_interned_method_handle(class, method)
        end
    end

    local current = class.super
    while current do
        for _, method in current._methods do
            if method.name == name and method.descriptor == descriptor then
                -- CHECK ACCESS
                return create_interned_method_handle(current, method)
            end
        end
        current = current.super
    end

    local function deep_search_interface_method(class_or_interface: t.JvmClass): (t.JvmClass?, t.MethodInfo?)
        for _, interface in class_or_interface.interfaces do
            for _, method in interface._methods do
                if method.name == name and method.descriptor == descriptor then
                    return interface, method
                end
            end
            local found_class, found_method = deep_search_interface_method(interface)
            if found_class and found_method then
                return found_class, found_method
            end
        end
        return nil, nil
    end

    local found_class, found_method = deep_search_interface_method(class)
    if found_class and found_method then
        -- CHECK ACCESS HERE
        return create_interned_method_handle(found_class, found_method)
    end

    return self:throw_exception("java/lang/NoSuchMethodError", `{class.fqcn} has no method {name}{descriptor}`)
end

function Jvm.create_string(self: t.Jvm, value: string): t.JvmObject
    if self._interned_strings[value] then
        return self._interned_strings[value]
    end

    local String = self._classes.bootstrap["java/lang/String"]
    local str_obj = String:_new_uninitialised({ kind = "string", value = value })
    self._interned_strings[value] = str_obj
    return str_obj
end

function Jvm.create_array(self: t.Jvm, element: t.JvmType, size_or_values: number | { t.JvmValue }): t.JvmObject
    local elem_descriptor = jvm_type.type_to_descriptor(element)
    local class_name = `[{elem_descriptor}`
    local class = self:resolve_class(class_name)

    local size = if type(size_or_values) == "number" then size_or_values else #size_or_values

    local array = class:_new_uninitialised({
        kind = "array",
        element = element,
        length = size,
        values = table.create(size, nil :: any),
    })

    if type(size_or_values) == "table" then
        for i = 1, size do
            array:set_array_element(i - 1, size_or_values[i])
        end
    end

    return array
end

function Jvm.create_exception(
    self: t.Jvm,
    name: string,
    message: string?,
    cause: t.JvmObject?,
    dont_capture_stack: boolean?
): t.JvmObject
    local Exception = self:resolve_class(name)
    local message = if message then self:create_string(message) else nil

    local magic: t._MagicValue?
    if (not dont_capture_stack) and self.current_thread then
        magic = { kind = "throwable", stack = table.clone(self.current_thread.stack) }
    end

    local e = Exception:_new_uninitialised(magic)

    local Throwable = self._classes.bootstrap["java/lang/Throwable"]
    local message_field = self:resolve_field(Throwable, "message", "Ljava/lang/String;")
    local cause_field = self:resolve_field(Throwable, "cause", "Ljava/lang/Throwable;")

    e:set_field(message_field, message)
    e:set_field(cause_field, cause)

    return e
end

function Jvm.throw_exception(
    self: t.Jvm,
    name: string,
    message: string?,
    cause: t.JvmObject?,
    dont_capture_stack: boolean?
): never
    local e = self:create_exception(name, message, cause, dont_capture_stack)
    error(e, 0) -- Caught by the outer host if async, or the exec engine if inside bytecode
end

function Jvm.create_internal_error(self: t.Jvm, message: string, level: number?): t.JvmObject
    local traceback = debug.traceback(nil, (level or 1) + 1)
    message ..= ` ({dbg.vm_info(self)})`

    local cause =
        self:create_exception("jvm4l/luau/LuauError", message .. "\n    " .. traceback:gsub("\n", "\n    "), nil, true)
    return self:create_exception("java/lang/InternalError", message, cause)
end

function Jvm.internal_error(self: t.Jvm, message: string, level: number?): never
    error(self:create_internal_error(message, level), -1)
end

function Jvm.coerce(self: t.Jvm, ...: t.IntoJvmValue): ...t.JvmValue
    local count = select("#", ...)
    local values: { t.JvmValue } = table.create(count, nil :: any)

    for i = 1, count do
        local value = select(i, ...)

        if type(value) == "boolean" then
            value = if value then 1 else 0
        elseif type(value) == "string" then
            value = self:create_string(value)
        end

        values[i] = value
    end

    return unpack(values)
end

function Jvm.run(self: t.Jvm, main_path: string, args: { t.JvmValue })
    util.unimplemented()
end

table.freeze(Jvm)

return Jvm
