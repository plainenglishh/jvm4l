local t = require("../t")

local frame = {}

function frame.push_on(
    stack: { t.StackFrame },
    class: t.JvmClass,
    method: t.MethodInfo,
    invocation: t.Invocation?,
    ...: t.JvmValue
)
    local args = { ... }
    local frame: t.StackFrame
    if method.code.kind == "java" then
        frame = {
            method = method,
            class = class,
            loader = class.loader,
            code = method.code,
            stack = {},
            locals = args,
            pc = 0,
            start_pc = 0,
            invocation = invocation,
        } :: t.StackFrame
    elseif method.code.kind == "luau" then
        frame = {
            method = method,
            class = class,
            loader = class.loader,
            code = method.code,
            args = args,
            invocation = invocation,
        } :: t.StackFrame
    end

    table.insert(stack, frame)
end

function frame.current(jvm: t.Jvm): (t.Thread, t.StackFrame?)
    local current_thread = jvm.current_thread
    local current_frame = current_thread.stack[#current_thread.stack]
    return current_thread, current_frame
end

--- Marks an invocation as complete.
local function complete_invocation(invocation: t.Invocation, value: t.JvmValue)
    assert(invocation.state == "running")
    local invocation = invocation :: any
    invocation.state = "complete"
    invocation.value = value
end

--[=[
    Completes the most recent frame, returning `value`.
]=]
function frame.return_from_current_frame(thread: t.Thread, count: number, value: t.JvmValue)
    local stack = thread.stack
    local frame = stack[#stack]
    local parent_frame = stack[#stack - 1]

    if frame.invocation then
        complete_invocation(frame.invocation, value)
    end

    stack[#stack] = nil

    if parent_frame and parent_frame.code.kind == "java" and count == 1 then
        table.insert(parent_frame.stack, value)
    end
end

function frame.fail_invocation(invocation: t.Invocation, exception: t.JvmObject)
    assert(invocation.state == "running")
    local invocation = invocation :: any
    invocation.state = "failed"
    invocation.exception = exception
end

return frame
