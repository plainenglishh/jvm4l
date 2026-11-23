local t = require("../t")
local StringBuilder = require("../utilities/StringBuilder")
local analysis = require("./analysis")
local instructions = require("./instructions")
local dissasembler = {}

local function dissasemble_block(writer: StringBuilder.StringBuilder, ir: buffer, block: analysis.BasicBlock)
    local pc = block.start_pc

    while pc < block.end_pc do
        if pc ~= block.start_pc then
            writer:write("  ")
        end
        writer:write(string.format("0x%08X: ", pc))

        local op = buffer.readu8(ir, pc)
        pc += 1
        local insn_info = instructions[op]

        writer:write(insn_info.name)

        for _, operand in insn_info.operands do
            writer:write(" ")

            if operand.type == "register" then
                local reg = buffer.readu16(ir, pc)
                pc += 2
                writer:write(`R{reg}`)
            elseif operand.type == "register_block" then
                local count = buffer.readu8(ir, pc)
                local reg = buffer.readu16(ir, pc + 1)
                pc += 3
                writer:write(`R{reg}x{count}`)
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
            elseif operand.type == "variable" then
                local size = buffer.readu16(ir, pc)
                pc += 2 + size
                writer:write(`<{size}b>`)
            else
                error(`unknown operand type {operand.type}`)
            end
        end

        writer:writeln("")
    end
end

function dissasembler.disassemble(ir: buffer, handlers: { t.ExceptionHandler }): string
    local writer = StringBuilder.new()

    writer:writeln("code:")
    local blocks = analysis.basic_blocks(ir, handlers)
    for _, block in blocks do
        writer:write("> ", block.id, block.start_pc)
        dissasemble_block(writer, ir, block)
    end

    if #handlers > 0 then
        writer:writeln("\nexceptions:")
        for i, handler in handlers do
            writer:writeln("  exception %i:", i)
            writer:writeln("    start_pc   = 0x%08X", handler.start_pc)
            writer:writeln("    end_pc     = 0x%08X", handler.end_pc)
            writer:writeln("    handler_pc = 0x%08X", handler.handler_pc)
            writer:writeln("    catch_type = %s", handler.catch_type)
        end
    end

    return writer:build()
end

return dissasembler
