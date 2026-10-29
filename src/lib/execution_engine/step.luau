--!native
local dbg = require("../dbg")
local jvm_type = require("../jvm_type")
local t = require("../t")
local util = require("../util")
local dispatcher = require("./dispatcher")
local frame = require("./frame")

--[=[
    Invokes `method` inline without performing dispatch logic.
    You must call `dispatcher.dispatch` before this to get the correct method, regardless of dispatch type.
]=]
local function invoke_inline(jvm: t.Jvm, method: dispatcher.DispatchedMethodHandle, args: t.Arguments)
    local thread = jvm.current_thread
    assert(thread)

    local stack = thread.stack
    local this_frame = stack[#stack]
    if not this_frame or this_frame.code.kind == "native" then
        jvm:throw_exception(
            "java/lang/InternalError",
            "attempt to use invoke_inline in native context, use invoke_sync"
        )
        error("^")
    end

    frame.push_on(jvm, thread, method.method, nil, args)
end

local function read_u16be(b: buffer, offset: number): number
    return bit32.rshift(bit32.byteswap(buffer.readu16(b, offset)), 16)
end

local function not_null(jvm: t.Jvm, value: t.JvmObjectRef): t.JvmObject
    if value == nil then
        return jvm:throw_exception("java/lang/NullPointerException")
    end

    return value
end

local LONG_SLOT_MARKER: any = "__LONG_MARKER__"

local function push(f: t.StackFrameJava, value: t.JvmValue, slots: number)
    local stack = f.stack

    local top = f.sp + 1
    stack[top] = value

    if slots == 2 then
        top += 1
        stack[top] = LONG_SLOT_MARKER
    end

    f.sp = top
end

local function pop(f: t.StackFrameJava, slots: number?): (t.JvmValue, number)
    local stack = f.stack
    local top = f.sp

    local val = stack[top]
    stack[top] = nil
    top -= 1

    if slots == 2 then
        if val ~= LONG_SLOT_MARKER then
            error("expected 2-slot value")
        end
        local real_val = stack[top]
        stack[top] = nil
        top -= 1
        f.sp = top
        return real_val, 2
    elseif slots == 1 then
        if val == LONG_SLOT_MARKER then
            error("expected 1-slot")
        end
        f.sp = top
        return val, 1
    else
        if val == LONG_SLOT_MARKER then
            local real_val = stack[top]
            stack[top] = nil
            top -= 1
            f.sp = top
            return real_val, 2
        end
        f.sp = top
        return val, 1
    end
end

local function pop_n(f: t.StackFrameJava, n: number, reverse: boolean): { t.JvmValue }
    local out = table.create(n)

    for i = 1, n do
        local value = pop(f)
        if reverse then
            table.insert(out, 1, value)
        else
            table.insert(out, value)
        end
    end

    return out :: { t.JvmValue }
end

local function get_local(f: t.StackFrame, idx: number): t.JvmValue
    assert(f.code.kind == "java")
    local value = f.locals[idx + 1]
    -- dont check, null references are allowed
    return value
end

local function set_local(f: t.StackFrame, idx: number, value: t.JvmValue)
    assert(f.code.kind == "java")
    f.locals[idx + 1] = value
end

local function supports_wide(op: number): boolean
    return op == 0x15
        or op == 0x17
        or op == 0x19
        or op == 0x16
        or op == 0x18
        or op == 0x36
        or op == 0x38
        or op == 0x3a
        or op == 0x37
        or op == 0x39
        or op == 0xa9
        or op == 0x84
end

local OP_DISPATCH_MAP: { [number]: dispatcher.DispatchType } = {
    [0xB6] = "virtual",
    [0xB7] = "special",
    [0xB8] = "static",
}

local function is_throwable(value: unknown): boolean
    if not util.is_object(value) then
        return false
    end

    local value = value :: t.JvmObject
    return value:instance_of(value.jvm._classes.bootstrap["java/lang/Throwable"])
end

local function coerce_error(jvm: t.Jvm, e: unknown, invoke_depth: number): t.JvmObject
    if is_throwable(e) then
        return e :: t.JvmObject
    end

    local message: string
    if util.is_object(e) then
        local value = e :: t.JvmObject

        if value:instance_of(value.jvm._classes.bootstrap["java/lang/String"]) then
            message = value:inner_string()
        else
            message = tostring(value)
        end
    else
        message = tostring(e)
    end

    local traceback = dbg.luau_scoped_traceback(3, invoke_depth)
    return jvm:create_exception("jvm4l/luau/LuauError", `{message}\n{traceback}`, nil, false)
end

local function sign_extend_byte(byte: number): number
    return if byte >= 0x80 then byte - 0x100 else byte
end

local function sign_extend_short(short: number): number
    return if short >= 0x8000 then short - 0x10000 else short
end

--- compares `int`, `float` and `double
local function conf_if(cond: number, v1: number, v2: number): boolean
    if cond == 0 then
        return v1 == v2
    elseif cond == 1 then
        return v1 ~= v2
    elseif cond == 2 then
        return v1 < v2
    elseif cond == 3 then
        return v1 >= v2
    elseif cond == 4 then
        return v1 > v2
    elseif cond == 5 then
        return v1 <= v2
    end

    error("")
end

local function wrap_int(n: number)
    local u32 = bit32.band(n, 0xFFFFFFFF)
    if u32 >= 0x80000000 then
        return u32 - 0x100000000
    end
    return u32
end

--[=[ 
    Execute a single VM step (a native call, or a burst of bytecode 
    instructions)

    Throws either an exception, or a generic luau error, to be caught by the 
    execution driver.

    Conditions to halt a burst:
    1. budget exhaustion,
    2. anything that pushes or pops stack frames (no instruction can both push and pop a frame so that the depth remains the same)
    3. thread synchronisation (requires manual breaks in opcode impls)
]=]
local function step(jvm: t.Jvm)
    local thread, f = frame.current(jvm)
    assert(thread and f)

    local method = f.method

    if f.code.kind == "luau" then
        local depth = dbg.luau_stack_depth()
        local ok, value = xpcall(f.code.closure, function(e: any)
            return coerce_error(jvm, e, depth)
        end, jvm, unpack(f.args))

        if not ok then
            error(value, 0)
        end

        return frame.return_from_current_frame(jvm, thread, if method.type:get().returns == "void" then 0 else 1, value)
    end

    local jit = f.code.jit
    if jit then
        local exit_reason, value = jit(jvm, thread, f)
        if exit_reason == "break" then
            return
        elseif exit_reason == "return" then
            return frame.return_from_current_frame(
                jvm,
                thread,
                if method.type:get().returns == "void" then 0 else 1,
                value
            )
        end
    end

    local class = f.class
    local k = f.constants
    local code = f.code.code
    local pc = f.pc -- only needs to be cached at the end, doesnt matter for exceptions, as that uses start_pc and sets pc, never reads it!

    local function fetch_u8(): number
        local value = buffer.readu8(code, pc)
        pc += 1
        return value
    end

    local function fetch_u16(): number
        local value = read_u16be(code, pc)
        pc += 2
        return value
    end

    local inital_stack_depth = #thread.stack
    local burst_count = 100 -- use budget later

    for i = 1, burst_count do
        local start_pc = pc
        f.start_pc = start_pc -- cache now because its used for debugging

        local op = fetch_u8()

        local wide = false
        if op == 0xC4 then -- wide
            wide = true
            op = fetch_u8()
        end

        if wide and not supports_wide(op) then
            jvm:_internal_error(string.format("opcode %02X does not support wide", op))
        end

        if op == 0x00 then -- `nop`
            -- do nothing
        elseif op == 0x01 then -- `aconst_null`
            push(f, nil, 1)
        elseif op >= 0x02 and op <= 0x08 then -- `aconst_<n>`
            push(f, op - 0x03, 1)
        elseif op >= 0x09 and op <= 0x0A then -- `lconst_<n>`
            push(f, integer.create(op - 0x09), 2)
        elseif op >= 0x0B and op <= 0x0D then -- `fconst_<n>`
            push(f, op - 0x0B, 1)
        elseif op >= 0x0E and op <= 0x0F then -- `dconst_<n>`
            push(f, op - 0x0E, 2)
        elseif op == 0x10 then -- `bipush`
            push(f, sign_extend_byte(fetch_u8()), 1)
        elseif op == 0x11 then -- `sipush`
            push(f, sign_extend_short(fetch_u16()), 1)
        elseif op == 0x12 then -- `ldc`
            local idx = fetch_u8()
            local value: t.JvmValue

            if k:is(idx, "int") then
                value = k:get(idx, "int")
            elseif k:is(idx, "float") then
                value = k:get(idx, "float")
            elseif k:is(idx, "string") then
                value = k:get(idx, "string")
            elseif k:is(idx, "class") then
                value = k:get(idx, "class")
            else
                error("")
            end -- todo(dynamic): MethodType and MethodHandle

            push(f, value, 1)

            if inital_stack_depth ~= #thread.stack then
                break
            end
        elseif op >= 0x1A and op <= 0x1D then -- `iload_<n>`
            push(f, get_local(f, op - 0x1A), 1)
        elseif op >= 0x2A and op <= 0x2D then -- `aload_<n>`
            push(f, get_local(f, op - 0x2A), 1)
        elseif op >= 0x3B and op <= 0x3E then -- `istore_<n>`
            set_local(f, op - 0x3B, pop(f, 1))
        elseif op >= 0x4B and op <= 0x4E then -- `astore_<n>`
            set_local(f, op - 0x4B, pop(f, 1))
        elseif op == 0x59 then -- `dup`
            local value = pop(f, 1)
            push(f, value, 1)
            push(f, value, 1)
        elseif op == 0x60 then -- `iadd`
            local v2, v1 = pop(f, 1) :: number, pop(f, 1) :: number
            push(f, wrap_int(v1 + v2), 1)
        elseif op == 0x64 then -- `isub`
            local v2, v1 = pop(f, 1) :: number, pop(f, 1) :: number
            push(f, wrap_int(v1 - v2), 1)
        elseif op == 0x84 then -- `iinc`
            local idx = fetch_u8()
            local by = sign_extend_byte(fetch_u8())
            local value = get_local(f, idx) :: number
            set_local(f, idx, wrap_int(value + by))
        elseif op >= 0x99 and op <= 0x9E then -- `if<cond>`
            local cond = op - 0x99
            local offset = sign_extend_short(fetch_u16())
            local value1 = pop(f, 1) :: number

            local taken = conf_if(cond, value1, 0)
            if taken then
                pc = start_pc + offset
            end
        elseif op >= 0x9F and op <= 0xA4 then -- `if_icmp<cond>`
            local cond = op - 0x9F
            local offset = sign_extend_short(fetch_u16())
            local value2, value1 = pop(f, 1) :: number, pop(f, 1) :: number

            local taken = conf_if(cond, value1, value2)
            if taken then
                pc = start_pc + offset
            end
        elseif op == 0xA7 then -- `goto`
            local offset = sign_extend_short(fetch_u16())
            pc = start_pc + offset
        elseif op == 0xB2 then -- `getstatic`
            local idx = fetch_u16()
            local field = k:get(idx, "field")
            local slots = jvm_type.words(field.info.type:get())
            local value = field.class:get_static_field(field)
            push(f, value, slots)

            if inital_stack_depth ~= #thread.stack then
                break
            end
        elseif op == 0xB3 then -- `putstatic`
            local idx = fetch_u16()
            local field = k:get(idx, "field")
            local value = pop(f)
            field.class:set_static_field(field, value)

            if inital_stack_depth ~= #thread.stack then
                break
            end
        elseif op == 0xB4 then -- `getfield`
            local idx = fetch_u16()
            local field = k:get(idx, "field")
            local slots = jvm_type.words(field.info.type:get())
            local object = not_null(jvm, pop(f) :: t.JvmObjectRef)
            local value = object:get_field(field)
            push(f, value, slots)
        elseif op == 0xB5 then -- `putfield`
            local idx = fetch_u16()
            local field = k:get(idx, "field")
            local value = pop(f)
            local object = not_null(jvm, pop(f) :: t.JvmObjectRef)
            object:set_field(field, value)
        elseif op >= 0xB6 and op <= 0xB8 then -- `invokevirtual`, `invokestatic`, `invokespecial`
            local dispatch_type = OP_DISPATCH_MAP[op]

            local idx = fetch_u16()
            local method = k:get(idx, "method")
            local arg_count = #method.info.type:get().arguments
            if op ~= 0xB8 then
                arg_count += 1
            end
            local args = pop_n(f, arg_count, true) :: t.Arguments
            args.n = arg_count
            local dispatched_method = dispatcher.dispatch(jvm, method, dispatch_type, class)
            invoke_inline(jvm, dispatched_method, args)
            break
        elseif op == 0xB0 or op == 0xB1 or (op >= 0xAC and op <= 0xAF) then -- `areturn`, `return`, `ireturn` `freturn`, `lreturn`, `dreturn`
            local value: t.JvmValue, count: number

            if op == 0xAD or op == 0xAF then
                value = pop(f, 2)
                count = 1
            elseif op == 0xB1 then
                value = nil
                count = 0
            else
                value = pop(f, 1)
                count = 1
            end

            frame.return_from_current_frame(jvm, thread, count, value)
            break
        elseif op == 0xBB then -- `new`
            local idx = fetch_u16()
            local class = k:get(idx, "class")
            push(f, class:_new_uninitialised(), 1)

            if inital_stack_depth ~= #thread.stack then
                break
            end
        elseif op == 0xBF then -- `athrow`
            -- TODO: synchronisation
            local obj = not_null(jvm, pop(f, 1) :: t.JvmObjectRef)
            error(obj, 0)
            -- will break by nature of error
        else
            jvm:_internal_error(string.format("unimplemented opcode 0x%02X", op))
        end
    end

    f.pc = pc
end

return step
