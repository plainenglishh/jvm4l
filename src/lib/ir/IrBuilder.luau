local BufferWriter = require("../utilities/BufferWriter")

local function assert_not_R0(reg: number)
    assert(reg ~= 0, "register cannot be R0 (null register)")
end

export type Label = { pc: number? }
type PatchInfo = {
    operand_pc: number,
    target: Label,
}

local IrBuilder = {}
export type IrBuilder = setmetatable<{
    _writer: BufferWriter.BufferWriter,
    _patches: { PatchInfo },
}, typeof(IrBuilder)>

IrBuilder.__index = IrBuilder

function IrBuilder.new(): IrBuilder
    return setmetatable({
        _writer = BufferWriter.new(),
        _patches = {},
    }, IrBuilder)
end

function IrBuilder.pc(self: IrBuilder): number
    return self._writer:cursor()
end

function IrBuilder.label(self: IrBuilder): Label
    return { bound = nil }
end

function IrBuilder.bind(self: IrBuilder, label: Label)
    assert(not label.pc, "label already bound")
    label.pc = self:pc()
end

function IrBuilder.emit_move(self: IrBuilder, dst: number, src: number)
    assert_not_R0(dst)
    assert_not_R0(src)
    self._writer:write_u8(0x01)
    self._writer:write_u16(dst)
    self._writer:write_u16(src)
end

function IrBuilder.emit_load_literal_int(self: IrBuilder, dst: number, literal: number)
    assert_not_R0(dst)
    self._writer:write_u8(0x02)
    self._writer:write_u16(dst)
    self._writer:write_i32(literal)
end

function IrBuilder.emit_load_literal_small_int(self: IrBuilder, dst: number, literal: number)
    assert_not_R0(dst)
    self._writer:write_u8(0x03)
    self._writer:write_u16(dst)
    self._writer:write_i8(literal)
end

function IrBuilder.emit_load_const(self: IrBuilder, dst: number, const: number)
    assert_not_R0(dst)
    self._writer:write_u8(0x04)
    self._writer:write_u16(dst)
    self._writer:write_u16(const)
end

function IrBuilder.emit_add_int(self: IrBuilder, dst: number, lhs: number, rhs: number)
    assert_not_R0(dst)
    assert_not_R0(lhs)
    assert_not_R0(rhs)
    self._writer:write_u8(0x05)
    self._writer:write_u16(dst)
    self._writer:write_u16(lhs)
    self._writer:write_u16(rhs)
end

function IrBuilder.emit_sub_int(self: IrBuilder, dst: number, lhs: number, rhs: number)
    assert_not_R0(dst)
    assert_not_R0(lhs)
    assert_not_R0(rhs)
    self._writer:write_u8(0x06)
    self._writer:write_u16(dst)
    self._writer:write_u16(lhs)
    self._writer:write_u16(rhs)
end

function IrBuilder.emit_add_literal_int(self: IrBuilder, dst: number, lhs: number, rhs: number)
    assert_not_R0(dst)
    assert_not_R0(lhs)
    self._writer:write_u8(0x07)
    self._writer:write_u16(dst)
    self._writer:write_u16(lhs)
    self._writer:write_i16(rhs)
end

function IrBuilder.emit_compare_eq_int(self: IrBuilder, dst: number, lhs: number, rhs: number)
    assert_not_R0(dst)
    self._writer:write_u8(0x08)
    self._writer:write_u16(dst)
    self._writer:write_u16(lhs)
    self._writer:write_u16(rhs)
end

function IrBuilder.emit_compare_lt_int(self: IrBuilder, dst: number, lhs: number, rhs: number)
    assert_not_R0(dst)
    self._writer:write_u8(0x09)
    self._writer:write_u16(dst)
    self._writer:write_u16(lhs)
    self._writer:write_u16(rhs)
end

function IrBuilder.emit_compare_eq_ref(self: IrBuilder, dst: number, lhs: number, rhs: number)
    assert_not_R0(dst)
    self._writer:write_u8(0x0A)
    self._writer:write_u16(dst)
    self._writer:write_u16(lhs)
    self._writer:write_u16(rhs)
end

function IrBuilder.build(self: IrBuilder): buffer
    local b = self._writer:build()

    for _, patch in self._patches do
        assert(patch.target.pc, "unbound target label")

        buffer.writeu32(b, patch.operand_pc, patch.target.pc)
    end

    return b
end

return IrBuilder
