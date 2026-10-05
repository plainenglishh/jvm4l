local t = require("./t")

local native_methods: { [string]: { [string]: t.NativeMethod } } = {}

native_methods["java/lang/Object"] = {
    ["hashCode:()I"] = function(_jvm: t.Jvm, this: t.JvmObject)
        return this.hash_code
    end,
}

native_methods["java/lang/Throwable"] = {
    ["fillInBacktrace:(I)V"] = function(jvm: t.Jvm, this: t.JvmObject, skip: number)
        local stack: { t.StackFrame } = {}

        if jvm.current_thread then
            table.move(jvm.current_thread._stack, 1, #jvm.current_thread._stack - skip, 1, stack)
        end

        this._magic = { kind = "throwable", stack = stack }
    end,

    ["fillInStackTrace:()Ljava/lang/Throwable;"] = function(jvm: t.Jvm, this: t.JvmObject): t.JvmObject
        local Throwable = jvm:resolve_class("java/lang/Throwable")

        local StackTraceElement = jvm:resolve_class("java/lang/StackTraceElement")
        local stacktrace_ref = jvm:get_field_ref(Throwable, "stacktrace", "[Ljava/lang/StackTraceElement;")
        local declaring_class_ref = jvm:get_field_ref(StackTraceElement, "declaringClass", "Ljava/lang/String;")
        local method_name_ref = jvm:get_field_ref(StackTraceElement, "methodName", "Ljava/lang/String;")

        local magic = this._magic
        assert(magic and magic.kind == "throwable")
        local trace: { t.JvmValue } = {}

        local stack_depth = #magic.stack
        for i = 1, stack_depth - 1 do
            local frame = magic.stack[i]

            local elem = StackTraceElement:new_uninitialised()
            elem:set_field(declaring_class_ref, jvm:create_string(frame.class.name))
            elem:set_field(method_name_ref, jvm:create_string(frame.method.name))

            trace[#trace + 1] = elem
        end

        this:set_field(stacktrace_ref, jvm:create_array(StackTraceElement, trace))

        return this
    end,
}

native_methods["jvm4l/Luau"] = {
    ["print:([Ljava/lang/Object;)V"] = function(_jvm: t.Jvm, objects: t.JvmObject)
        print(unpack(objects:get_array_elements()))
    end,
}

native_methods["jvm4l/Luau"] = {
    ["error:(Ljava/lang/Object;I)V"] = function(_jvm: t.Jvm, o: t.JvmObject, level: t.JvmInt)
        error(o, level)
    end,
}

return native_methods
