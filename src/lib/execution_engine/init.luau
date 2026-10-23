--!native

local executor = require("@self/executor")
local frames = require("@self/frame")
local t = require("./t")

local execution_engine = {}

--[=[
    Begins synchronous execution on the given method.
]=]
function execution_engine.invoke_on_sync(
    jvm: t.Jvm,
    thread: t.Thread,
    class: t.JvmClass,
    method: t.MethodInfo,
    args: { t.JvmValue }
): (boolean, ...t.JvmValue)
    if method.code.kind == "abstract" then
        jvm:throw_exception("java/lang/AbstractMethodError", method.descriptor)
        error("^")
    end

    local stack = thread.stack
    local this_frame = stack[#stack]
    if this_frame and this_frame.code.kind == "java" then
        jvm:throw_exception(
            "java/lang/InternalError",
            "attempt to use invoke_on_sync in Java context, use invoke_inline"
        )
        error("^")
    end

    local invocation: t.Invocation = { state = "running" }
    frames.push_on(thread, class, method, invocation, args)
    return executor(jvm, invocation)
end

function execution_engine.invoke_sync(
    jvm: t.Jvm,
    class: t.JvmClass,
    method: t.MethodInfo,
    args: { t.JvmValue }
): (boolean, ...t.JvmValue)
    return execution_engine.invoke_on_sync(jvm, jvm.current_thread, class, method, args)
end

return execution_engine
