local ir = require("../ir")
local instructions = require("../ir/instructions")
local t = require("../t")
local StringBuilder = require("../utilities/StringBuilder")
type StringBuilder = StringBuilder.StringBuilder

local function rexpr(rsrc: number): string
    return `registers[{rsrc}]`
end

local emit = {}

--- Commits any information required to recover from an exception.
function emit.protect(writer: StringBuilder, start_pc: number)
    writer:writeln("f.start_pc = 0x%08X", start_pc)
end

function emit.commit(writer: StringBuilder)
    writer:writeln("f.pc = pc")
end

function emit.break_always(writer: StringBuilder)
    emit.commit(writer)
    writer:writeln("do return 'break' end")
end

function emit.jump(writer: StringBuilder, target: number)
    writer:writeln("pc = 0x%08X; do continue end", target)
end

function emit.wrap_int(writer: StringBuilder, tmp: string)
    writer:writeln("%s = (%s + 2147483648) %% 4294967296 - 2147483648", tmp, tmp)
end

function emit.return_register(writer: StringBuilder, reg: number)
    writer:writeln("do return 'return', %s end", rexpr(reg))
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

type OpImpl = (writer: StringBuilder.StringBuilder, method: t.Method, b: buffer, pc: number) -> number

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

OPS[0x81] = function(writer: StringBuilder, _, b: buffer, pc: number): number
    local rsrc = buffer.readu16(b, pc + 1)
    if rsrc ~= 0 then
        emit.return_register(writer, rsrc)
    end

    return pc + 3
end

local function generate(method: t.Method): (boolean, string)
    local code = ir.ensure_transpiled(method.class.jvm, method)
    local b = code.code
    local blocks = ir.analysis.basic_blocks(b, code.exceptions)

    local writer = StringBuilder.new()

    writer:writeln([[
--!nolint UnreachableCode
--!nolint LocalUnused

@native
local function step(jvm: any, f: any): ...any
local pc: number = f.pc
local k: any = f.constants
local registers = f.registers
while true do
]])

    for _, block in blocks do
        if block.start_pc ~= 0 then
            writer:write("else")
        end

        writer:writeln(`if pc == {block.start_pc} then`)

        local start_pc = block.start_pc
        while start_pc <= block.end_pc do
            local op = buffer.readu8(b, start_pc)
            local info = instructions[op]
            if not info then
                return false, string.format("unknown opcode 0x%02X @ pc 0x%08X", op, start_pc - 1)
            end

            writer:writeln(
                `do --// pc: 0x%08X, op: \`%s\` (0x%02X), fallible: %*`,
                start_pc,
                info.name,
                op,
                info.fallible
            )
            if info.fallible then
                emit.protect(writer, start_pc)
            end

            local op_builder = OPS[op]
            if op_builder then
                start_pc = op_builder(writer, method, b, start_pc)
            else
                --print(writer:build())
                return false, string.format("no builder for opcode 0x%02X @ pc 0x%02X", op, start_pc - 1)
            end
            writer:writeln("end\n")
        end

        writer:writeln("--// block end")
        if block.fallthrough then
            writer:writeln("pc = 0x%08X", block.fallthrough)
        else
            writer:writeln('error("missing return")')
        end
    end

    writer:writeln('else\nerror(string.format("bad jump target 0x%%08X", pc))\nend\nend\nend\n\nreturn step')

    return true, writer:build()
end

return generate
