local transpiler = require("@self/transpiler")
local t = require("./t")
local ir = {}

function ir.transpile(jvm: t.Jvm, java: t.JavaMethodInfo): t.MethodCodeJava
    return transpiler.transpile(jvm, java)
end

ir.analysis = require("@self/analysis")
ir.dissasembler = require("@self/dissasembler")
ir.instructions = require("@self/instructions")

return ir
