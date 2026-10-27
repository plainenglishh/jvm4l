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
    if frame then
        if frame.code.kind == "java" then
            message ..= `, native=false, pc={frame.start_pc}`
        elseif frame.code.kind == "luau" then
            message ..= ", native=true"
        end
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

function dbg.luau_stack_depth(start_level: number?): number
    local i = start_level or 1
    while debug.info(i, "f") do
        i += 1
    end
    return i - 1
end

function dbg.luau_scoped_traceback(start_level: number, target_depth: number): string
    local current_depth = dbg.luau_stack_depth()
    local start_frame = start_level + 1
    local stop_frame = current_depth - target_depth

    if stop_frame < start_frame then
        stop_frame = current_depth
    end

    local out = {}

    for i = start_frame, stop_frame do
        local s, l, n = debug.info(i, "sln")
        if not s then
            break
        end
        if l == -1 then
            continue
        end

        if n ~= "" then
            n = ` function {n}`
        end

        table.insert(out, `    {s}:{l}{n}`)
    end

    return table.concat(out, "\n")
end

return dbg
