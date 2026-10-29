local t = require("../t")

--[[
    leaders:
    - first op
    - jump targets
    - anything that would result in a step break (see exec engine), including:
        - stack depth changes (invocations, returns, places that may cause a clinit to be invoked)
        - monitor enter/exit

    budget will be decremented and checked at every branch
    in the rare case an exception creation causes <clinit> to be pushed on the stack, i do not care... that can be deferred until the jit step exits
]]

type OpTargets = (op: number, code: buffer, pc: number, start_pc: number, wide: boolean) -> ({ number }, number)
type OpTargetsGenerator<T...> = (T...) -> OpTargets

local function sign_extend_short(short: number): number
    return if short >= 0x8000 then short - 0x10000 else short
end

local function read_u16be(b: buffer, offset: number): number
    return bit32.rshift(bit32.byteswap(buffer.readu16(b, offset)), 16)
end

local function read_i16be(b: buffer, offset: number): number
    return sign_extend_short(read_u16be(b, offset))
end

local TARGETS: { [number]: OpTargets } = {}
do
    local function set_range<T...>(min_op: number, max_op: number, generator: OpTargetsGenerator<T...>, ...: T...)
        for op = min_op, max_op do
            TARGETS[op] = generator(...)
        end
    end

    local function no_targets(size: number): OpTargets
        return function(_, code: buffer, pc: number, start_pc: number): ({ number }, number)
            return {}, start_pc + size
        end
    end

    local function i16(count: number)
        return function(_, code: buffer, pc: number, start_pc: number): ({ number }, number)
            local targets = {}

            for i = 1, count do
                table.insert(targets, start_pc + read_i16be(code, pc))
                pc += 2
            end

            return targets, pc
        end
    end

    local function will_break(size: number)
        return function(_, code: buffer, pc: number, start_pc: number): ({ number }, number)
            return { start_pc + size }, start_pc + size
        end
    end

    --- no targets
    set_range(0x00, 0x0F, no_targets, 1)
    TARGETS[0x10] = no_targets(2)
    TARGETS[0x11] = no_targets(3)
    set_range(0x1A, 0x1D, no_targets, 1)
    set_range(0x2A, 0x2D, no_targets, 1)
    set_range(0x3B, 0x3E, no_targets, 1)
    TARGETS[0x59] = no_targets(1)
    TARGETS[0x60] = no_targets(1)
    TARGETS[0x64] = no_targets(1)
    TARGETS[0x64] = no_targets(3)
    TARGETS[0x84] = no_targets(1)
    set_range(0xAC, 0xB1, no_targets, 1)
    set_range(0xB4, 0xB5, no_targets, 3)
    TARGETS[0xBF] = no_targets(1)
    TARGETS[0x12] = no_targets(2)
    TARGETS[0xBB] = no_targets(3)
    set_range(0xB2, 0xB3, no_targets, 3)

    -- `if<cond>`, `if_icmp<cond>`
    set_range(0x99, 0xA4, i16, 1)
    -- `goto`
    TARGETS[0xA7] = i16(1)
    -- `invokevirtual`, `invokespecial`, `invokestatic`
    set_range(0xB6, 0xB8, will_break, 3)
end

local function get_targets(code: t.MethodCodeJava): { number } | string
    local b = code.code
    local pc = 0
    local len = buffer.len(b)
    local targets = { 0 }

    for _, exception_handler in code.exceptions do
        if not table.find(targets, exception_handler.handler_pc) then
            table.insert(targets, exception_handler.handler_pc)
        end
    end

    while pc < len do
        local wide = false
        local op = buffer.readu8(b, pc)
        pc += 1

        if op == 0xC4 then
            wide = true
            op = buffer.readu8(b, pc)
            pc += 1
        end

        local op_targets = TARGETS[op]
        if not op_targets then
            return string.format("no target extractor for opcode 0x%02X @ pc %i", op, pc - 1)
        end

        local op_targets, new_pc = op_targets(op, b, pc, pc - 1, wide)

        for _, target in op_targets do
            if not table.find(targets, target) then
                table.insert(targets, target)
            end
        end

        pc = new_pc
    end

    table.sort(targets)
    return targets
end

export type Block = {
    start_pc: number,
    end_pc: number,
    fallthrough: number?,
}

export type BlockMap = { [number]: Block }

local scanner = {}

function scanner.scan(code: t.MethodCodeJava): { [number]: Block } | string
    local targets = get_targets(code)
    if type(targets) == "string" then
        return targets
    end

    local blocks: { [number]: Block } = {}

    for i, start_pc in targets do
        local fallthrough_pc: number? = targets[i + 1]
        local end_pc = (fallthrough_pc or buffer.len(code.code)) - 1
        blocks[start_pc] = {
            start_pc = start_pc,
            end_pc = end_pc,
            fallthrough = fallthrough_pc,
        }
    end

    return blocks
end

return scanner
