local test = require("@std/test")
local jvm4l = require("../src/lib")

local vm = jvm4l.Jvm.new({
    link_native = function()
        return nil
    end,
})

test.case("object allocation", function(asserts)
    local Object = vm:load_class("java/lang/Object")
    local o = Object:new()
    asserts.neq(o, nil)
    asserts.eq(o.class.name, "java/lang/Object")
end)
