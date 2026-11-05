local transpiler = require("@self/transpiler")
local t = require("./t")
local ir = {}

function ir.transpile(jvm: t.Jvm, method: t.MethodHandle, k: t.ConstantPool)
    transpiler.transpile(jvm, method, k)
end

return ir
