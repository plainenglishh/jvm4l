local analysis = require("../analysis")
local instructions = require("../instructions")

local function resolve(copies: { [number]: number }, reg: number): number
    while copies[reg] ~= nil do
        reg = copies[reg]
    end
    return reg
end

local function kill_register(copies: { [number]: number }, reg: number)
    copies[reg] = nil
    for k, v in copies do
        if v == reg then
            copies[k] = nil
        end
    end
end

-- TODO! preserve layout for invoke
local function copy_propagation(ir: buffer, blocks: { analysis.BasicBlock })
    for _, block in blocks do
        local copies: { [number]: number } = {}

        local pc = block.start_pc
        while pc <= block.end_pc do
            local op = buffer.readu8(ir, pc)
            local insn = instructions[op]
            assert(insn)
            local size = insn.sizeof(ir, pc)

            for _, operand in insn.operands do
                if operand.type == "register" and operand.direction == "src" then
                    local offset = pc + operand.offset
                    local old_reg = buffer.readu16(ir, offset)
                    local root_reg = resolve(copies, old_reg)
                    if root_reg ~= old_reg then
                        buffer.writeu16(ir, offset, root_reg)
                    end
                end
            end

            for _, operand in insn.operands do
                if operand.type == "register" and operand.direction == "dst" then
                    local offset = pc + operand.offset
                    local dst_reg = buffer.readu16(ir, offset)
                    kill_register(copies, dst_reg)
                end
            end

            if op == 0x01 then
                local dst = buffer.readu16(ir, pc + 1)
                local src = buffer.readu16(ir, pc + 3)

                if src == dst then
                    buffer.fill(ir, pc, 0x00, size)
                else
                    copies[dst] = src
                end
            end

            pc += size
        end
    end
end

return copy_propagation
