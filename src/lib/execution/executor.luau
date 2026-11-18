local dbg = require("../dbg")
local t = require("../t")
local util = require("../util")
local frame = require("./frame")
local scheduler = require("./scheduler")
local step = require("./step")

local function is_throwable(value: unknown): boolean
    if not util.is_object(value) then
        return false
    end

    local value = value :: t.JvmObject
    return value:instance_of(value.jvm._classes.bootstrap["java/lang/Throwable"])
end

local function match_exception_handler(f: t.StackFrame, exception: t.JvmObject): t.ExceptionHandler?
    assert(f.code.kind == "java")
    for _, exception_handler in f.code.exceptions do
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
        dbg.trace(jvm, "unwound frame #%i on thread #%i (%s.%s)", i, thread.id, f.class.fqcn, f.method.signature)

        if f.invocation and f.invocation == target then
            return false
        end
    end

    error("unreachable")
end

local executor = {}

--[=[
    Drive *all* threads execution until `target` completes or fails.
]=]
@native
function executor.execute_all(jvm: t.Jvm, target: t.Invocation): (boolean, t.JvmValue)
    jvm._exec_depth += 1
    dbg.trace(jvm, "entered execution engine #%i", jvm._exec_depth)

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
        if not thread then
            continue
        end

        thread.budget -= 1

        local ok, exception = xpcall(step :: any, function(value): t.JvmObject
            if is_throwable(value, "java/lang/Throwable") then
                return value :: t.JvmObject
            else
                return jvm:_create_internal_error(tostring(value), 2)
            end
        end, jvm)

        if ok then
            continue
        end

        local caught = unwind_thread(jvm, thread, target, exception)
        if caught then
            continue
        end

        if #thread.stack == 0 then
            thread.state = "terminated"
        end
    end

    dbg.trace(jvm, 'exited execution engine #%i (success=%*, value="%*")', jvm._exec_depth, target_ok, target_value)
    jvm._exec_depth -= 1
    return target_ok, target_value
end

--[=[
    Drive *all* threads execution until `target` completes or fails.
]=]
@native
function executor.execute_exclusive(jvm: t.Jvm, target: t.Invocation, depth: number): (boolean, t.JvmValue)
    jvm._exec_depth += 1
    dbg.trace(jvm, "entered exclusive execution engine #%i", jvm._exec_depth)
    local thread = assert(jvm.current_thread, "no current thread to run execute_exclusive on")

    local target_ok: boolean, target_value: t.JvmValue
    while true do
        if target.state == "complete" then
            target_ok, target_value = true, target.value
            break
        elseif target.state == "failed" then
            target_ok, target_value = false, target.exception
            break
        elseif #thread.stack < depth then
            error("exclusive stack depth range left without completing invocation")
        end

        local ok, exception = xpcall(step :: any, function(value): t.JvmObject
            if is_throwable(value, "java/lang/Throwable") then
                return value :: t.JvmObject
            else
                return jvm:_create_internal_error(tostring(value), 2)
            end
        end, jvm)

        if ok then
            continue
        end

        local caught = unwind_thread(jvm, thread, target, exception)
        if caught then
            continue
        end
    end

    dbg.trace(
        jvm,
        'exited exclusive execution engine #%i (success=%*, value="%*")',
        jvm._exec_depth,
        target_ok,
        target_value
    )
    jvm._exec_depth -= 1
    return target_ok, target_value
end

return executor
