local jvm4l = require("./src/lib")

local function link_native(class_name: string, method_name: string): jvm4l.NativeMethod?
    return nil
end

local vm = jvm4l.Jvm.new({
    link_native = link_native,
})

local Object = vm:resolve_class("java/lang/Object")
local array = vm:create_array(Object, {
    Object:new_uninitialised(),
    Object:new_uninitialised(),
    Object:new_uninitialised(),
    Object:new_uninitialised(),
    Object:new_uninitialised(),
})
print(array:get_array_elements())
print(vm:resolve_class("jvm4l/Luau"))

local Test = vm:resolve_class("jvm4l/Test")
local test_ref = vm:get_method_ref(Test, "main", "()V")
local test_method = Test:resolve_method(test_ref)
print(test_method)
