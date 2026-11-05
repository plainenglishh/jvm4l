local jvm_type = require("../jvm_type")
local jcl_classfiles = require("../jcl_classfiles")
local t = require("../t")
local util = require("../util")
local GarbageCollector = require("../GarbageCollector")
local dbg = require("../dbg")
local loader = require("../loader")

local Jvm = {}

Jvm.__type = "Jvm"
Jvm.__index = Jvm

function Jvm.__tostring(_self: t.Jvm): string
    return "<Jvm>"
end

function Jvm.__display(self: t.Jvm): string
    return tostring(self)
end

function Jvm.new(into_settings: t.IntoJvmSettings): t.Jvm
    local settings = {
        quantum = into_settings.quantum or 500,
        interrupt = into_settings.interrupt,
        link_native = into_settings.link_native,
        trace = into_settings.trace,
        dump = into_settings.dump,
        jit_load = into_settings.jit_load,
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
    loader.bootstrap_core_classes(self)

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

function Jvm.load_class(self: t.Jvm, name: string, initiating_loader: t.JvmClassLoader?): t.JvmClass
    local initiating_loader: t.JvmClassLoader = initiating_loader or self:get_loader()

    if self._classes[initiating_loader][name] then
        return self._classes[initiating_loader][name]
    end

    if string.sub(name, 1, 1) == "[" then
        return loader.get_array_class(self, name, initiating_loader)
    end

    if initiating_loader == "bootstrap" then
        if name == "java/lang/Object" or name == "java/lang/Class" then
            self:_internal_error("attempt to get uninitialised core class? how did you reach this point?")
        end

        local classfile = jcl_classfiles[name]
        if not classfile then
            return self:throw_exception("java/lang/NoClassDefFoundError", name)
        end

        return self:define_class(classfile, initiating_loader)
    end

    local fqcn = name:gsub("/", ".")
    local loadClass = initiating_loader.class:resolve_method("loadClass", "(Ljava/lang/String;)Ljava/lang/Class")
    local class_o = initiating_loader:invoke(loadClass, self:create_string(fqcn))
    assert(type(class_o) == "table")
    return class_o:inner_class()
end

function Jvm.define_class(self: t.Jvm, classfile: buffer, defining_loader: t.JvmClassLoader): t.JvmClass
    return loader.define_class(self, classfile, defining_loader)
end

function Jvm._get_interned_field(self: t.Jvm, class: t.JvmClass, name: string, descriptor: string): t.FieldHandle?
    local by_class = self._interned_field_handles[class]
    if not by_class then
        return nil
    end

    local by_name = by_class[name]
    if not by_name then
        return nil
    end

    return by_name[descriptor]
end

function Jvm._create_interned_field(self: t.Jvm, class: t.JvmClass, field_info: t.FieldInfo): t.FieldHandle
    local interned = self:_get_interned_field(class, field_info.name, field_info.descriptor)
    if interned then
        return interned
    end

    local handle: t.FieldHandle = table.freeze({
        class = class,
        info = field_info,
    })

    local by_class = self._interned_field_handles[class]
    if not by_class then
        by_class = {}
        self._interned_field_handles[class] = by_class
    end

    local by_name = by_class[field_info.name]
    if not by_name then
        by_name = {}
        by_class[field_info.name] = by_name
    end

    by_name[field_info.descriptor] = handle

    return handle
end

function Jvm._get_interned_method(self: t.Jvm, class: t.JvmClass, name: string, descriptor: string): t.MethodHandle?
    local by_class = self._interned_method_handles[class]
    if not by_class then
        return nil
    end

    local by_name = by_class[name]
    if not by_name then
        return nil
    end

    return by_name[descriptor]
end

function Jvm._create_interned_method(self: t.Jvm, class: t.JvmClass, method_info: t.MethodInfo): t.MethodHandle
    local interned = self:_get_interned_method(class, method_info.name, method_info.descriptor)
    if interned then
        return interned
    end

    local handle: t.MethodHandle = table.freeze({
        class = class,
        info = method_info,
    })

    local by_class = self._interned_method_handles[class]
    if not by_class then
        by_class = {}
        self._interned_method_handles[class] = by_class
    end

    local by_name = by_class[method_info.name]
    if not by_name then
        by_name = {}
        by_class[method_info.name] = by_name
    end

    by_name[method_info.descriptor] = handle

    return handle
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
    local class = self:load_class(class_name)

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
    skip_stack_capture: boolean?
): t.JvmObject
    local root_package = string.match(name, "(.-)/")
    if root_package ~= "java" and root_package ~= "jvm4l" then
        error("only JCL exceptions can be created via `Jvm.create_exception`.")
    end

    local Exception = self:load_class(name, "bootstrap")
    local message = if message then self:create_string(message) else nil

    local magic: t._MagicValue?
    if (not skip_stack_capture) and self.current_thread then
        magic = { kind = "throwable", stack = table.clone(self.current_thread.stack) }
    end

    local e = Exception:_new_uninitialised(magic)

    local Throwable = self._classes.bootstrap["java/lang/Throwable"]
    local message_field = Throwable:resolve_field("message", "Ljava/lang/String;")
    local cause_field = Throwable:resolve_field("cause", "Ljava/lang/Throwable;")

    e:set_field(message_field, message)
    e:set_field(cause_field, cause)

    return e
end

function Jvm.throw_exception(
    self: t.Jvm,
    name: string,
    message: string?,
    cause: t.JvmObject?,
    skip_stack_capture: boolean?
): never
    print(`{name}: {message}`)
    local e = self:create_exception(name, message, cause, skip_stack_capture)
    error(e, 0) -- Caught by the outer host if async, or the exec engine if inside bytecode
end

function Jvm._create_internal_error(self: t.Jvm, message: string, level: number?): t.JvmObject
    local traceback = debug.traceback(nil, (level or 1) + 1)
    message ..= ` ({dbg.vm_info(self)})`

    local cause =
        self:create_exception("jvm4l/luau/LuauError", message .. "\n    " .. traceback:gsub("\n", "\n    "), nil, true)
    return self:create_exception("java/lang/InternalError", message, cause)
end

function Jvm._internal_error(self: t.Jvm, message: string, level: number?): never
    error(self:_create_internal_error(message, level), 0)
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

function Jvm.run(self: t.Jvm, main_path: string, ...: t.JvmValue)
    local ApplicationClassLoader = self:load_class("jvm4l/ApplicationClassLoader")
    local ApplicationClassLoader_new = ApplicationClassLoader:resolve_method("<init>", "(Ljava/lang/ClassLoader;)V")
    local acl = ApplicationClassLoader:new(ApplicationClassLoader_new, nil)
    print(acl)
end

table.freeze(Jvm)

return Jvm
