local t = require("./t")

local native_methods: { [string]: { [string]: t.NativeMethod } } = {}

native_methods["jvm4l/Luau"] = {
    ["print(Ljava/lang/Object;)V"] = function(jvm: t.Jvm, o: t.JvmObject)
        print(o)
    end,
}

native_methods["jvm4l/Luau"] = {
    ["error(Ljava/lang/Object;I)V"] = function(jvm: t.Jvm, o: t.JvmObject, level: t.JvmInt)
        error(o, level)
    end,
}

return native_methods
