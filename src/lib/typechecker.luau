local descriptor_parser = require("./descriptor_parser")
local t = require("./t")

local typechecker = {}

local function check_integer(value: any, min: number, max: number): boolean
    if type(value) ~= "number" then
        return false
    end

    if value % 1 ~= 0 then
        return false
    end

    if value >= min and value <= max then
        return true
    end

    return false
end

function typechecker.check_value(value: t.JvmValue, target: t.JvmType): boolean
    if target == "boolean" then
        return check_integer(value, 0, 1)
    elseif target == "byte" then
        return check_integer(value, -128, 127)
    elseif target == "short" then
        return check_integer(value, -32768, 32767)
    elseif target == "char" then
        return check_integer(value, 0, 65535)
    elseif target == "int" then
        return check_integer(value, -2147483648, 2147483647)
    elseif target == "float" then
        if type(value) ~= "number" then
            return false
        end

        local v = vector.create(value, 0)
        return v.x == value
    elseif target == "double" then
        return type(value) == "number"
    elseif target == "long" then
        return typeof(value) == "integer"
    elseif type(target) == "table" then
        if value == nil then
            return true
        end

        if type(value) ~= "table" then
            return false
        end

        return value:instance_of(target)
    end

    return false
end

--[=[
    Checks if `value` satisfies the given `FieldInfo`.

    Will resolve types.
]=]
function typechecker.check_field(jvm: t.Jvm, value: t.JvmValue, class: t.JvmClass, target: t.FieldInfo)
    local field_type = descriptor_parser.resolve_descriptor(jvm, target.descriptor, class.loader)
    return typechecker.check_value(value, field_type)
end

--[=[
    Checks if `values` satisfies the given `MethodInfo`.

    Will resolve types.
]=]
function typechecker.check_method(jvm: t.Jvm, values: { t.JvmValue }, class: t.JvmClass, target: t.MethodInfo): boolean
    local method_type = descriptor_parser.resolve_method_descriptor(jvm, target.descriptor, class.loader)

    if #values ~= #method_type.arguments then
        return false
    end

    for i = 1, #method_type.arguments do
        if not typechecker.check_value(values[i], method_type.arguments[i]) then
            return false
        end
    end

    return true
end

return typechecker
