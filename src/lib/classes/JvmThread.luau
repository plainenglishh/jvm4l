local t = require("../t")
local JvmThread = {}
JvmThread.__type = "JvmThread"
JvmThread.__index = JvmThread

function JvmThread.__tostring(_self: t.JvmThread): string
    return "<JvmThread>"
end

function JvmThread.__display(self: t.JvmThread): string
    return tostring(self)
end

function JvmThread._allocate(jvm: t.Jvm): t.JvmThread
    local self: t.JvmThread = setmetatable({
        jvm = jvm,
        _stack = {},
        _state = "new",
        _daemon = false,
        _mirror = (nil :: any) :: t.JvmObject,
    }, JvmThread)

    local mirror = self.jvm._classes.bootstrap["java/lang/Thread"]:new_uninitialised({ kind = "thread", value = self })
    self._mirror = mirror

    return self
end

table.freeze(JvmThread)

return JvmThread
