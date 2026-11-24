local transpiler = require("@self/transpiler")
local t = require("./t")
local ir = {}

function ir.transpile(jvm: t.Jvm, method: t.Method): t.MethodCodeIr
    return transpiler.transpile(jvm, method)
end

function ir.ensure_transpiled(jvm: t.Jvm, method: t.Method): t.MethodCodeIr
    if method.code.kind == "ir" then
        return method.code
    end

    return ir.transpile(jvm, method)
end

ir.analysis = require("@self/analysis")
ir.dissasembler = require("@self/dissasembler")
ir.instructions = require("@self/instructions")

return ir
