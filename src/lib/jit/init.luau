local compile = require("@self/compiler")
local dbg = require("./dbg")
local t = require("./t")

local jit = {}

function jit.try_compile(jvm: t.Jvm, method: t.MethodHandle)
    local start_t = os.clock()
    if method.info.code.kind ~= "java" then
        dbg.trace(jvm, "unable to jit compile %s.%s: not a java method", method.class.fqcn, method.info.name)
        return
    end

    local jit_load = jvm._settings.jit_load
    if not jit_load then
        dbg.trace(jvm, "unable to jit compile %s.%s: jit not enabled", method.class.fqcn, method.info.name)
        return
    end

    local ok, src_or_reason = compile(method.info.code)
    if not ok then
        dbg.trace(jvm, "unable to jit compile %s.%s: %s", method.class.fqcn, method.info.name, src_or_reason)
        return
    end

    --require("@std/fs").writeStringToFile("jitout.luau", src_or_reason)

    local jit_load = assert(jvm._settings.jit_load)
    local load_ok, loaded = pcall(jit_load, src_or_reason, "=jvm4l_jit")
    if not load_ok then
        dbg.trace(jvm, "unable to jit compile %s.%s: error in loading: %s", method.class.fqcn, method.info.name, loaded)
        return
    end

    method.info.code.jit = loaded() :: t.JitStep
    local time_ms = (os.clock() - start_t) * 1000
    dbg.trace(jvm, "jit compiled %s.%s in %.3fms", method.class.fqcn, method.info.name, time_ms)
end

return jit
