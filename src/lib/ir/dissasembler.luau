local t = require("../t")
local StringBuilder = require("../utilities/StringBuilder")
local analysis = require("./analysis")
local instructions = require("./instructions")
local dissasembler = {}

local function dissasemble_block(
    writer: StringBuilder.StringBuilder,
    ir: buffer,
    block: analysis.BasicBlock,
    encountered_constants: { [number]: boolean }
)
    local pc = block.start_pc

    while pc < block.end_pc do
        if pc ~= block.start_pc then
            writer:write("    ")
        end
        writer:write(string.format("0x%08X: ", pc))

        local op = buffer.readu8(ir, pc)
        pc += 1
        local insn = instructions[op]

        writer:write(insn.name)

        for _, operand in insn.operands do
            writer:write(" ")

            if operand.type == "register" then
                local reg = buffer.readu16(ir, pc)
                pc += 2
                writer:write(`R{reg}`)
            elseif operand.type == "register_array" then
                local count = buffer.readu8(ir, pc)
                writer:write(`[`)
                pc += 1
                for i = 0, count - 1 do
                    if i ~= 0 then
                        writer:write(", ")
                    end

                    local reg = buffer.readu16(ir, pc)
                    pc += 2
                    writer:write("R%i", reg)
                end
                writer:write("]")
            elseif operand.type == "literal" then
                local value
                if operand.literal_type == "i32" then
                    value = buffer.readi32(ir, pc)
                    pc += 4
                elseif operand.literal_type == "f32" then
                    value = buffer.readf32(ir, pc)
                    pc += 4
                elseif operand.literal_type == "i64" then
                    value = buffer.readinteger(ir, pc)
                    pc += 8
                elseif operand.literal_type == "f64" then
                    value = buffer.readf64(ir, pc)
                    pc += 8
                end
                writer:write(tostring(value))
            elseif operand.type == "constant" then
                local kidx = buffer.readu16(ir, pc)
                encountered_constants[kidx] = true
                pc += 2
                writer:write(`K{kidx}`)
            elseif operand.type == "jump_target" then
                local target = buffer.readu32(ir, pc)
                pc += 4
                writer:write(string.format("0x%08X", target))
            elseif operand.type == "dispatch_type" then
                local value = buffer.readu8(ir, pc)
                pc += 1

                if value == 0 then
                    writer:write("VIRTUAL")
                elseif value == 1 then
                    writer:write("SPECIAL")
                elseif value == 2 then
                    writer:write("STATIC")
                else
                    writer:write("INVALID")
                end
            elseif operand.type == "data" then
                local size = buffer.readu16(ir, pc)
                pc += 2 + size
                writer:write(`<{size}b>`)
            else
                error(`unknown operand type {operand.type}`)
            end
        end

        if insn.fallible or insn.can_jump or insn.breaks then
            writer:write(" (")
            if insn.can_jump then
                writer:write(">")
            end

            if insn.fallible then
                writer:write("!")
            end

            if insn.breaks then
                writer:write("*")
            end
            writer:write(")")
        end

        writer:writeln("")
    end
end

function dissasembler.disassemble(code: t.MethodCodeJava): string
    local writer = StringBuilder.new()

    writer:writeln("Name: %s", code.proto.debug_name)
    writer:writeln("Registers:")
    if code.temp_register_count > 0 then
        writer:writeln("    Temp:   %i (R1 - R%i)", code.temp_register_count, code.temp_register_count)
    else
        writer:writeln("    Temp:   0 (none)")
    end
    if code.local_register_count > 0 then
        writer:writeln(
            "    Locals: %i (R%i - R%i)",
            code.local_register_count,
            code.local_register_start,
            code.local_register_start + code.local_register_count - 1
        )
    else
        writer:writeln("    Locals: 0 (none)")
    end
    writer:writeln("    Total:  %i", code.total_registers)

    local encountered_constants = {}
    writer:writeln("Instructions:")
    local blocks = analysis.basic_blocks(code.code, code.exceptions)
    for _, block in blocks do
        writer:write("  > ", block.id, block.start_pc)
        dissasemble_block(writer, code.code, block, encountered_constants)
    end

    if #code.exceptions > 0 then
        writer:writeln("Exceptions:")
        for i, handler in code.exceptions do
            writer:writeln(
                "    %i = 0x%08X..0x%08X -> 0x%08X (%s)",
                i,
                handler.start_pc,
                handler.end_pc,
                handler.handler_pc,
                if handler.catch_type then handler.catch_type.fqcn else "any"
            )
        end
    end

    if code.line_numbers and #code.line_numbers > 0 then
        writer:writeln("Line Numbers:")
        local lines = code.line_numbers
        for i, line_number_entry in lines do
            writer:writeln(
                "    %i = 0x%08X..0x%08X = %i",
                i,
                line_number_entry.start_pc,
                line_number_entry.end_pc,
                line_number_entry.line
            )
        end
    end

    return writer:build()
end

return dissasembler
