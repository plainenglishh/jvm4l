local JvmObject = require("../entities/JvmObject")
local t = require("../t")
local frame = require("./frame")
local scheduler = require("./scheduler")
local step = require("./step")

local function is_exception(value: any): boolean
    return type(value) == "table" and getmetatable(value) == JvmObject
end

local function coerce_exception(jvm: t.Jvm, exception: unknown): t.JvmObject
    return if is_exception(exception)
        then exception :: t.JvmObject
        else jvm:create_exception("jvm4l/LuauError", tostring(exception))
end

local function match_exception_handler(f: t.StackFrame, exception: t.JvmObject): t.ExceptionHandler?
    assert(f.code.kind == "java")
    for i, exception_handler in f.code.exceptions do
        if f.start_pc < exception_handler.start_pc or f.start_pc >= exception_handler.end_pc then
            continue
        end

        if exception_handler.catch_type ~= nil and not exception:instance_of(exception_handler.catch_type) then
            continue
        end

        return exception_handler
    end

    return nil
end

local function unwind_thread(jvm: t.Jvm, thread: t.Thread, target: t.Invocation, exception: t.JvmObject): boolean
    local stack = thread.stack
    local stack_depth = #stack

    for i = stack_depth, 1, -1 do
        local f = stack[i]

        if f.invocation then
            frame.fail_invocation(f.invocation, exception)

            if f.invocation ~= target then
                return false
            end
        end

        if f.code.kind == "java" then
            local exception_handler = match_exception_handler(f, exception)
            if exception_handler then
                table.clear(f.stack)
                table.insert(f.stack, exception)
                f.pc = exception_handler.handler_pc
                return true
            end
        end

        stack[i] = nil
        jvm:_trace(`unwound frame #{i} on thread #{thread.id} ({f.class.fqcn}.{f.method.signature})`)

        if f.invocation and f.invocation == target then
            return false
        end
    end

    error("unreachable")
end

--[=[
    Drive *all* threads execution until `target` completes or fails.
]=]
@native
local function executor(jvm: t.Jvm, target: t.Invocation): (boolean, t.JvmValue)
    jvm._exec_depth += 1
    jvm:_trace(`entered execution engine #{jvm._exec_depth}`)

    local target_ok: boolean, target_value: t.JvmValue
    while true do
        if target.state == "complete" then
            target_ok, target_value = true, target.value
            break
        elseif target.state == "failed" then
            target_ok, target_value = false, target.exception
            break
        end

        scheduler.try_reschedule(jvm)
        local thread = jvm.current_thread
        thread.budget -= 1

        local ok, exception = pcall(step, jvm)
        if ok then
            continue
        end

        local exception: t.JvmObject = coerce_exception(jvm, exception)
        local caught = unwind_thread(jvm, thread, target, exception)
        if caught then
            continue
        end

        if #thread.stack == 0 then
            thread.state = "terminated"
        end
    end

    jvm:_trace(
        `exited execution engine #{jvm._exec_depth} {if target_ok then "" else "un"}successfully with {if target_ok
            then "value"
            else "exception (hashcode)"} {if not target_ok
            then (target_value :: any).hash_code
            else target_value}`
    )
    jvm._exec_depth -= 1
    return target_ok, target_value
end

return executor
