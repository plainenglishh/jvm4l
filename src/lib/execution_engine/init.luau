--!native

local executor = require("@self/executor")
local frames = require("@self/frame")
local t = require("./t")

local execution_engine = {}

--[=[
    Begins synchronous execution on the given method.
]=]
function execution_engine.invoke(
    jvm: t.Jvm,
    class: t.JvmClass,
    method: t.MethodInfo,
    ...: t.JvmValue
): (boolean, ...t.JvmValue)
    if method.code.kind == "abstract" then
        jvm:throw_exception("java/lang/AbstractMethodError", method.descriptor)
        error("^")
    end

    local thread = jvm.current_thread
    local stack = thread.stack
    local this_frame = stack[#stack]
    if this_frame and this_frame.code.kind == "java" then
        jvm:throw_exception("java/lang/InternalError", "attempt to use invoke_sync in Java context, use invoke_inline")
        error("^")
    end

    local invocation: t.Invocation = { state = "running" }
    frames.push_on(stack, class, method, invocation, ...)
    return executor(jvm, invocation)
end

return execution_engine
