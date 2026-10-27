local dbg = require("../dbg")
local t = require("../t")
local typechecker = require("../typechecker")
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

local function check_type(jvm: t.Jvm, value: t.JvmValue, target: t.JvmType | "ref")
    if target == "ref" then
        if value == nil then
            return
        end

        if type(value) == "table" and value.__type == "JvmObject" then
            return
        end
    else
        if typechecker.check_value(value, target) then
            return
        end
    end

    error("invalid type in bytecode step", 2)
end

local function not_null(jvm: t.Jvm, value: t.JvmObjectRef): t.JvmObject
    if value == nil then
        return jvm:throw_exception("java/lang/NullPointerException")
    end

    return value
end

local LONG_SLOT_MARKER = newproxy(false)

local function push(f: t.StackFrame, value: t.JvmValue, slots: number)
    assert(f.code.kind == "java")
    local stack = f.stack

    local top = f.sp + 1
    stack[top] = value

    if slots == 2 then
        top += 1
        stack[top] = LONG_SLOT_MARKER
    end

    f.sp = top
end

local function pop(f: t.StackFrame, slots: number?): (t.JvmValue, number)
    assert(f.code.kind == "java")
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

local function pop_n(f: t.StackFrame, n: number): { t.JvmValue }
    local out = table.create(n)

    for i = 1, n do
        local value = pop(f)
        table.insert(out, value)
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

local function fetch_u8(f: t.StackFrameJava): number
    local value = buffer.readu8(f.code.code, f.pc)
    f.pc += 1
    return value
end

local function fetch_u16(f: t.StackFrameJava): number
    local value = read_u16be(f.code.code, f.pc)
    f.pc += 2
    return value
end

local function SIGN_EXTEND_BYTE(byte: number): number
    return if byte >= 0x80 then byte - 0x100 else byte
end

local function SIGN_EXTEND_SHORT(short: number): number
    return if short >= 0x8000 then short - 0x10000 else short
end

--[=[ 
    Execute a single VM step (a native call, or a single bytecode instruction)

    Throws either an exception, or a generic luau error, to be caught by the 
    execution driver.
]=]
@native
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

    local class = f.class
    local k = f.class._constant_pool or error("expected constant pool")

    local start_pc = f.pc
    f.start_pc = start_pc

    local op = fetch_u8(f)

    local wide = false
    if op == 0xC4 then -- wide
        wide = true
        op = fetch_u8(f)
    end

    if wide and not supports_wide(op) then
        jvm:_internal_error(string.format("opcode %02X does not support wide", op))
    end

    if op == 0x00 then -- `nop`
        -- do nothing
    elseif op <= 0x0F then -- constant loads
        local value: t.JvmValue, slots: number

        if op == 0x01 then -- `aconst_null`
            value, slots = nil, 1
        elseif op >= 0x02 and op <= 0x08 then -- `aconst_<n>`
            value, slots = op - 0x03, 1
        elseif op >= 0x09 and op <= 0x0A then -- `lconst_<n>`
            value, slots = integer.create(op - 0x09), 2
        elseif op >= 0x0B and op <= 0x0D then -- `fconst_<n>`
            value, slots = op - 0x0B, 1
        elseif op >= 0x0E and op <= 0x0F then -- `dconst_<n>`
            value, slots = op - 0x0E, 2
        end

        push(f, value, slots)
    elseif op <= 0x11 then -- immediate constant loads
        local value: number

        if op == 0x10 then -- `bipush`
            value = SIGN_EXTEND_BYTE(fetch_u8(f))
        elseif op == 0x11 then -- `sipush`
            value = SIGN_EXTEND_SHORT(fetch_u16(f))
        end

        push(f, value, 1)
    elseif op == 0x12 then -- `ldc`
        local idx = fetch_u8(f)
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
    elseif op >= 0x2A and op <= 0x2D then -- `aload_i`
        local idx = op - 0x2A
        local value = get_local(f, idx)
        check_type(jvm, value, "ref")
        push(f, value, 1)
    elseif op >= 0x4B and op <= 0x4E then -- `astore_i`
        local idx = op - 0x4B
        local value = pop(f, 1)
        check_type(jvm, value, "ref") -- TODO: support returnAddress
        set_local(f, idx, value)
    elseif op == 0xB5 then -- `putfield`
        local idx = fetch_u16(f)
        local field = k:get(idx, "field")
        local value = pop(f)
        local object = not_null(jvm, pop(f) :: t.JvmObjectRef)
        object:set_field(field, value)
    elseif op == 0xB7 then -- `invokespecial`
        local idx = fetch_u16(f)
        local method = k:get(idx, "method")
        local arg_count = #method.info.type:get().arguments + 1
        local args = pop_n(f, arg_count) :: t.Arguments
        args.n = arg_count
        local dispatched_method = dispatcher.dispatch(jvm, method, "special", class)
        invoke_inline(jvm, dispatched_method, args)
    elseif op == 0xB8 then -- `invokestatic`
        local idx = fetch_u16(f)
        local method = k:get(idx, "method")
        local arg_count = #method.info.type:get().arguments
        local args = pop_n(f, arg_count) :: t.Arguments
        args.n = arg_count
        local dispatched_method = dispatcher.dispatch(jvm, method, "static", class)
        invoke_inline(jvm, dispatched_method, args)
    elseif op == 0xAC then -- `ireturn`
        frame.return_from_current_frame(jvm, thread, 1, pop(f, 1))
    elseif op == 0xB1 then -- `return`
        frame.return_from_current_frame(jvm, thread, 0, nil)
    elseif op == 0xA7 then -- `goto`
        local raw_offset = fetch_u16(f)

        local offset = bit32.arshift(bit32.lshift(raw_offset, 16), 16)
        if offset >= 0x80000000 then
            offset = offset - 4294967296
        end

        f.pc = start_pc + offset
    else
        jvm:_internal_error(string.format("unimplemented opcode 0x%02X", op))
    end
end

return step
