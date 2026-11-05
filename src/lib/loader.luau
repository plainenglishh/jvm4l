local class_parser = require("./class_parser")
local dbg = require("./dbg")
local JvmClass = require("./entities/JvmClass")
local jcl_classfiles = require("./jcl_classfiles")
local jvm_type = require("./jvm_type")
local t = require("./t")
local native_methods = require("./native_methods")
local Lazy = require("./utilities/Lazy")

local function link_native(self: t.Jvm, class_name: string, signature: string): t.NativeMethod?
    return self._settings.link_native(class_name, signature)
        or (native_methods[class_name] and native_methods[class_name][signature])
end

local function add_members_from_classfile(
    jvm: t.Jvm,
    class: t.JvmClass,
    classfile: t.Classfile,
    defining_loader: t.JvmClassLoader
)
    local class_name = class_parser.class_name(classfile, class_parser.class(classfile, classfile.this_class))

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
                    catch_type = jvm:load_class(class_name, defining_loader)
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
                jit = nil,
            }
        end

        class:_add_method({
            name = name,
            descriptor = descriptor,
            signature = signature,
            code = code :: t.MethodCode,
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

    for _, field in classfile.fields do
        local name = class_parser.utf8_value(classfile, field.name_index)
        local descriptor = class_parser.utf8_value(classfile, field.descriptor_index)

        class:_add_field({
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
end

local ARRAY_METHODS: { t.MethodInfo } = {}

local function register_class(self: t.Jvm, defining_loader: t.JvmClassLoader, class: t.JvmClass)
    if not self._classes[defining_loader] then
        self._classes[defining_loader] = {}
    end

    self._classes[defining_loader][class.name] = class
end

local function assert_no_clinit(class: t.JvmClass)
    for i, v in class._methods do
        if v.name == "<clinit>" then
            error(
                "<clinit> cannot appear in this class. this is an issue with the Jvm4L JCL, not user code. contact the developer!"
            )
        end
    end

    if class.super then
        assert_no_clinit(class.super)
    end
end

local loader = {}

function loader.bootstrap_core_classes(jvm: t.Jvm)
    local object_classfile = class_parser.parse(jcl_classfiles["java/lang/Object"])
    local object = JvmClass._prepare(jvm, "bootstrap", "java/lang/Object", nil, {}, 0x0001, object_classfile)
    jvm._classes.bootstrap["java/lang/Object"] = object

    local class_classfile = class_parser.parse(jcl_classfiles["java/lang/Class"])
    local class = JvmClass._prepare(jvm, "bootstrap", "java/lang/Class", object, {}, 0x0001, class_classfile)
    jvm._classes.bootstrap["java/lang/Class"] = class

    add_members_from_classfile(jvm, object, object_classfile, "bootstrap")
    add_members_from_classfile(jvm, class, class_classfile, "bootstrap")

    local object_mirror = class:_new_uninitialised({ kind = "class", value = object })
    object._mirror = object_mirror

    local class_mirror = class:_new_uninitialised({ kind = "class", value = class })
    class._mirror = class_mirror

    jvm:load_class("java/lang/String")
    jvm:load_class("java/lang/Throwable")
    jvm:load_class("java/lang/Thread")
end

function loader.get_array_class(self: t.Jvm, name: string, initiating_loader: t.JvmClassLoader): t.JvmClass
    local element = string.sub(name, 2)
    local element_first_char = string.sub(element, 1, 1)

    local defining_loader: t.JvmClassLoader
    local element_class: t.JvmClass?
    if element_first_char == "[" then
        element_class = self:load_class(element, initiating_loader)
        defining_loader = element_class.loader
    elseif element_first_char == "L" then
        element_class = self:load_class(string.sub(element, 2, #element - 1), initiating_loader)
        defining_loader = element_class.loader
    else
        defining_loader = "bootstrap"
    end

    local Object = self._classes.bootstrap["java/lang/Object"]
    local class = JvmClass._prepare(self, defining_loader, name, Object, {}, 0x0001)
    for _, method in ARRAY_METHODS do
        class:_add_method(method)
    end
    register_class(self, defining_loader, class)
    dbg.trace(self, "created array class %s", name)
    return class
end

function loader.define_class(
    jvm: t.Jvm,
    classfile: buffer,
    defining_loader: t.JvmClassLoader,
    proto_class: t.JvmClass?
): t.JvmClass
    local parse_ok, classfile = pcall(class_parser.parse, classfile)
    if not parse_ok then
        jvm:throw_exception("java/lang/ClassFormatError", tostring(classfile))
    end

    local this_class_info = class_parser.class(classfile, classfile.this_class)
    local this_class_name = class_parser.class_name(classfile, this_class_info)

    assert(classfile.super_class ~= 0, "given classfile has no super class")

    local super_class_info = class_parser.class(classfile, classfile.super_class)
    local super_class_name = class_parser.class_name(classfile, super_class_info)
    local super_class = jvm:load_class(super_class_name, defining_loader)

    local implements = {}
    for _, interface_idx in classfile.interfaces do
        local interface_info = class_parser.class(classfile, interface_idx)
        local interface_name = class_parser.class_name(classfile, interface_info)
        local interface = jvm:load_class(interface_name, defining_loader)
        table.insert(implements, interface)
    end

    local source_file = class_parser.get_sourcefile_attribute(classfile)

    local class = proto_class
        or JvmClass._prepare(
            jvm,
            defining_loader,
            this_class_name,
            super_class,
            implements,
            classfile.access_flags,
            classfile,
            source_file
        )
    register_class(jvm, defining_loader, class)
    add_members_from_classfile(jvm, class, classfile, defining_loader)

    if
        defining_loader == "bootstrap"
        and (
            class.name == "java/lang/Object"
            or class.name == "java/lang/Throwable"
            or class:inherits_from(jvm:load_class("java/lang/Throwable", "bootstrap"))
        )
    then
        assert_no_clinit(class)
    end

    dbg.trace(jvm, "loaded class %s from loader %*", this_class_name, defining_loader)
    return class
end

return loader
