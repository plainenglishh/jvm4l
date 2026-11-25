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

function typechecker.check_field_type(value: t.JvmValue, target: t.JvmFieldType): boolean
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
        if type(value) ~= "table" then
            return false
        end

        if value.null then
            return true
        end

        return value:instance_of(target)
    end

    return false
end

function typechecker.check_return_type(value: t.JvmValue, target: t.JvmReturnType): boolean
    if target == "void" then
        return type(value) == "table" and value.null
    else
        return typechecker.check_field_type(value, target)
    end
end

--[=[
    Checks if `value` satisfies the given `FieldInfo`.

    Will resolve types.
]=]
function typechecker.check_field(jvm: t.Jvm, value: t.JvmValue, class: t.JvmClass, target: t.Field): boolean
    return typechecker.check_field_type(value, target.type:get())
end

--[=[
    Checks if `values` satisfies the given `MethodInfo`.

    Will resolve types.
]=]
function typechecker.check_method_args(jvm: t.Jvm, values: t.Arguments, class: t.JvmClass, target: t.Method): boolean
    local method_type = target.type:get()
    local static = target.static
    local arg_offset = if static then 0 else 1
    local expected_args = #method_type.arguments + arg_offset

    if values.n ~= expected_args then
        return false
    end

    if not static then
        local this = values[1] :: t.JvmObject
        if not this or this.null then
            return false
        end

        if not typechecker.check_field_type(this, class) then
            return false
        end
    end

    for i = 1, #method_type.arguments do
        if not typechecker.check_field_type(values[i + arg_offset], method_type.arguments[i]) then
            return false
        end
    end

    return true
end

return typechecker
