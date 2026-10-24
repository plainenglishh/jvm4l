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
    method: t.MethodHandle,
    args: { t.JvmValue }
): (boolean, ...t.JvmValue)
    local method_info = method.method_info
    if method_info.code.kind == "abstract" then
        jvm:throw_exception("java/lang/AbstractMethodError", method_info.descriptor)
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
    frames.push_on(jvm, thread, method, invocation, args)
    return executor(jvm, invocation)
end

function execution_engine.invoke_sync(
    jvm: t.Jvm,
    method: t.MethodHandle,
    args: { t.JvmValue }
): (boolean, ...t.JvmValue)
    return execution_engine.invoke_on_sync(jvm, jvm.current_thread, method, args)
end

return execution_engine
