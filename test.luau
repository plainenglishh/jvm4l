print("-----")
local jvm4l = require("./src/lib")

local function link_native(class_name: string, signature: string): jvm4l.NativeMethod?
    if class_name == "jvm4l/Test" and signature == "print_int:(I)V" then
        return function(jvm: jvm4l.Jvm, value)
            print(value)
            return nil
        end
    elseif class_name == "jvm4l/Test" and signature == "error:()V" then
        return function(jvm: jvm4l.Jvm)
            error("error was called!")
        end
    elseif class_name == "jvm4l/Test" and signature == "calls_error_wrapper:()V" then
        return function(jvm: jvm4l.Jvm)
            local Test = jvm:resolve_class("jvm4l/Test")
            local error_wrapper = jvm:resolve_method(Test, "error_wrapper", "()V")
            Test:invoke_static(error_wrapper)
            return nil
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
})

--local Object = vm:resolve_class("java/lang/Object")
--local array = vm:create_array(Object, {
--    Object:new_uninitialised(),
--    Object:new_uninitialised(),
--    Object:new_uninitialised(),
--    Object:new_uninitialised(),
--    Object:new_uninitialised(),
--})
--print(array:get_array_elements())
--print(vm:resolve_class("jvm4l/Luau"))

local ok, err = pcall(function(...)
    local Test = vm:resolve_class("jvm4l/Test")
    local test_ref = vm:resolve_method(Test, "main", "()V")
    Test:invoke_static(test_ref)

    --local Double = vm:resolve_class("java/lang/Double")
    --local hashCode = vm:resolve_method(Double, "hashCode", "()I")
    --local obj = Double:_new_uninitialised()
    --print(obj:invoke(hashCode))
end)

if not ok then
    print(`\x1b[31m{jvm4l.display_exception(err :: any)}\x1b[0m`)
end
