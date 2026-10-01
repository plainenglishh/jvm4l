local jvm4l = require("./src/lib")

local function link_native(class_name: string, method_name: string): jvm4l.NativeMethod?
    return nil
end

local vm = jvm4l.Jvm.new(link_native)
local Object = vm:resolve_class("java/lang/Object")
local array = vm:create_array(Object, 5)

array:set_array_element(0, Object:new_uninitialised())
array:set_array_element(1, Object:new_uninitialised())
array:set_array_element(2, Object:new_uninitialised())
array:set_array_element(3, Object:new_uninitialised())
array:set_array_element(4, Object:new_uninitialised())
print(array:get_array_elements())
