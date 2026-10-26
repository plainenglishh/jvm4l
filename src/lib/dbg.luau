local t = require("./t")
local dbg = {}

function dbg.dump_stack(jvm: t.Jvm)
    print(`stack dump:`)

    for thread_id, thread in jvm._threads do
        local current = thread == jvm.current_thread

        print(`  thread #{thread_id}{if current then " (current)" else ""}:`)

        local has_frames = false
        for frame_no, frame in thread.stack do
            has_frames = true
            print(`    frame {frame_no}:`)
            print(`      native: {frame.code.kind == "luau"}`)
            print(`      invocation: {frame.invocation ~= nil}`)
        end

        if not has_frames then
            print("      no frames")
        end
    end
end

function dbg.vm_info(jvm: t.Jvm): string
    local thread = jvm.current_thread
    if not thread then
        return "no thread"
    end

    local frame = thread.stack[#thread.stack]
    local message = `thread={thread.id}, frame={#thread.stack}`
    if not frame then
        message ..= ")"
    elseif frame.code.kind == "java" then
        message ..= `, native=false, pc={frame.start_pc})`
    elseif frame.code.kind == "luau" then
        message ..= ", native=true)"
    end

    return message
end

function dbg.trace(jvm: t.Jvm, format: string, ...: any)
    local trace = jvm._settings.trace
    if not trace then
        return
    end

    local message = string.format(format, ...)
    trace(message)
end

return dbg
