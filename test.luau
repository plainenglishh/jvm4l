print("-----")

local jvm4l = require("./src/lib")
local jit = require("./src/lib/jit")

local function link_native(class_name: string, signature: string): jvm4l.NativeMethod?
    if class_name == "jvm4l/test/Test" and signature == "print_int:(I)V" then
        return function(jvm: jvm4l.Jvm, value)
            print(value)
            return nil
        end
    elseif class_name == "jvm4l/test/Test" and signature == "error:()V" then
        return function(jvm: jvm4l.Jvm)
            error("error was called!")
        end
    elseif class_name == "jvm4l/test/Test" and signature == "calls_error_wrapper:()V" then
        return function(jvm: jvm4l.Jvm)
            local Test = jvm:load_class("jvm4l//testTest")
            local error_wrapper = Test:resolve_method("error_wrapper", "()V")
            Test:invoke_static(error_wrapper)
            return nil
        end
    elseif class_name == "jvm4l/ApplicationClassLoader" and signature == "findClassBytes:(Ljava/lang/String;)[B" then
        return function(jvm: jvm4l.Jvm, name: jvm4l.JvmValue): jvm4l.JvmValue
            error("unimplemented")
        end
    end

    return nil
end

local epoch = os.clock()
local vm = jvm4l.Jvm.new({
    link_native = link_native,
    trace = function(message: string)
        local time_ms = (os.clock() - epoch) * 1000
        print(string.format("\x1b[2m[jvm4l @ %.3fms] %s\x1b[0m", time_ms, message))
    end,

    --jit_load = function(src: string, chunk_name: string): (...any) -> ...any
    --    local luau = require("@std/luau")
    --    local bc = luau.compile(src)
    --    return luau.load(bc, chunk_name)
    --end,

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

--local Object = vm:load_class("java/lang/Object")
--local array = vm:create_array(Object, {
--    Object:new_uninitialised(),
--    Object:new_uninitialised(),
--    Object:new_uninitialised(),
--    Object:new_uninitialised(),
--    Object:new_uninitialised(),
--})
--print(array:get_array_elements())
--print(vm:load_class("jvm4l/Luau"))

local ok, err = pcall(function(...)
    local Test = vm:load_class("jvm4l/test/Test")
    local test_ref = Test:resolve_method("main", "()V")
    --jit.try_compile(vm, Test:resolve_method("loop", "()I"))
    Test:invoke_static(test_ref)
end)

if not ok then
    print(`\x1b[31m{jvm4l.display_exception(err :: any)}\x1b[0m`)
end
