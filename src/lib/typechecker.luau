local t = require("./t")

local typechecker = {}

local integral_ranges = {
    boolean = { min = 0, max = 1 },
    byte = { min = -128, max = 127 },
    short = { min = -32768, max = 32767 },
    char = { min = 0, max = 65535 },
    int = { min = -2147483648, max = 2147483647 },
}

local float_check = buffer.create(4)

local function check_integer(value: number, min: number, max: number)
    if value % 1 ~= 0 then
        return false
    end

    if value >= min and value <= max then
        return true
    end

    return false
end

function typechecker.check_value(jvm: t.Jvm, value: t.JvmValue, target: t.JvmType): boolean
    if target == "boolean" then
        return type(value) == "boolean"
        -- TODO!
    elseif type(target) == "table" then
        if type(value) ~= "table" then
            return false
        end

        return value:instance_of(target)
    end

    return false
end

function typechecker.check_method(jvm: t.Jvm, args: { t.JvmValue }, target: { t.JvmType }): boolean
    if #args ~= #target then
        return false
    end

    for i = 1, #target do
        if not typechecker.check_value(jvm, args[i], target[i]) then
            return false
        end
    end

    return true
end

return typechecker
