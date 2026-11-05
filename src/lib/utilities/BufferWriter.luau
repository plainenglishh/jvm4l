local BufferWriter = {}
export type BufferWriter = setmetatable<{
    _b: buffer,
    _capacity: number,
    _cursor: number,
}, typeof(BufferWriter)>
BufferWriter.__index = BufferWriter

function BufferWriter.new(initial: number?): BufferWriter
    return setmetatable({
        _b = buffer.create(initial or 1024),
        _capacity = initial or 1024,
        _cursor = 0,
    }, BufferWriter)
end

function BufferWriter._check_size(self: BufferWriter, needed: number)
    local target_size = self._capacity + needed
    local new_size = self._capacity

    while target_size > new_size do
        new_size *= 1.25
    end

    local new_b = buffer.create(new_size)
    buffer.copy(new_b, 0, self._b, 0, self._capacity)
    self._capacity = new_size
    self._b = new_b
end

function BufferWriter.cursor(self: BufferWriter): number
    return self._cursor
end

function BufferWriter.write_u8(self: BufferWriter, value: number)
    self:_check_size(1)
    buffer.writeu8(self._b, self._cursor, value)
    self._cursor += 1
end

function BufferWriter.write_i8(self: BufferWriter, value: number)
    self:_check_size(1)
    buffer.writei8(self._b, self._cursor, value)
    self._cursor += 1
end

function BufferWriter.write_u16(self: BufferWriter, value: number)
    self:_check_size(2)
    buffer.writeu16(self._b, self._cursor, value)
    self._cursor += 2
end

function BufferWriter.write_i16(self: BufferWriter, value: number)
    self:_check_size(2)
    buffer.writei16(self._b, self._cursor, value)
    self._cursor += 2
end

function BufferWriter.write_u32(self: BufferWriter, value: number)
    self:_check_size(4)
    buffer.writeu32(self._b, self._cursor, value)
    self._cursor += 4
end
function BufferWriter.write_i32(self: BufferWriter, value: number)
    self:_check_size(4)
    buffer.writei32(self._b, self._cursor, value)
    self._cursor += 4
end

function BufferWriter.write_f32(self: BufferWriter, value: number)
    self:_check_size(4)
    buffer.writef32(self._b, self._cursor, value)
    self._cursor += 4
end

function BufferWriter.write_f64(self: BufferWriter, value: number)
    self:_check_size(8)
    buffer.writef64(self._b, self._cursor, value)
    self._cursor += 8
end

function BufferWriter.build(self: BufferWriter): buffer
    local b = buffer.create(self._cursor)
    buffer.copy(b, 0, self._b, 0, self._cursor)
    return b
end

return BufferWriter
