local dbg = require("../dbg")
local descriptors = require("../descriptors")
local t = require("../t")
local util = require("../util")
local BufferWriter = require("../utilities/BufferWriter")
local dissasembler = require("./dissasembler")
local emit = require("./emit")

local function sign_extend_byte(byte: number): number
    return if byte >= 0x80 then byte - 0x100 else byte
end

local function sign_extend_short(short: number): number
    return if short >= 0x8000 then short - 0x10000 else short
end

local function read_u16be(b: buffer, offset: number): number
    local b1 = buffer.readu8(b, offset)
    local b2 = buffer.readu8(b, offset + 1)
    return bit32.bor(bit32.lshift(b1, 8), b2)
end

local function read_i16be(b: buffer, offset: number): number
    return sign_extend_short(read_u16be(b, offset))
end

local function supports_wide(op: number): boolean
    return op == 0x15
        or op == 0x17
        or op == 0x19
        or op == 0x16
        or op == 0x18
        or op == 0x36
        or op == 0x38
        or op == 0x3a
        or op == 0x37
        or op == 0x39
        or op == 0xa9
        or op == 0x84
end

local transpiler = {}

type JumpTarget = {
    java_pc: number,
    operand_pc: number,
}

type SlotSize = "1" | "2"

local function condense_locals(code: t.MethodCodeJava): { [number]: number }
    -- condense old local indexes to new local indexes (note, not register indexes)
    return util.unimplemented()
end

function transpiler.transpile(jvm: t.Jvm, method: t.MethodHandle, k: t.ConstantPool)
    local code = method.info.code
    assert(code.kind == "java")

    dbg.trace(jvm, `transpiling {method.class.fqcn}.{method.info.signature}`)
    local bc = code.code
    local bc_len = buffer.len(bc)
    local ir = BufferWriter.new(bc_len * 2)

    local pc_map: { [number]: number } = {} -- sparse map, use the ir pc above it if nil
    local jump_targets: { JumpTarget } = {}
    local stack: { SlotSize } = {}
    local stack_depth = 0
    --local locals = condense_locals(code)

    local function get_pc(old_pc: number): number
        return pc_map[old_pc] or error(`bad pc {old_pc}`)
    end

    local pc = 0

    local function fetch_u8(): number
        local value = buffer.readu8(bc, pc)
        pc += 1
        return value
    end

    local function fetch_u16(): number
        local value = read_u16be(bc, pc)
        pc += 2
        return value
    end

    local function fetch_i16(): number
        local value = read_i16be(bc, pc)
        pc += 2
        return value
    end

    local function push_stack_register(slots: SlotSize): number
        stack_depth += 1
        stack[stack_depth] = slots
        return stack_depth
    end

    local function pop_stack_register(check_size: SlotSize | "any"): (number, SlotSize)
        local size = stack[stack_depth]
        if check_size ~= "any" then
            assert(size == check_size, `expected {check_size}, got {size}`)
        end
        stack_depth -= 1
        return stack_depth + 1, size
    end

    local function get_local_register(index: number): number
        return code.max_stack + index + 1 --locals[index]
    end

    while pc < bc_len do
        local start_pc = pc
        pc_map[start_pc] = ir:cursor()
        local op = fetch_u8()

        local wide = false
        if op == 0xC4 then -- wide
            wide = true
            op = fetch_u8()
        end

        if wide and not supports_wide(op) then
            error(string.format("opcode %02X does not support wide", op))
        end

        if op == 0x00 then -- `nop`
            emit.nop(ir)
        elseif op == 0x01 then -- `aconst_null`
            local rdst = push_stack_register("1")
            emit.load_literal_null(ir, rdst)
        elseif op >= 0x02 and op <= 0x08 then -- `iconst_<i>`
            local rdst = push_stack_register("1")
            local value = op - 0x03
            emit.load_literal_int(ir, rdst, value)
        elseif op >= 0x09 and op <= 0x0A then -- `lconst_<i>`
            local rdst = push_stack_register("2")
            local value = op - 0x09
            emit.load_literal_long(ir, rdst, integer.create(value))
        elseif op >= 0x0B and op <= 0x0D then -- `fconst_<i>`
            local rdst = push_stack_register("1")
            local value = op - 0x0B
            emit.load_literal_float(ir, rdst, value)
        elseif op >= 0x0E and op <= 0x0F then -- `dconst_<i>`
            local rdst = push_stack_register("2")
            local value = op - 0x0E
            emit.load_literal_double(ir, rdst, value)
        elseif op == 0x10 then -- `bipush`
            local rdst = push_stack_register("1")
            local value = sign_extend_byte(fetch_u8())
            emit.load_literal_int(ir, rdst, value)
        elseif op == 0x11 then -- `sipush`
            local rdst = push_stack_register("1")
            local value = sign_extend_short(fetch_u16())
            emit.load_literal_int(ir, rdst, value)
        elseif op == 0x12 then -- `ldc`
            local kconst = fetch_u8()

            if k:is(kconst, "int") then
                local rdst = push_stack_register("1")
                local value = k:get(kconst, "int")
                emit.load_literal_int(ir, rdst, value)
            elseif k:is(kconst, "float") then
                local rdst = push_stack_register("1")
                local value = k:get(kconst, "float")
                emit.load_literal_float(ir, rdst, value)
            elseif k:is(kconst, "long") then
                local rdst = push_stack_register("2")
                local value = k:get(kconst, "long")
                emit.load_literal_long(ir, rdst, value)
            elseif k:is(kconst, "double") then
                local rdst = push_stack_register("2")
                local value = k:get(kconst, "double")
                emit.load_literal_double(ir, rdst, value)
            else
                local rdst = push_stack_register("1")
                emit.load_const(ir, rdst, kconst)
            end
        elseif op >= 0x1A and op <= 0x1D then -- `iload_<n>`
            local rdst = push_stack_register("1")
            local rsrc = get_local_register(op - 0x1A)
            emit.move(ir, rdst, rsrc)
        elseif op >= 0x2A and op <= 0x2D then -- `aload_<n>`
            local rdst = push_stack_register("1")
            local rsrc = get_local_register(op - 0x2A)
            emit.move(ir, rdst, rsrc)
        elseif op >= 0x3B and op <= 0x3E then -- `istore_<n>`
            local rdst = get_local_register(op - 0x3B)
            local rsrc = pop_stack_register("1")
            emit.move(ir, rdst, rsrc)
        elseif op >= 0x4B and op <= 0x4E then -- `astore_<n>`
            local rdst = get_local_register(op - 0x4B)
            local rsrc = pop_stack_register("1")
            emit.move(ir, rdst, rsrc)
        elseif op == 0x59 then -- `dup`
            local src_stack_reg = stack_depth
            local dst_stack_reg = push_stack_register("1")
            emit.move(ir, dst_stack_reg, src_stack_reg)
        elseif op == 0x60 then -- `iadd`
            local rrhs = pop_stack_register("1")
            local rlhs = pop_stack_register("1")
            local rdst = push_stack_register("1")
            emit.add_int(ir, rdst, rlhs, rrhs)
        elseif op == 0x64 then -- `isub`
            local rrhs = pop_stack_register("1")
            local rlhs = pop_stack_register("1")
            local rdst = push_stack_register("1")
            emit.sub_int(ir, rdst, rlhs, rrhs)
        elseif op == 0x84 then -- `iinc`
            local rdst = get_local_register(fetch_u8())
            local value = sign_extend_byte(fetch_u8())
            emit.add_literal_int(ir, rdst, rdst, value)
        elseif op >= 0x99 and op <= 0x9E then -- `if<cond>`
            local cond = op - 0x99
            local rlhs = pop_stack_register("1")
            local rdst = push_stack_register("1")
            local offset = fetch_i16()
            emit.compare_x_int(ir, cond, rdst, rlhs, 0)
            table.insert(jump_targets, emit.jump_if(ir, rdst, start_pc + offset))
        elseif op >= 0x9F and op <= 0xA4 then -- `if_icmp<cond>`
            local cond = op - 0x9F
            local rrhs = pop_stack_register("1")
            local rlhs = pop_stack_register("1")
            local rdst = push_stack_register("1")
            local offset = fetch_i16()
            emit.compare_x_int(ir, cond, rdst, rlhs, rrhs)
            table.insert(jump_targets, emit.jump_if(ir, rdst, start_pc + offset))
        elseif op == 0xA7 then
            local offset = fetch_i16()
            table.insert(jump_targets, emit.jump(ir, start_pc + offset))
        elseif op == 0xB0 or op == 0xB1 or (op >= 0xAC and op <= 0xAF) then -- `areturn`, `return`, `ireturn` `freturn`, `lreturn`, `dreturn`
            local rsrc: number?

            if op == 0xAD or op == 0xAF then
                rsrc = pop_stack_register("2")
            elseif op ~= 0xB1 then
                rsrc = pop_stack_register("1")
            end

            if rsrc then
                emit.return_(ir, rsrc)
            else
                emit.return_void(ir)
            end
        elseif op == 0xB2 then -- `getstatic`
            local kfield = fetch_u16()
            local rdst = push_stack_register("1")
            emit.get_static(ir, rdst, kfield)
        elseif op == 0xB3 then -- `putstatic`
            local kfield = fetch_u16()
            local rsrc = pop_stack_register("any")
            emit.set_static(ir, rsrc, kfield)
        elseif op == 0xB4 then -- `getfield`
            local kfield = fetch_u16()
            local rsrc = pop_stack_register("1")
            local rdst = push_stack_register("1")
            emit.get_field(ir, rdst, rsrc, kfield)
        elseif op == 0xB5 then -- `putfield`
            local kfield = fetch_u16()
            local rdst = pop_stack_register("1")
            local rsrc = pop_stack_register("any")
            emit.set_field(ir, rdst, rsrc, kfield)
        elseif op >= 0xB6 and op <= 0xB8 then -- `invokevirtual`, `invokespecial`, `invokestatic`
            local dispatch_type = op - 0xB6

            local kmethod = fetch_u16()
            local method = k:get(kmethod, "method")
            local arg_words = descriptors.argument_words(method.info.descriptor)
            local arg_count = #arg_words
            if op ~= 0xB8 then
                arg_count += 1
            end

            local void = string.sub(method.info.descriptor, -1, -1) == "V"
            local rsrc = (stack_depth - arg_count) + 1
            stack_depth -= arg_count

            if void then
                emit.invoke_void(ir, kmethod, rsrc, arg_count, dispatch_type)
            else
                local rdst = push_stack_register("1")
                emit.invoke(ir, rdst, kmethod, rsrc, arg_count, dispatch_type)
            end
        elseif op == 0xBB then -- `new`
            local rdst = push_stack_register("1")
            local kclass = fetch_u16()
            emit.new(ir, rdst, kclass)
        elseif op == 0xBF then -- `throw`
            local rsrc = pop_stack_register("1")
            emit.throw(ir, rsrc)
        else
            error(string.format("unimplemented opcode 0x%02X", op))
        end
    end

    local ir = ir:build()

    --// final stage: resolve jump targets
    for _, jump in jump_targets do
        buffer.writeu32(ir, jump.operand_pc, get_pc(jump.java_pc))
    end

    --local stmp = os.clock()
    --dbg.dump_artifact(jvm, `ir-{stmp}.out`, ir)
    dbg.dump_artifact(jvm, `ir-{method.info.name}.asm`, dissasembler.disassemble(ir))

    local exceptions: { t.ExceptionHandler } = {}
    for i, exception in code.exceptions do
        exceptions[i] = {
            start_pc = get_pc(exception.start_pc),
            end_pc = get_pc(exception.end_pc),
            handler_pc = get_pc(exception.handler_pc),
        }
    end

    local line_numbers
    if code.line_numbers then
        line_numbers = {}
        for i, entry in code.line_numbers do
            line_numbers[i] = {
                line = entry.line,
                start_pc = get_pc(entry.start_pc),
            }
        end
    end

    code.ir = {
        total_registers = code.max_stack + code.max_locals + 1,
        code = ir,
        exceptions = exceptions,
        line_numbers = line_numbers,
    }

    dbg.trace(jvm, "end transpile")
end

return transpiler
