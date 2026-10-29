local t = require("../t")
local StringBuilder = require("../utilities/StringBuilder")
local scanner = require("./scanner")

local function read_u16be(b: buffer, offset: number): number
    return bit32.rshift(bit32.byteswap(buffer.readu16(b, offset)), 16)
end

local function read_i16be(b: buffer, offset: number): number
    local value = (read_u16be(b, offset))
    return if value >= 0x8000 then value - 0x10000 else value
end

type OpImpl = (
    method: t.MethodHandle,
    code: buffer,
    pc: number,
    start_pc: number,
    wide: boolean,
    writer: StringBuilder.StringBuilder
) -> number

local OPS: { [number]: OpImpl } = {}

local function write_push(writer: StringBuilder.StringBuilder, val_expr: string, slots: number)
    writer:write("sp += %i", slots)
    writer:write("; stack[sp%s] = %s", if slots == 2 then " - 1" else "", val_expr)
    if slots == 2 then
        writer:write("; stack[sp] = '__LONG_MARKER__'")
    end
    writer:writeln("")
end

local function write_pop(writer: StringBuilder.StringBuilder, output_var: string, slots: number?)
    if slots then
        writer:write("local %s = stack[sp%s]", output_var, if slots == 2 then " - 1" else "")
        writer:writeln("; sp -= %i", slots)
    else
        writer:write("local %s = stack[sp]", output_var)
        writer:write("; if %s == '__LONG_MARKER__' then", output_var)
        writer:write(" %s = stack[sp - 1]; sp -= 1", output_var)
        writer:writeln("end sp -= 1", output_var)
    end
end

local function write_break(writer: StringBuilder.StringBuilder)
    writer:writeln("f.pc, f.sp = pc, sp; return 'break'")
end

local function write_return(writer: StringBuilder.StringBuilder, slots: number)
    write_pop(writer, "value", slots)
    writer:writeln("return 'return', value")
end

local function write_jump(writer: StringBuilder.StringBuilder, target: number)
    writer:writeln("pc = %*; continue", target)
end

local function write_int_wrap(writer: StringBuilder.StringBuilder, var_name: string)
    writer:writeln(
        [[
    %s = (%s + 2147483648) %% 4294967296 - 2147483648
    ]],
        var_name,
        var_name
    )
end

for op = 0x02, 0x08 do
    local value = op - 0x03

    OPS[op] = function(
        method: t.MethodHandle,
        code: buffer,
        pc: number,
        start_pc: number,
        _,
        writer: StringBuilder.StringBuilder
    ): number
        write_push(writer, tostring(value), 1)
        return pc
    end
end

OPS[0x12] = function(
    method: t.MethodHandle,
    code: buffer,
    pc: number,
    start_pc: number,
    _,
    writer: StringBuilder.StringBuilder
): number
    local idx = buffer.readu8(code, pc)
    pc += 1

    local k = method.class._constant_pool or error("")

    if k:is(idx, "int") then
        write_push(writer, tostring(k:get(idx, "int")), 1)
    elseif k:is(idx, "float") then
        write_push(writer, tostring(k:get(idx, "float")), 1)
    else
        writer:writeln(
            [[
local value: any
if k:is(%i, "string") then
    value = k:get(%i, "string")
elseif k:is(%i, "class") then
    value = k:get(%i, "class")
else
    error("")
end]],
            idx,
            idx,
            idx,
            idx
        )

        write_push(writer, "value", 1)
    end

    return pc
end

for op = 0x1A, 0x1D do
    local idx = op - 0x1A

    OPS[op] = function(
        method: t.MethodHandle,
        code: buffer,
        pc: number,
        start_pc: number,
        _,
        writer: StringBuilder.StringBuilder
    ): number
        writer:writeln("local value = locals[%i]", idx + 1)
        write_push(writer, "value", 1)
        return pc
    end
end

for op = 0x3B, 0x3E do
    local idx = op - 0x3B

    OPS[op] = function(
        method: t.MethodHandle,
        code: buffer,
        pc: number,
        start_pc: number,
        _,
        writer: StringBuilder.StringBuilder
    ): number
        write_pop(writer, "value", 1)
        writer:writeln("locals[%i] = value", idx + 1)
        return pc
    end
end

OPS[0x84] = function(
    method: t.MethodHandle,
    code: buffer,
    pc: number,
    start_pc: number,
    _,
    writer: StringBuilder.StringBuilder
): number
    local idx = buffer.readu8(code, pc)
    local by = buffer.readu8(code, pc + 1)
    pc += 2

    writer:writeln("local value = locals[%i] + %i", idx + 1, by)
    write_int_wrap(writer, "value")
    writer:writeln("locals[%i] = value", idx + 1)

    return pc
end

local COND_BOPS = {
    [0] = "==",
    [1] = "~=",
    [2] = "<",
    [3] = ">=",
    [4] = "==",
    [5] = ">",
    [6] = "<=",
}

for op = 0x9F, 0xA4 do
    local cond_expr = COND_BOPS[op - 0x9F]

    OPS[op] = function(
        method: t.MethodHandle,
        code: buffer,
        pc: number,
        start_pc: number,
        _,
        writer: StringBuilder.StringBuilder
    ): number
        local offset = read_i16be(code, pc)
        pc += 2

        write_pop(writer, "v2", 1)
        write_pop(writer, "v1", 1)
        writer:writeln("if v1 %s v2 then", cond_expr)
        write_jump(writer, start_pc + offset)
        writer:writeln("end")

        return pc
    end
end

OPS[0xA7] = function(
    method: t.MethodHandle,
    code: buffer,
    pc: number,
    start_pc: number,
    _,
    writer: StringBuilder.StringBuilder
): number
    local offset = read_i16be(code, pc)
    pc += 2
    write_jump(writer, start_pc + offset)
    return pc
end

OPS[0xAC] = function(
    method: t.MethodHandle,
    code: buffer,
    pc: number,
    start_pc: number,
    _,
    writer: StringBuilder.StringBuilder
): number
    write_return(writer, 1)
    return pc
end

local function compile(method: t.MethodHandle): (boolean, string)
    assert(method.info.code.kind == "java")
    local blocks = scanner.scan(method.info.code)
    if type(blocks) == "string" then
        return false, blocks
    end

    local writer = StringBuilder.new()

    writer:writeln([[
--!native
--!nolint
local function step(jvm: any, thread: any, f: any): ...any
local pc: number = f.pc
local sp: number = f.sp
local k: any = f.constants
local stack: {any} = f.stack
local locals: {any} = f.locals
local stack_depth = #thread.stack
while true do
]])

    local b = method.info.code.code
    for block_start: number, block in blocks do
        if block_start ~= 0 then
            writer:write("else")
        end

        writer:writeln(`if pc == {block_start} then`)

        local pc = block_start
        while pc <= block.end_pc do
            local wide = false
            local op = buffer.readu8(b, pc)
            local start_pc = pc
            pc += 1
            if op == 0xC4 then
                wide = true
                op = buffer.readu8(b, pc)
                pc += 1
            end

            writer:writeln(`--// pc: %i, op: 0x%02X\ndo`, start_pc, op)
            writer:writeln(`f.start_pc = %i`, start_pc)
            local op_builder = OPS[op]
            if op_builder then
                pc = op_builder(method, b, pc, start_pc, wide, writer)
            else
                print(writer:build())
                return false, string.format("no builder for opcode 0x%02X @ pc %i", op, pc - 1)
            end

            writer:writeln("end")
        end

        if block.fallthrough then
            writer:writeln("pc = %i -- fall through", block.fallthrough)
        else
            writer:writeln('error("reached end without returning")')
        end
    end

    writer:writeln("else\nerror(`bad jump target {pc}`)\nend\nend\nend\nreturn step")

    return true, writer:build()
end

return compile
