local instructions = require("./instructions")
export type BasicBlock = {
    start_pc: number,
    end_pc: number,
    next: number?,
    length: number,
}

local analysis = {}

function analysis.basic_blocks(b: buffer): { BasicBlock }
    local pc = 0
    local len = buffer.len(b)
    local boundaries: { number } = { 0 }

    while pc < len do
        local op = buffer.readu8(b, pc)
        local start_pc = pc

        local insn = instructions[op]
        if not insn then
            error(string.format("invalid opcode 0x%02X at 0x%08X", op, start_pc))
        end

        if not insn.size then
            error("variable length opcodes not yet supported")
        end

        pc += insn.size

        if insn.breaks and op ~= 0x82 and op ~= 0x83 then -- will never return to a `return` insn
            if not table.find(boundaries, start_pc) then
                table.insert(boundaries, start_pc)
            end
        end

        if insn.can_jump then
            local target
            if op >= 0x40 and op <= 0x46 then
                target = buffer.readu32(b, start_pc + 5)
            elseif op == 0x50 then
                target = buffer.readu32(b, start_pc + 1)
            end

            assert(target)

            if not table.find(boundaries, target) then
                table.insert(boundaries, target)
            end

            if pc < len then
                if not table.find(boundaries, pc) then
                    table.insert(boundaries, pc)
                end
            end
        end
    end

    table.sort(boundaries)

    local blocks = {}

    for i, start_pc in boundaries do
        local fallthrough_pc: number? = boundaries[i + 1]
        local end_pc = (fallthrough_pc or len) - 1
        table.insert(blocks, {
            start_pc = start_pc,
            end_pc = end_pc,
            next = fallthrough_pc,
            length = (end_pc - start_pc) + 1,
        })
    end

    return blocks
end

return analysis
