print("-----")

local jvm4l = require("./src/lib")
local jit = require("./src/lib/jit")

local function link_native(class_name: string, signature: string): jvm4l.NativeMethodStep?
    if class_name == "jvm4l/test/Test" and signature == "print_int:(I)V" then
        return function(jvm, ctx, value)
            print(value)
            return "return", jvm.null
        end
    elseif class_name == "jvm4l/test/Test" and signature == "print_string:(Ljava/lang/String;)V" then
        return function(jvm, ctx, value)
            local value = value :: jvm4l.JvmObject
            print(value:inner_string())
            return "return", jvm.null
        end
    elseif class_name == "jvm4l/test/Test" and signature == "error:()V" then
        return function(jvm: jvm4l.Jvm, ctx)
            error("error was called!")
        end
    elseif class_name == "jvm4l/test/Test" and signature == "calls_error_wrapper:()V" then
        return function(jvm: jvm4l.Jvm, ctx)
            local Test = jvm:load_class("jvm4l//testTest")
            local error_wrapper = Test:resolve_method("error_wrapper", "()V")
            Test:invoke_static(error_wrapper)
            return "return", jvm.null
        end
    elseif class_name == "jvm4l/ApplicationClassLoader" and signature == "findClassBytes:(Ljava/lang/String;)[B" then
        return function(jvm: jvm4l.Jvm, ctx, name: jvm4l.JvmValue)
            error("unimplemented")
        end
    end

    return nil
end
--require("@std/fs").removeDirectory("dbgout", { recursive = true })
local epoch = os.clock()
local vm = jvm4l.Jvm.new({
    link_native = link_native,

    trace = function(message)
        local time_ms = (os.clock() - epoch) * 1000
        print(string.format("\x1b[2m[jvm4l @ %.3fms] %s\x1b[0m", time_ms, message))
    end,

    dump = function(path: string, bytes: buffer)
        local fs = require("@std/fs")
        local fullpath = `dbgout/{path}`
        local path = require("@std/path")
        local dirname = path.dirname(fullpath)
        if not fs.exists(dirname) then
            fs.createDirectory(path.dirname(fullpath), { makeParents = true })
        end
        fs.writeStringToFile(fullpath, buffer.tostring(bytes))
    end,

    jit_load = function(src: string, chunk_name: string): (...any) -> ...any
        local luau = require("@std/luau")
        local bc = luau.compile(src)
        return luau.load(bc, chunk_name)
    end,

    --jit_load = function(src: string, chunk_name: string): (...any) -> ...any
    --    local luau = require("@std/luau")
    --    return function()
    --        return luau.eval(src, {
    --            name = chunk_name,
    --            stdlib = "Safe",
    --        })
    --    end
    --end,
})

local ok, err = pcall(function(...)
    local Test = vm:load_class("jvm4l/test/Test")
    local test_ref = Test:resolve_method("main", "()V")
    local loop_ref = Test:resolve_method("loop", "()I")
    jit.compile(vm, loop_ref)

    local start = os.clock()
    for i = 1, 5 do
        Test:invoke_static(test_ref)
    end
    local finish = os.clock()
    local time_taken = ((finish - start) / 5) * 1000
    print(string.format("took %.3fms", time_taken))
end)

if not ok then
    print(`\x1b[31m{jvm4l.display_exception(err :: any)}\x1b[0m`)
end
