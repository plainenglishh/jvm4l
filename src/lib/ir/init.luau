local transpiler = require("@self/transpiler")
local t = require("./t")
local ir = {}

function ir.transpile(jvm: t.Jvm, method: t.MethodHandle, k: t.ConstantPool)
    transpiler.transpile(jvm, method, k)
end

ir.analysis = require("@self/analysis")
ir.dissasembler = require("@self/dissasembler")
ir.instructions = require("@self/instructions")

return ir
