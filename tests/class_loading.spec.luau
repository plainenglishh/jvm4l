local test = require("@std/test")
local jvm4l = require("../src/lib")

test.suite("class loading", function(suite)
    suite:case("classes load", function(asserts)
        local jvm = jvm4l.Jvm.new({
            link_native = function()
                return nil
            end,
        })

        local a = jvm:load_class("java/lang/String")
        local b = jvm:load_class("java/lang/String")
        asserts.eq(a, b)
    end)
end)
