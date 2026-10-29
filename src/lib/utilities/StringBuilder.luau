local StringBuilder = {}
export type StringBuilder = setmetatable<{
    _buf: { string },
}, typeof(StringBuilder)>

StringBuilder.__index = StringBuilder

function StringBuilder.new(): StringBuilder
    return setmetatable({
        _buf = {},
    }, StringBuilder)
end

function StringBuilder.write(self: StringBuilder, str: string, ...: any)
    table.insert(self._buf, string.format(str, ...))
end

function StringBuilder.writeln(self: StringBuilder, str: string, ...: any)
    self:write(str, ...)
    table.insert(self._buf, "\n")
end

function StringBuilder.build(self: StringBuilder): string
    return table.concat(self._buf)
end

return StringBuilder
