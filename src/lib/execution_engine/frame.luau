local jvm_type = require("../jvm_type")
local t = require("../t")

local frame = {}

function frame.push_on(
    jvm: t.Jvm,
    thread: t.Thread,
    class: t.JvmClass,
    method: t.MethodInfo,
    invocation: t.Invocation?,
    args: { t.JvmValue }
)
    local frame: t.StackFrame
    if method.code.kind == "java" then
        local locals: { any } = table.create(method.code.max_locals)

        local current_arg = 1
        local current_local = 1

        if not method.static then
            locals[current_local] = args[current_arg]
            current_arg += 1
            current_local += 1
        end

        for _, arg in method.type:get().arguments do
            local val = args[current_arg]
            locals[current_local] = val

            local slots = jvm_type.slots_of(arg)
            if slots == "2" then
                current_local += 1
                locals[current_local] = nil -- holes are fine here
            end

            current_arg += 1
            current_local += 1
        end

        frame = {
            method = method,
            class = class,
            loader = class.loader,
            code = method.code,
            stack = table.create(method.code.max_stack),
            stack_top = 0,
            locals = locals,
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

    jvm:_trace(`pushed frame #{#thread.stack + 1} on thread #{thread.id} ({class.fqcn}.{method.signature})`)

    table.insert(thread.stack, frame)
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
