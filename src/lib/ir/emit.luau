local BufferWriter = require("../utilities/BufferWriter")
type BufferWriter = BufferWriter.BufferWriter

export type JumpTarget = {
    java_pc: number,
    operand_pc: number,
}

local emit = {}

function emit.nop(ir: BufferWriter)
    ir:write_u8(0x00)
end

function emit.move(ir: BufferWriter, rdst: number, rsrc: number)
    ir:write_u8(0x01)
    ir:write_u16(rdst)
    ir:write_u16(rsrc)
end

function emit.load_literal_null(ir: BufferWriter, rdst: number)
    ir:write_u8(0x10)
    ir:write_u16(rdst)
end

function emit.load_literal_int(ir: BufferWriter, rdst: number, value: number)
    ir:write_u8(0x11)
    ir:write_u16(rdst)
    ir:write_i32(value)
end

function emit.load_literal_float(ir: BufferWriter, rdst: number, value: number)
    ir:write_u8(0x12)
    ir:write_u16(rdst)
    ir:write_f32(value)
end

function emit.load_literal_long(ir: BufferWriter, rdst: number, value: integer)
    error("")
end

function emit.load_literal_double(ir: BufferWriter, rdst: number, value: number)
    ir:write_u8(0x14)
    ir:write_u16(rdst)
    ir:write_f64(value)
end

function emit.load_const(ir: BufferWriter, rdst: number, kconst: number)
    ir:write_u8(0x15)
    ir:write_u16(rdst)
    ir:write_u16(kconst)
end

function emit.add_int(ir: BufferWriter, rdst: number, rlhs: number, rrhs: number)
    ir:write_u8(0x20)
    ir:write_u16(rdst)
    ir:write_u16(rlhs)
    ir:write_u16(rrhs)
end

function emit.sub_int(ir: BufferWriter, rdst: number, rlhs: number, rrhs: number)
    ir:write_u8(0x21)
    ir:write_u16(rdst)
    ir:write_u16(rlhs)
    ir:write_u16(rrhs)
end

function emit.add_literal_int(ir: BufferWriter, rdst: number, rlhs: number, lrhs: number)
    ir:write_u8(0x22)
    ir:write_u16(rdst)
    ir:write_u16(rlhs)
    ir:write_i32(lrhs)
end

function emit.compare_x_int(ir: BufferWriter, cond: number, rdst: number, rlhs: number, rrhs: number)
    ir:write_u8(0x40 + cond)
    ir:write_u16(rdst)
    ir:write_u16(rlhs)
    ir:write_u16(rrhs)
end

function emit.jump(ir: BufferWriter, jtarget: number): JumpTarget
    ir:write_u8(0x50)
    local operand_pc = ir:cursor()
    ir:write_u32(0)
    return {
        operand_pc = operand_pc,
        java_pc = jtarget,
    }
end

function emit.jump_if(ir: BufferWriter, rsrc: number, jtarget: number): JumpTarget
    ir:write_u8(0x51)
    ir:write_u16(rsrc)
    local operand_pc = ir:cursor()
    ir:write_u32(0)
    return {
        operand_pc = operand_pc,
        java_pc = jtarget,
    }
end

function emit.get_field(ir: BufferWriter, rdst: number, rsrc: number, kfield: number)
    ir:write_u8(0x60)
    ir:write_u16(rdst)
    ir:write_u16(rsrc)
    ir:write_u16(kfield)
end

function emit.set_field(ir: BufferWriter, rdst: number, rsrc: number, kfield: number)
    ir:write_u8(0x61)
    ir:write_u16(rdst)
    ir:write_u16(rsrc)
    ir:write_u16(kfield)
end

function emit.get_static(ir: BufferWriter, rdst: number, kfield: number)
    ir:write_u8(0x62)
    ir:write_u16(rdst)
    ir:write_u16(kfield)
end

function emit.set_static(ir: BufferWriter, rsrc: number, kfield: number)
    ir:write_u8(0x62)
    ir:write_u16(rsrc)
    ir:write_u16(kfield)
end

function emit.new(ir: BufferWriter, rdst: number, kclass: number)
    ir:write_u8(0x70)
    ir:write_u16(rdst)
    ir:write_u16(kclass)
end

function emit.throw(ir: BufferWriter, rsrc: number)
    ir:write_u8(0x71)
    ir:write_u16(rsrc)
end

function emit.invoke(
    ir: BufferWriter,
    rdst: number,
    kmethod: number,
    rsrc: number,
    arg_count: number,
    dispatch_type: number
)
    ir:write_u8(0x80)
    ir:write_u16(rdst)
    ir:write_u16(kmethod)
    ir:write_u16(rsrc)
    ir:write_u8(arg_count)
    assert(dispatch_type >= 0 and dispatch_type <= 3)
    ir:write_u8(dispatch_type)
end

function emit.invoke_void(ir: BufferWriter, kmethod: number, rsrc: number, arg_count: number, dispatch_type: number)
    ir:write_u8(0x81)
    ir:write_u16(kmethod)
    ir:write_u16(rsrc)
    ir:write_u8(arg_count)
    assert(dispatch_type >= 0 and dispatch_type <= 3)
    ir:write_u8(dispatch_type)
end

function emit.return_(ir: BufferWriter, rsrc: number)
    ir:write_u8(0x82)
    ir:write_u16(rsrc)
end

function emit.return_void(ir: BufferWriter)
    ir:write_u8(0x83)
end

return emit
