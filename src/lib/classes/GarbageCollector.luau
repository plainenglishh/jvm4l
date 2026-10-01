local t = require("../t")

local GarbageCollector = {}
GarbageCollector.__index = GarbageCollector

function GarbageCollector._new(jvm: t.Jvm): t.GarbageCollector
    return setmetatable({
        jvm = jvm,
        _objects = {},
    }, GarbageCollector)
end

function GarbageCollector._track(self: t.GarbageCollector, object: t.JvmObject)
    if not self._objects[object] then
        self._objects[object] = true
    end
end

function GarbageCollector._step(_self: t.GarbageCollector)
    -- do nothing for now, keep everything for testing
end

return GarbageCollector
