local StringBuilder = require("../utilities/StringBuilder")
local instructions = require("./instructions")
local dissasembler = {}

function dissasembler.disassemble(ir: buffer): string
    local writer = StringBuilder.new()

    local pc = 0
    local size = buffer.len(ir)

    while pc < size do
        writer:write(string.format("0x%04X: ", pc))

        local op = buffer.readu8(ir, pc)
        pc += 1
        local insn_info = instructions[op]

        writer:write(insn_info.name)

        assert(insn_info.operands ~= "variable")
        for _, operand in insn_info.operands do
            writer:write(" ")
            local value
            if operand.type == "u8" then
                value = buffer.readu8(ir, pc)
                pc += 1
            elseif operand.type == "i8" then
                value = buffer.readi8(ir, pc)
                pc += 1
            elseif operand.type == "u16" then
                value = buffer.readu16(ir, pc)
                pc += 2
            elseif operand.type == "i16" then
                value = buffer.readi16(ir, pc)
                pc += 2
            elseif operand.type == "u32" then
                value = buffer.readu32(ir, pc)
                pc += 4
            elseif operand.type == "i32" then
                value = buffer.readi32(ir, pc)
                pc += 4
            elseif operand.type == "f32" then
                value = buffer.readf32(ir, pc)
                pc += 4
            elseif operand.type == "f64" then
                value = buffer.readf64(ir, pc)
                pc += 8
            end
            assert(value)

            if operand.usage == "reg_dst" then
                writer:write(`R{value}`)
            elseif operand.usage == "reg_src" then
                writer:write(`R{value}`)
            elseif operand.usage == "constant" then
                writer:write(`K{value}`)
            elseif operand.usage == "jump_target" then
                writer:write(string.format("0x%04X", value))
            elseif operand.usage == "dispatch_type" then
                local type: string
                if value == 0 then
                    type = "VIRTUAL"
                elseif value == 1 then
                    type = "SPECIAL"
                elseif value == 2 then
                    type = "STATIC"
                else
                    type = "INVALID"
                end
                writer:write(type)
            else
                writer:write(tostring(value))
            end
        end

        writer:writeln("")
    end

    return writer:build()
end

return dissasembler
