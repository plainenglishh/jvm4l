local t = require("./t")

local ConstantPool = {}
ConstantPool.__index = ConstantPool

local function check_type() end

function ConstantPool.new(class: t.JvmClass): t.ConstantPool
    return table.freeze(setmetatable({
        _jvm = class.jvm,
        _class = class,
        _classfile = assert(class._classfile, `class has no class file`),
        _resolved = {},
    }, ConstantPool))
end

function ConstantPool.get(self: t.ConstantPool, idx: number, kind: string): any end

return table.freeze(ConstantPool)
