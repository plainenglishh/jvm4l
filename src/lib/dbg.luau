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

return dbg
