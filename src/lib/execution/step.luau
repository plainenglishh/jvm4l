--!native

local dbg = require("../dbg")
local ir = require("../ir")
local t = require("../t")
local util = require("../util")
local dispatcher = require("./dispatcher")
local frame = require("./frame")

--[=[
    Invokes `method` inline without performing dispatch logic.
    You must call `dispatcher.dispatch` before this to get the correct method, regardless of dispatch type.
]=]
local function invoke_inline(
    jvm: t.Jvm,
    method: dispatcher.DispatchedMethodHandle,
    args: t.Arguments,
    return_to: number?
)
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

    frame.push_on(jvm, thread, method.method, nil, args, return_to)
end

local function not_null(jvm: t.Jvm, value: t.JvmObjectRef): t.JvmObject
    if value == nil then
        return jvm:throw_exception("java/lang/NullPointerException")
    end

    return value
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

--- compares `int`, `float` and `double
local function cmp(cond: number, v1: number, v2: number): boolean
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

local function wrap_int(n: number): number
    return (n + 2147483648) % 4294967296 - 2147483648
end

local DISPATCH_TYPES: { [number]: dispatcher.DispatchType } = {
    [0] = "virtual",
    [1] = "special",
    [2] = "static",
}

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
    local ir = f.code
    assert(ir, "transpile didn't work! bad!")

    local pc = f.pc
    local b = ir.code
    local registers = f.registers

    local function fetch_u8(): number
        local value = buffer.readu8(b, pc)
        pc += 1
        return value
    end

    local function fetch_u16(): number
        local value = buffer.readu16(b, pc)
        pc += 2
        return value
    end

    local function fetch_u32(): number
        local value = buffer.readu32(b, pc)
        pc += 4
        return value
    end

    local burst_count = 100 -- use budget later
    for i = 1, burst_count do
        local start_pc = pc
        f.start_pc = start_pc -- cache now because its used for debugging

        local op = fetch_u8()
        if op == 0x00 then -- `nop`
        elseif op == 0x01 then -- `move`
            local dst = fetch_u16()
            local src = fetch_u16()
            registers[dst] = registers[src]
        elseif op == 0x10 then -- `load_literal/null`
            local dst = fetch_u16()
            registers[dst] = nil
        elseif op == 0x11 then -- `load_literal/int`
            local dst = fetch_u16()
            local value = buffer.readi32(b, pc)
            pc += 4
            registers[dst] = value
        elseif op == 0x12 then -- `load_literal/float`
            local dst = fetch_u16()
            local value = buffer.readf32(b, pc)
            pc += 4
            registers[dst] = value
        elseif op == 0x13 then -- `load_literal/long`
            local dst = fetch_u16()
            local value = buffer.readinteger(b, pc)
            pc += 8
            registers[dst] = value
        elseif op == 0x14 then -- `load_literal/double`
            local dst = fetch_u16()
            local value = buffer.readf64(b, pc)
            pc += 8
            registers[dst] = value
        elseif op == 0x15 then -- `load_const`
            local dst = fetch_u16()
            local idx = fetch_u16()

            local value
            if k:is(idx, "string") then
                value = k:get(idx, "string")
            elseif k:is(idx, "class") then
                value = k:get(idx, "class")
            else -- todo(dynamic): MethodType and MethodHandle
                error("unsupported const type")
            end

            registers[dst] = value
        elseif op == 0x20 then -- `add/int`
            local dst = fetch_u16()
            local lhs = registers[fetch_u16()] :: number
            local rhs = registers[fetch_u16()] :: number
            registers[dst] = wrap_int(lhs + rhs)
        elseif op == 0x21 then -- `sub/int`
            local dst = fetch_u16()
            local lhs = registers[fetch_u16()] :: number
            local rhs = registers[fetch_u16()] :: number
            registers[dst] = wrap_int(lhs - rhs)
        elseif op == 0x22 then -- `add_literal/int`
            local dst = fetch_u16()
            local lhs = registers[fetch_u16()] :: number
            local rhs = buffer.readi32(b, pc)
            pc += 4
            registers[dst] = wrap_int(lhs + rhs)
        elseif op >= 0x40 and op <= 0x45 then
            local cond = op - 0x40 -- `jump_if_<cond>/int`
            local lhs = registers[fetch_u16()] :: number
            local rhs = registers[fetch_u16()] :: number or 0

            if cmp(cond, lhs, rhs) then
                pc = fetch_u32()
            else
                pc += 4
            end
        --elseif op == 0x46 then
        elseif op == 0x50 then
            pc = fetch_u32()
        elseif op == 0x51 then
            local src = fetch_u16()
            local target = fetch_u32()

            if registers[src] ~= 0 then
                pc = target
            end
        elseif op == 0x60 then
            local dst = fetch_u16()
            local src = fetch_u16()
            local field = k:get(fetch_u16(), "field")

            local object = not_null(jvm, registers[src] :: t.JvmObjectRef)
            local value = object:get_field(field)
            registers[dst] = value
        elseif op == 0x61 then
            local dst = fetch_u16()
            local src = fetch_u16()
            local field = k:get(fetch_u16(), "field")

            local value = registers[src]
            local object = not_null(jvm, registers[dst] :: t.JvmObjectRef)
            object:set_field(field, value)
        elseif op == 0x62 then
            local dst = fetch_u16()
            local field = k:get(fetch_u16(), "field")
            local value = field.class:get_static_field(field)
            registers[dst] = value
        elseif op == 0x63 then
            local src = fetch_u16()
            local field = k:get(fetch_u16(), "field")
            local value = registers[src]
            field.class:set_static_field(field, value)
        elseif op == 0x70 then
            local dst = fetch_u16()
            local class = k:get(fetch_u16(), "class")
            registers[dst] = class:_new_uninitialised()
        elseif op == 0x71 then
            local obj = not_null(jvm, registers[fetch_u16()] :: t.JvmObjectRef)
            error(obj, 0)
        elseif op == 0x80 or op == 0x81 then
            local dst
            if op == 0x80 then
                dst = fetch_u16()
            end

            local method = k:get(fetch_u16(), "method")
            local arg_start = fetch_u16()
            local arg_count = fetch_u8()
            local dispatch_type = DISPATCH_TYPES[fetch_u8()]
            local args = table.create(arg_count) :: { t.JvmValue }
            table.move(registers, arg_start, arg_start + arg_count, 1, args)
            local dispatched = dispatcher.dispatch(jvm, method, dispatch_type, f.class)
            invoke_inline(jvm, dispatched, t.Arguments.from_array(args, arg_count), dst)
            break
        elseif op == 0x82 or op == 0x83 then
            local value, value_count = nil, 0
            if op == 0x82 then
                value = registers[fetch_u16()]
                value_count = 1
            end

            frame.return_from_current_frame(jvm, thread, value_count, value)
            break
        else
            jvm:_internal_error(string.format("unimplemented opcode 0x%02X", op))
        end
    end

    f.pc = pc
end

return step
