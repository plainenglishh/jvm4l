local generate = require("@self/generate")
local dbg = require("./dbg")
local t = require("./t")

local function set_jit_state_compiled(state: t.JitState, closure: t.MethodStepJava)
    (state :: any).kind = "compiled"
    (state :: any).closure = closure
end

local function set_jit_state_failed(state: t.JitState, reason: string)
    (state :: any).kind = "failed"
    (state :: any).reason = reason
end

local function compiled(jvm: t.Jvm, method: t.Method): t.MethodStepJava?
    local code = method.code:get()
    if code.kind ~= "java" then
        return nil
    end

    local jit_state = code.jit
    if jit_state.kind == "compiled" then
        return jit_state.closure
    end

    return nil
end

local jit = {}

function jit.compile(jvm: t.Jvm, method: t.Method)
    local code = method.code:get()
    assert(code.kind == "java", "attempt to jit compile non-java method")

    local jit_state = code.jit

    local tracer = dbg.timed_trace(jvm)
    local jit_load = jvm._settings.jit_load

    if not jit_load then
        tracer("unable to jit compile: no jit_load", method.debug_name)
        set_jit_state_failed(jit_state, "no jit load")
        return
    end

    local ok, src_or_reason = generate(method)
    if not ok then
        tracer("unable to jit compile `%s`: %s", method.debug_name, src_or_reason)
        set_jit_state_failed(jit_state, src_or_reason)
        return
    end

    dbg.dump_artifact(jvm, dbg.fs_safe_debug_name(method.debug_name) .. ".luau", src_or_reason)

    local load_ok, loaded = pcall(jit_load, src_or_reason, "=jvm4l_jit")
    if not load_ok then
        tracer("unable to jit compile `%s`: error in loading: %s", method.debug_name, loaded)
        set_jit_state_failed(jit_state, loaded :: any)
        return
    end

    tracer("jit compiled `%s` in %t", method.debug_name)
    set_jit_state_compiled(jit_state, loaded())
end

function jit.compiled(jvm: t.Jvm)
    return compiled
end

function jit.query(jvm: t.Jvm, method: t.Method): t.MethodStepJava?
    local compiled_closure = compiled(jvm, method)
    if compiled_closure then
        return compiled_closure
    end

    --- do instrumentation here later
    return nil
end

return jit
