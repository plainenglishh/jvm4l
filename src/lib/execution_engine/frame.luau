local dbg = require("../dbg")
local jvm_type = require("../jvm_type")
local t = require("../t")
local typechecker = require("../typechecker")

local frame = {}

function frame.push_on(
    jvm: t.Jvm,
    thread: t.Thread,
    method: t.MethodHandle,
    invocation: t.Invocation?,
    args: t.Arguments
)
    local frame: t.StackFrame
    local method_info = method.info
    local class = method.class

    if not typechecker.check_method(jvm, args, class, method_info) then
        jvm:throw_exception("java/lang/IncompatibleClassChangeError", "typechecking failed")
    end

    if method_info.code.kind == "java" then
        local locals: { any } = table.create(method_info.code.max_locals)

        local current_arg = 1
        local current_local = 1

        if not method_info.static then
            local this = args[current_arg]
            locals[current_local] = this
            current_arg += 1
            current_local += 1
        end

        for i, arg in method_info.type:get().arguments do
            local val = args[current_arg]
            locals[current_local] = val

            local words = jvm_type.words(arg)
            if words == 2 then
                locals[current_local] = nil -- holes are fine here
            end

            current_arg += 1
            current_local += 1
        end

        frame = {
            method = method_info,
            class = class,
            loader = class.loader,
            code = method_info.code,
            stack = table.create(method_info.code.max_stack),
            sp = 0,
            locals = locals,
            pc = 0,
            start_pc = 0,
            invocation = invocation,
        } :: t.StackFrame
    elseif method_info.code.kind == "luau" then
        frame = {
            method = method_info,
            class = class,
            loader = class.loader,
            code = method_info.code,
            args = args,
            invocation = invocation,
        } :: t.StackFrame
    end

    dbg.trace(
        jvm,
        "pushed frame #%i on thread #%i (%s.%s)",
        #thread.stack + 1,
        thread.id,
        class.fqcn,
        method_info.signature
    )

    table.insert(thread.stack, frame)
end

function frame.current(jvm: t.Jvm): (t.Thread?, t.StackFrame?)
    local current_thread = jvm.current_thread
    if not current_thread then
        return nil, nil
    end
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
function frame.return_from_current_frame(jvm: t.Jvm, thread: t.Thread, count: number, value: t.JvmValue)
    local stack = thread.stack
    local frame = stack[#stack]
    local parent_frame = stack[#stack - 1]

    local return_type = frame.method.type:get().returns
    local return_ok = false
    if return_type == "void" then
        return_ok = value == nil
    else
        return_ok = typechecker.check_value(value, return_type)
    end

    if not return_ok then
        jvm:throw_exception(
            "java/lang/IncompatibleClassChangeError",
            `invalid return from {frame.class.fqcn}{frame.method.name}{frame.method.descriptor}, got luau {type(value)}`
        )
    end

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
