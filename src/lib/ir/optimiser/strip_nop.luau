local t = require("../../t")
local instructions = require("../instructions")

local function strip_nops(ir: buffer, handlers: { t.ExceptionHandler }): buffer
    local old_len = buffer.len(ir)
    local pc_map: { [number]: number } = {}
    local pending_nops: { number } = {}
    local survivors: { { old_pc: number, new_pc: number, size: number, insn: instructions.InstructionInfo } } = {}

    local old_pc = 0
    local new_pc = 0

    while old_pc < old_len do
        local op = buffer.readu8(ir, old_pc)
        local insn = instructions[op]
        assert(insn and insn.size)

        if op == 0x00 then
            table.insert(pending_nops, old_pc)
        else
            for _, nop_pc in pending_nops do
                pc_map[nop_pc] = new_pc
            end
            table.clear(pending_nops)

            pc_map[old_pc] = new_pc
            table.insert(survivors, {
                old_pc = old_pc,
                new_pc = new_pc,
                size = insn.size,
                insn = insn,
            })
            new_pc += insn.size
        end

        old_pc += insn.size
    end

    for _, nop_pc in pending_nops do
        pc_map[nop_pc] = new_pc
    end
    pc_map[old_len] = new_pc

    if new_pc == old_len then
        return ir
    end

    local compacted = buffer.create(new_pc)

    for _, item in survivors do
        buffer.copy(compacted, item.new_pc, ir, item.old_pc, item.size)

        if item.insn.can_jump and item.insn.operands ~= "variable" then
            for _, operand in item.insn.operands do
                if operand.usage == "jump_target" then
                    local target_offset = item.new_pc + operand.offset
                    local old_target = buffer.readu32(compacted, target_offset)
                    local new_target =
                        assert(pc_map[old_target], string.format("unmapped jump target 0x%08X", old_target))
                    buffer.writeu32(compacted, target_offset, new_target)
                end
            end
        end
    end

    for _, h in handlers do
        h.start_pc = assert(pc_map[h.start_pc], "unmapped handler start_pc")
        h.end_pc = assert(pc_map[h.end_pc], "unmapped handler end_pc")
        h.handler_pc = assert(pc_map[h.handler_pc], "unmapped handler_pc")
    end

    return compacted
end

return strip_nops
