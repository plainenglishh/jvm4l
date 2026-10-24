print("-----")
local jvm4l = require("./src/lib")

local function link_native(class_name: string, method_name: string): jvm4l.NativeMethod?
    if class_name == "jvm4l/Test" and method_name == "print_int:(I)V" then
        return function(jvm: jvm4l.Jvm, value)
            print(value)
            return nil
        end
    elseif class_name == "jvm4l/Test" and method_name == "error:()V" then
        return function(jvm: jvm4l.Jvm)
            error("error was called!")
        end
    elseif class_name == "jvm4l/Test" and method_name == "calls_error_wrapper:()V" then
        return function(jvm: jvm4l.Jvm)
            local Test = jvm:resolve_class("jvm4l/Test")
            local error_wrapper = jvm:resolve_method(Test, "error_wrapper", "()V")
            jvm:invoke(error_wrapper, {})
            return nil
        end
    end

    return nil
end

local epoch = os.clock()
local vm = jvm4l.Jvm.new({
    link_native = link_native,
    trace = function(message: string)
        local time = os.clock() - epoch
        print(`\x1b[2m[jvm4l @ {math.round(time * 100000) / 100000}] {message}\x1b[0m`)
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
    vm:invoke(test_ref, {})
end)
if not ok then
    print(`\x1b[31m{err}\x1b[m`)
end
