local JvmObject = require("./classes/JvmObject")
local t = require("./t")
local util = require("./util")

--[[
    Later improvements:
    1. dont create a new execution driver for java -> java/luau invocations.
]]

local execution_engine = {}

local function fail_invocation(invocation: t.Invocation, exception: t.JvmObject)
    local invocation = invocation :: any
    invocation.state = "failed"
    invocation.exception = exception
end

local function complete_invocation(invocation: t.Invocation, value: t.JvmValue)
    local invocation = invocation :: any
    invocation.state = "complete"
    invocation.value = value
end

--[=[
    Checks whether a new thread should be scheduled, and schedules a new thread
    if necessary.

    Reschedule conditions are:
    1. the current thread has reached its budget;
    2. the current thread is blocked. 
]=]
local function try_reschedule(jvm: t.Jvm)
    --- do nothing for now
    -- todo: check if current quota reached, or if we're blocked, and pick a new thread
end

--[=[ 
    Execute a single VM step (a native call, or a single bytecode instruction)

    Throws either an exception, or a generic luau error, to be caught by the 
    execution driver.
]=]
local function step(jvm: t.Jvm)
    local thread = jvm.current_thread
    local frame = thread.stack[#thread.stack]
end

--[=[
    Drive all threads execution until `target` completes or fails.

    There will always be at least *one* invocation in a thread stack, including 
    the top most frame. This function will always check it's own 
    target before doing anything else.
]=]
local function execute(jvm: t.Jvm, target: t.Invocation): (boolean, t.JvmValue)
    jvm._exec_depth += 1
    while true do
        if target.state == "complete" then
            jvm._exec_depth -= 1
            return true, target.value
        elseif target.state == "failed" then
            jvm._exec_depth -= 1
            return false, target.exception
        end

        try_reschedule(jvm)
        local thread = jvm.current_thread
        thread.budget -= 1

        local ok, exception = pcall(step, jvm)
        if type(exception) ~= "table" and getmetatable(exception) ~= JvmObject then
            exception = jvm:create_exception("jvm4l/LuauError", tostring(exception))
        end

        if not ok then
            for i = #thread.stack, 1, -1 do
                local frame = thread.stack[i]
                if frame.code.kind == "java" then
                end

                if frame.invocation then
                end
            end
        end
    end
end

--[=[
    Invokes a method.
]=]
function execution_engine.invoke(jvm: t.Jvm, class: t.JvmClass, method: t.MethodInfo, ...: t.JvmValue): t.JvmValue
    if method.code.kind == "abstract" then
        jvm:throw_exception("java/lang/AbstractMethodError", method.descriptor)
        error("^")
    end

    local args = { ... }

    local invocation: t.Invocation = {
        state = "running",
    }

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

    table.insert(jvm.current_thread.stack, frame)
    local ok, value_or_exception = execute(jvm, invocation)
    if not ok then
        error(value_or_exception, 0)
    end
    return value_or_exception
end

return execution_engine
