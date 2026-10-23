local t = require("./t")
local Lazy = {}
Lazy.__index = Lazy

function Lazy.new<T>(init: () -> T): t.Lazy<T>
    return setmetatable({
        _init = init,
        _ready = false,
        _value = nil,
    }, Lazy)
end

function Lazy.get<T>(self: t.Lazy<T>): T
    if self._ready then
        return self._value :: T
    end

    self._value = self._init()
    self._ready = true
    return self._value :: T
end

return Lazy
