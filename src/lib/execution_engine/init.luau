--!native

local dispatcher = require("@self/dispatcher")
local executor = require("@self/executor")
local frames = require("@self/frame")
local t = require("./t")

export type DispatchType = dispatcher.DispatchType
export type DispatchedMethodHandle = dispatcher.DispatchedMethodHandle

local execution_engine = {}

function execution_engine.dispatch(
    jvm: t.Jvm,
    method: t.MethodHandle,
    type: DispatchType,
    executing_class: t.JvmClass,
    executing_object: t.JvmObject?
): DispatchedMethodHandle
    return dispatcher.dispatch(jvm, method, type, executing_class, executing_object)
end

--[=[
    Invokes `method` synchronously without performing dispatch logic.
    You must call `execution_engine.dispatch` before this to get the correct method, regardless of dispatch type.
]=]
function execution_engine.invoke_sync(jvm: t.Jvm, method: DispatchedMethodHandle, args: t.Arguments): t.JvmValue
    local thread: t.Thread
    if jvm.current_thread then
        thread = jvm.current_thread
    else
        thread = jvm:create_thread(false, nil)
        thread.state = "runnable"
        jvm.current_thread = thread
    end

    local stack = thread.stack
    local this_frame = stack[#stack]
    if this_frame and this_frame.code.kind == "java" then
        jvm:_internal_error("attempt to use `execution_engine.invoke_sync` in Java context, use invoke_inline")
        error("^")
    end

    local invocation: t.Invocation = { state = "running" }
    frames.push_on(jvm, thread, method.method, invocation, args)
    local ok, value_or_error = executor(jvm, invocation)
    if not ok then
        error(value_or_error)
    end

    return value_or_error
end

return execution_engine
