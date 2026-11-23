local t = require("../t")
local instructions = require("./instructions")

export type BasicBlock = {
    id: number,
    start_pc: number,
    end_pc: number,
    last_insn_pc: number,
    length: number,
    fallthrough: number?,
    jump_target: number?,
    successors: { number },
}

local analysis = {}

function analysis.basic_blocks(b: buffer, handlers: { t.ExceptionHandler }): { BasicBlock }
    local pc = 0
    local len = buffer.len(b)
    if len == 0 then
        return {}
    end

    local boundary_set: { [number]: boolean } = { [0] = true }
    local last_insn_info: { [number]: { pc: number, op: number, target: number?, falls_through: boolean } } = {}

    if handlers then
        for _, handler in handlers do
            if handler.handler_pc < len then
                boundary_set[handler.handler_pc] = true
            end
        end
    end

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

        local target: number? = nil
        local is_unconditional_jump = (op == 0x50)
        local is_return = op == 0x81

        if insn.can_jump then
            if op >= 0x40 and op <= 0x46 then
                target = buffer.readu32(b, start_pc + 5)
            elseif is_unconditional_jump then
                target = buffer.readu32(b, start_pc + 1)
            end

            assert(target, "jump instruction missing target")
            boundary_set[target] = true

            if pc < len then
                boundary_set[pc] = true
            end
        elseif is_return then
            if pc < len then
                boundary_set[pc] = true
            end
        end

        if insn.breaks and pc < len then
            boundary_set[pc] = true
        end

        last_insn_info[start_pc] = {
            pc = start_pc,
            op = op,
            target = target,
            falls_through = not (is_unconditional_jump or is_return),
        }
    end

    local boundaries: { number } = {}
    for b_pc in boundary_set do
        table.insert(boundaries, b_pc)
    end
    table.sort(boundaries)

    local sorted_insns: { number } = {}
    for insn_pc in last_insn_info do
        table.insert(sorted_insns, insn_pc)
    end
    table.sort(sorted_insns)

    local blocks: { BasicBlock } = {}
    local insn_idx = 1

    for i, start_pc in boundaries do
        local next_boundary: number? = boundaries[i + 1]
        local end_pc = (next_boundary or len) - 1

        while insn_idx < #sorted_insns and sorted_insns[insn_idx + 1] <= end_pc do
            insn_idx += 1
        end

        local last_pc = sorted_insns[insn_idx]
        local tail = last_insn_info[last_pc]

        local fallthrough: number? = if tail.falls_through and next_boundary then next_boundary else nil
        local successors: { number } = {}

        if fallthrough then
            table.insert(successors, fallthrough)
        end

        if tail.target and tail.target ~= fallthrough then
            table.insert(successors, tail.target)
        end

        table.insert(blocks, {
            id = i,
            start_pc = start_pc,
            end_pc = end_pc,
            last_insn_pc = last_pc,
            length = (end_pc - start_pc) + 1,
            fallthrough = fallthrough,
            jump_target = tail.target,
            successors = successors,
        })
    end

    return blocks
end

return analysis
