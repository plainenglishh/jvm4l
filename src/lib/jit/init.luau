local generate = require("@self/generate")
local dbg = require("./dbg")
local t = require("./t")

local function set_jit_state_compiled(state: t.JitState, closure: t.MethodStepJava)
    (state :: any).kind = "compiled"
    (state :: any).closure = closure
end

local function set_jit_state_failed(state: t.JitState)
    (state :: any).kind = "failed"
end

local function compiled(jvm: t.Jvm, method: t.Method): t.MethodStepJava?
    local code = method.code:get()
    if code.kind ~= "java" then
        return nil
    end

    local jit_state = code.jit
    if jit_state.kind == "compiled" then
        return jit_state.closure
    elseif jit_state.kind == "failed" then
        return nil
    end

    return nil
end

local function compile(jvm: t.Jvm, method: t.Method)
    local code = method.code:get()
    assert(code.kind == "java", "attempt to jit compile non-java method")

    local jit_state = code.jit

    local start_t = os.clock()

    local ok, src_or_reason = generate(method)
    if not ok then
        dbg.trace(jvm, "unable to jit compile `%s`: %s", method.debug_name, src_or_reason)
        set_jit_state_failed(jit_state)
        return
    end

    dbg.dump_artifact(jvm, `jit/{method.class.name}_{method.name:gsub("[<>]", "__")}.luau`, src_or_reason)

    local jit_load = assert(jvm._settings.jit_load)
    local load_ok, loaded = pcall(jit_load, src_or_reason, "=jvm4l_jit")
    if not load_ok then
        dbg.trace(jvm, "unable to jit compile `%s`: error in loading: %s", method.debug_name, loaded)
        set_jit_state_failed(jit_state)
        return
    end

    --code.jit = loaded() :: t.MethodStepJava
    local time_ms = (os.clock() - start_t) * 1000
    dbg.trace(jvm, "jit compiled `%s` in %.3fms", method.debug_name, time_ms)
    set_jit_state_compiled(jit_state, loaded())
end

local jit = {}

function jit.compile(jvm: t.Jvm, method: t.Method)
    compile(jvm, method)
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
