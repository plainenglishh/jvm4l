local ir = require("../ir")
local t = require("../t")
local StringBuilder = require("../utilities/StringBuilder")
type StringBuilder = StringBuilder.StringBuilder

local function rexpr(rsrc: number): string
    return `registers[{rsrc}]`
end

local emit = {}

function emit.commit(writer: StringBuilder)
    writer:writeln("f.pc, f.sp = pc, sp")
end

function emit.break_(writer: StringBuilder)
    emit.commit(writer)
    writer:writeln("do return 'break' end")
end

function emit.jump(writer: StringBuilder, target: number)
    writer:writeln("do pc = %*; continue end", target)
end

function emit.wrap_int(writer: StringBuilder, var_name: string)
    writer:writeln("%s = (%s + 2147483648) %% 4294967296 - 2147483648", var_name, var_name)
end

function emit.return_value(writer: StringBuilder, tmp: string)
    writer:writeln("do return 'return', %s end", tmp)
end

function emit.return_void(writer: StringBuilder)
    writer:writeln(`do return 'return' end`)
end

function emit.get_register(writer: StringBuilder, tmp: string, reg: number)
    writer:writeln("%s = %s", tmp, rexpr(reg))
end

function emit.set_register(writer: StringBuilder, reg: number, expr: string)
    writer:writeln("%s = %s", rexpr(reg), expr)
end

function emit.move_register(writer: StringBuilder, rdst: number, rsrc: number)
    writer:writeln("%s = %s", rexpr(rdst), rexpr(rsrc))
end

type OpImpl = (
    writer: StringBuilder.StringBuilder,
    method: t.MethodHandle,
    b: buffer,
    pc: number
) -> number

local OPS: { [number]: OpImpl } = {}

OPS[0x00] = function(_, _, _, pc: number): number
    return pc + 1
end

OPS[0x01] = function(writer: StringBuilder, _, b: buffer, pc: number): number
    local rdst = buffer.readu16(b, pc + 1)
    local rsrc = buffer.readu16(b, pc + 3)
    emit.move_register(writer, rdst, rsrc)
    return pc + 5
end

OPS[0x11] = function(writer: StringBuilder, _, b: buffer, pc: number): number
    local rdst = buffer.readu16(b, pc + 1)
    local literal = buffer.readi32(b, pc + 3)
    emit.set_register(writer, rdst, tostring(literal))
    return pc + 7
end

OPS[0x22] = function(writer: StringBuilder, _, b: buffer, pc: number): number
    local rdst = buffer.readu16(b, pc + 1)
    local rlhs = buffer.readu16(b, pc + 3)
    local lliteral = buffer.readu16(b, pc + 5)

    writer:writeln("local _tmp = %* + %*", rexpr(rlhs), lliteral)
    emit.wrap_int(writer, "_tmp")
    emit.set_register(writer, rdst, "_tmp")

    return pc + 9
end

OPS[0x43] = function(writer: StringBuilder, _, b: buffer, pc: number): number
    local rlhs = buffer.readu16(b, pc + 1)
    local rrhs = buffer.readu16(b, pc + 3)
    local target = buffer.readu32(b, pc + 5)

    writer:writeln("if %s >= %s then", rexpr(rlhs), rexpr(rrhs))
    emit.jump(writer, target)
    writer:writeln("end")

    return pc + 9
end

OPS[0x50] = function(writer: StringBuilder, _, b: buffer, pc: number): number
    local target = buffer.readu32(b, pc + 1)
    emit.jump(writer, target)
    return pc + 5
end

OPS[0x82] = function(writer: StringBuilder, _, b: buffer, pc: number): number
    local rsrc = buffer.readu16(b, pc + 1)
    writer:writeln("local _tmp")
    emit.get_register(writer, "_tmp", rsrc)
    emit.return_value(writer, "_tmp")

    return pc + 3
end

local function compile(method: t.MethodHandle): (boolean, string)
    assert(method.info.code.kind == "java")
    if not method.info.code.ir then
        ir.transpile(method.class.jvm, method, method.class._constant_pool or error(""))
    end
    assert(method.info.code.ir)
    local b = method.info.code.ir.code
    local blocks = ir.analysis.basic_blocks(method.info.code.ir.code)

    local writer = StringBuilder.new()

    writer:writeln([[
--!native
--!nolint
local function step(jvm: any, thread: any, f: any): ...any
local pc: number = f.pc
local sp: number = f.sp
local k: any = f.constants
local registers = f.registers
local stack_depth = #thread.stack
while true do
]])

    for _, block in blocks do
        if block.start_pc ~= 0 then
            writer:write("else")
        end

        writer:writeln(`if pc == {block.start_pc} then`)

        local pc = block.start_pc
        while pc <= block.end_pc do
            local op = buffer.readu8(b, pc)

            writer:writeln(`--// pc: 0x%08X, op: 0x%02X`, pc, op)
            writer:writeln(`f.start_pc = 0x%02X`, pc)
            local op_builder = OPS[op]
            if op_builder then
                pc = op_builder(writer, method, b, pc)
            else
                print(writer:build())
                return false, string.format("no builder for opcode 0x%02X @ pc %i", op, pc - 1)
            end
        end

        if block.next then
            writer:writeln("pc = %i -- next", block.next)
        else
            writer:writeln('error("reached end without returning")')
        end
    end

    writer:writeln("else\nerror(`bad jump target {pc}`)\nend\nend\nend\nreturn step")

    return true, writer:build()
end

return compile
