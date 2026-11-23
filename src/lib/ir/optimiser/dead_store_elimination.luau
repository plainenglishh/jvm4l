local analysis = require("../analysis")
local instructions = require("../instructions")

local function dead_store_elimination(ir: buffer, blocks: { analysis.BasicBlock }, local_start_reg: number)
    for _, block in blocks do
        local insns: { number } = {}
        local pc = block.start_pc
        while pc <= block.end_pc do
            local op = buffer.readu8(ir, pc)
            local insn = instructions[op]
            assert(insn and insn.size)
            table.insert(insns, pc)
            pc += insn.size
        end

        local live: { [number]: boolean } = {}

        for i = #insns, 1, -1 do
            local start_pc = insns[i]
            local op = buffer.readu8(ir, start_pc)

            local insn = instructions[op]
            assert(insn.operands ~= "variable")

            if op == 0x01 then
                local dst = buffer.readu16(ir, start_pc + 1)
                local is_live = (dst >= local_start_reg) or live[dst]
                if not is_live then
                    buffer.fill(ir, start_pc, 0x00, insn.size)
                    continue
                end
            end

            for _, operand in insn.operands do
                if operand.usage == "reg_dst" then
                    local dst = buffer.readu16(ir, start_pc + operand.offset)
                    live[dst] = nil
                end
            end
            for _, operand in insn.operands do
                if operand.usage == "reg_src" then
                    local src = buffer.readu16(ir, start_pc + operand.offset)
                    live[src] = true
                end
            end
        end
    end
end

return dead_store_elimination
