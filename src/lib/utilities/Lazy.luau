--- A lazily loaded value.
export type Lazy<T> = setmetatable<{
    _init: () -> T,
    _ready: boolean,
    _value: T?,
}, {
    __index: getmetatable<Lazy<T>>,
    new: (init: () -> T) -> Lazy<T>,
    get: (self: Lazy<T>) -> T,
}>

local Lazy = {}
Lazy.__index = Lazy

function Lazy.new<T>(init: () -> T): Lazy<T>
    return setmetatable({
        _init = init,
        _ready = false,
        _value = nil,
    }, Lazy)
end

function Lazy.get<T>(self: Lazy<T>): T
    if self._ready then
        return self._value :: T
    end

    self._value = self._init()
    self._ready = true
    return self._value :: T
end

return Lazy
