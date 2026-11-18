local transpiler = require("@self/transpiler")
local t = require("./t")
local ir = {}

function ir.transpile(jvm: t.Jvm, method: t.MethodHandle): t.MethodCodeIr
    return transpiler.transpile(jvm, method)
end

function ir.ensure_transpiled(jvm: t.Jvm, method: t.MethodHandle): t.MethodCodeIr
    if method.info.code.kind == "ir" then
        return method.info.code
    end

    return ir.transpile(jvm, method)
end

ir.analysis = require("@self/analysis")
ir.dissasembler = require("@self/dissasembler")
ir.instructions = require("@self/instructions")

return ir
