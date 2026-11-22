local t = require("./t")

local native_methods: { [string]: { [string]: t.NativeMethodStep } } = {}

native_methods["java/lang/Object"] = {
    ["hashCode:()I"] = function(_jvm: t.Jvm, ctx: t.NativeContext, this: t.JvmObject): (t.StepExitReason, t.JvmValue)
        return "return", this.hash_code
    end,
}

native_methods["java/lang/String"] = {
    ["replace:(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"] = function(
        jvm: t.Jvm,
        ctx: t.NativeContext,
        this: t.JvmObject,
        match: t.JvmObject,
        other: t.JvmObject
    ): (t.StepExitReason, t.JvmValue)
        local this = this:inner_string()
        local match = match:inner_string()
        local replacement = other:inner_string()
        local new = string.gsub(this, match, replacement)
        return "return", jvm:create_string(new)
    end,

    ["concat:(Ljava/lang/String;)Ljava/lang/String;"] = function(
        jvm: t.Jvm,
        ctx: t.NativeContext,
        this: t.JvmObject,
        other: t.JvmObject
    ): (t.StepExitReason, t.JvmValue)
        local this = this:inner_string()
        local other = other:inner_string()
        return "return", jvm:create_string(this .. other)
    end,
}

native_methods["java/lang/Throwable"] = {
    ["fillInBacktrace:(I)V"] = function(
        jvm: t.Jvm,
        ctx: t.NativeContext,
        this: t.JvmObject,
        skip: number
    ): (t.StepExitReason, t.JvmValue)
        local stack: { t.StackFrame } = {}

        if jvm.current_thread then
            table.move(jvm.current_thread.stack, 1, #jvm.current_thread.stack - skip, 1, stack)
        end

        this._magic = { kind = "throwable", stack = stack }
        return "return", jvm.null
    end,

    ["fillInStackTrace:()Ljava/lang/Throwable;"] = function(
        jvm: t.Jvm,
        ctx: t.NativeContext,
        this: t.JvmObject
    ): (t.StepExitReason, t.JvmValue)
        local Throwable = jvm:load_class("java/lang/Throwable")

        local StackTraceElement = jvm:load_class("java/lang/StackTraceElement")
        local stacktrace_ref = Throwable:resolve_field("stacktrace", "[Ljava/lang/StackTraceElement;")
        local declaring_class_ref = StackTraceElement:resolve_field("declaringClass", "Ljava/lang/String;")
        local method_name_ref = StackTraceElement:resolve_field("methodName", "Ljava/lang/String;")

        local magic = this._magic
        assert(magic and magic.kind == "throwable")
        local trace: { t.JvmValue } = {}

        local stack_depth = #magic.stack
        for i = 1, stack_depth - 1 do
            local frame = magic.stack[i]

            local elem = StackTraceElement:_new_uninitialised()
            elem:set_field(declaring_class_ref, jvm:create_string(frame.method.class.name))
            elem:set_field(method_name_ref, jvm:create_string(frame.method.info.name))

            trace[#trace + 1] = elem
        end

        this:set_field(stacktrace_ref, jvm:create_array(StackTraceElement, trace))

        return "return", this
    end,
}

native_methods["jvm4l/luau/Globals"] = {
    ["print:([Ljava/lang/Object;)V"] = function(
        jvm: t.Jvm,
        ctx: t.NativeContext,
        objects: t.JvmObject
    ): (t.StepExitReason, t.JvmValue)
        print(unpack(objects:get_array_elements()))
        return "return", jvm.null
    end,

    ["error:(Ljava/lang/Object;I)V"] = function(
        _jvm: t.Jvm,
        ctx: t.NativeContext,
        o: t.JvmObject,
        level: t.JvmInt
    ): (t.StepExitReason, t.JvmValue)
        return "return", error(o, level)
    end,
}

return native_methods
