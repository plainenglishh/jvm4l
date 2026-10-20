local class_parser = require("./class_parser")
local JvmObject = require("./classes/JvmObject")
local t = require("./t")

--[[
    improvements wrt frame transitions:
    native -> java = spin up a new nested exec engine (for sync value out)
    java -> native = just push a frame
    java -> java = just push a frame
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

local function return_from_frame(thread: t.Thread, count: number, value: t.JvmValue)
    local frame = thread.stack[#thread.stack]
    local parent_frame = thread.stack[#thread.stack - 1]

    if frame.invocation then
        complete_invocation(frame.invocation, value)
    end

    thread.stack[#thread.stack] = nil

    --if parent_frame and parent_frame.code.kind == "java" then
    --    table.insert(parent_frame.stack, value)
    --end
end

local function read_u16be(b: buffer, offset: number): number
    return bit32.rshift(bit32.byteswap(buffer.readu16(b, offset)), 16)
end

local function get_method_ref_from_k(jvm: t.Jvm, classfile: t.Classfile, idx: number): (t.JvmClass, t.MethodRef)
    local k = classfile.constant_pool
    local methodref = k[idx]
    if methodref.tag ~= "Methodref" then
        error("expected Methodref")
    end

    local classref = k[methodref.class_index]
    if classref.tag ~= "Class" then
        error("expected Class")
    end

    local name_and_type = k[methodref.name_and_type_index]
    if name_and_type.tag ~= "NameAndType" then
        error("expected NameAndType")
    end

    local class_name, name, descriptor =
        class_parser.class_name(classfile, classref),
        class_parser.string_value(classfile, name_and_type.name_index),
        class_parser.string_value(classfile, name_and_type.descriptor_index)

    local class = jvm:resolve_class(class_name)
    local method_ref = jvm:get_method_ref(class, name, descriptor)
    return class, method_ref
end

--[=[ 
    Execute a single VM step (a native call, or a single bytecode instruction)

    Throws either an exception, or a generic luau error, to be caught by the 
    execution driver.
]=]
local function step(jvm: t.Jvm)
    local thread = jvm.current_thread
    local f = thread.stack[#thread.stack]
    if f.code.kind == "luau" then
        local value = f.code.closure(jvm, unpack(f.args))
        return return_from_frame(thread, 1, value)
    end

    local code = f.code.code
    local stack = f.stack
    local locals = f.locals
    local classfile = f.class._classfile or error("expected classfile")
    local k = classfile.constant_pool

    local start_pc = f.pc
    local op = buffer.readu8(code, start_pc)
    f.pc += 1

    if op >= 0x02 and op <= 0x8 then
        table.insert(stack, op - 0x03)
    elseif op >= 0x4B and op <= 0x4E then
        local idx = op - 0x4B
        local ref = table.remove(stack)
        locals[idx] = ref
    elseif op == 0xB8 then
        local idx = read_u16be(code, f.pc)
        f.pc += 2

        local class, method_ref = get_method_ref_from_k(jvm, classfile, idx)
        local method_info = class:resolve_method(method_ref) or error("unable to resolve method")
        local args = { table.remove(stack) } -- one arg for now

        local ok, value = execution_engine.invoke(jvm, class, method_info, unpack(args))
        if not ok then
            f.pc = start_pc
            error(value, 0)
        end

        if value ~= nil then
            table.insert(stack, value)
        end
        return
    elseif op == 0xAC then -- ireturn
        return_from_frame(thread, 1, table.remove(stack))
        return
    elseif op == 0xB1 then -- return
        return_from_frame(thread, 0, nil)
        return
    elseif op == 0xA7 then -- goto
        local raw_offset = read_u16be(code, f.pc)
        f.pc += 2

        local offset = bit32.arshift(bit32.lshift(raw_offset, 16), 16)
        f.pc = start_pc + offset
    else
        jvm:throw_exception("java/lang/InternalError", `invalid opcode {op}`)
    end
end

local function is_exception(value: any): boolean
    return type(value) == "table" and getmetatable(value) == JvmObject
end

--[=[
    Drive all threads execution until `target` completes or fails.

    There will always be at least *one* invocation in a thread stack, including 
    the top most frame. This function will always check it's own 
    target before doing anything else.
]=]
local function execute(jvm: t.Jvm, target: t.Invocation): (boolean, t.JvmValue)
    jvm._exec_depth += 1
    --print(`spinning up exec engine on target {target}, new depth {jvm._exec_depth}`)

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

        if not ok then
            local exception: t.JvmObject = if is_exception(exception)
                then exception :: t.JvmObject
                else jvm:create_exception("jvm4l/LuauError", tostring(exception))

            local caught = false

            for i = #thread.stack, 1, -1 do
                local frame = thread.stack[i]
                if frame.code.kind == "java" then
                    for i, exception_info in frame.code.exceptions do
                        if frame.pc < exception_info.start_pc or frame.pc >= exception_info.end_pc then
                            continue
                        end

                        if
                            exception_info.catch_type ~= nil and not exception:instance_of(exception_info.catch_type)
                        then
                            continue
                        end

                        table.insert(frame.stack, exception)
                        frame.pc = exception_info.handler_pc
                        caught = true
                        break
                    end
                else
                    thread.stack[i] = nil
                    jvm._exec_depth -= 1
                    return false, exception
                end

                if caught then
                    break
                end

                if frame.invocation then
                    fail_invocation(frame.invocation, exception)
                end

                thread.stack[i] = nil
            end

            if #thread.stack == 0 then
                --- do some better handling here l&r.
                thread.state = "terminated"
            end
        end
    end
end

--[=[
    Invokes a method.
]=]
function execution_engine.invoke(
    jvm: t.Jvm,
    class: t.JvmClass,
    method: t.MethodInfo,
    ...: t.JvmValue
): (boolean, t.JvmValue)
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
    return execute(jvm, invocation)
end

return execution_engine
