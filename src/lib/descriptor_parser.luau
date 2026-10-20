local t = require("./t")
local descriptor_parser = {}

function descriptor_parser.arg_count(descriptor: string): number
    local count = 0
    local len = #descriptor
    local i = 1

    while i <= len and string.sub(descriptor, i, i) ~= "(" do
        i += 1
    end
    i += 1

    while i <= len do
        local char = string.sub(descriptor, i, i)
        if char == ")" then
            break
        end

        if char == "[" then
            i += 1
            continue
        elseif char == "L" then
            i += 1
            while i <= len and string.sub(descriptor, i, i) ~= ";" do
                i += 1
            end
            count += 1
            i += 1
        elseif char == "J" or char == "D" then
            count += 2
            i += 1
        else
            count += 1
            i += 1
        end
    end

    return count
end

function descriptor_parser.ret_count(descriptor: string): number
    return if descriptor:sub(#descriptor, #descriptor) == "V" then 0 else 1
end

function descriptor_parser.resolve_descriptor(
    jvm: t.Jvm,
    descriptor: string,
    loader: t.JvmClassLoader,
    i: number?
): (t.JvmType, number)
    local i = i or 1

    local first_char = string.sub(descriptor, i, i)
    if first_char == "Z" then
        return "boolean", i + 1
    elseif first_char == "B" then
        return "byte", i + 1
    elseif first_char == "C" then
        return "char", i + 1
    elseif first_char == "S" then
        return "short", i + 1
    elseif first_char == "I" then
        return "int", i + 1
    elseif first_char == "J" then
        return "long", i + 1
    elseif first_char == "F" then
        return "float", i + 1
    elseif first_char == "D" then
        return "double", i + 1
    elseif first_char == "L" then
        local start = i

        while true do
            i += 1
            if i > #descriptor then
                error("invalid")
            end

            if string.sub(descriptor, i, i) == ";" then
                break
            end
        end

        local name = string.sub(descriptor, start + 1, i - 1)
        return jvm:resolve_class(name), i + 1
    elseif first_char == "[" then
        local _, new_i = descriptor_parser.resolve_descriptor(jvm, descriptor, loader, i + 1)
        return jvm:resolve_class(string.sub(descriptor, i + 1, new_i - 1), loader), new_i
    else
        error("invalid descriptor")
    end
end

function descriptor_parser.resolve_method_descriptor(
    jvm: t.Jvm,
    descriptor: string,
    loader: t.JvmClassLoader
): t.JvmMethodType
    assert(string.sub(descriptor, 1, 1) == "(", "invalid descriptor")

    local arguments = {}

    local i = 2

    while true do
        if string.sub(descriptor, i, i) == ")" then
            i += 1
            break
        end

        local ty, new_i = descriptor_parser.resolve_descriptor(jvm, descriptor, loader, i)
        table.insert(arguments, ty)
        i = new_i
    end

    local returns
    if string.sub(descriptor, i, i) == "V" then
        returns = "void"
    else
        returns = descriptor_parser.resolve_descriptor(jvm, descriptor, loader, i)
    end

    return {
        arguments = arguments,
        returns = returns,
    }
end

function descriptor_parser.type_to_descriptor(ty: t.JvmType): string
    if ty == "boolean" then
        return "Z"
    elseif ty == "byte" then
        return "B"
    elseif ty == "char" then
        return "C"
    elseif ty == "short" then
        return "S"
    elseif ty == "int" then
        return "I"
    elseif ty == "long" then
        return "J"
    elseif ty == "float" then
        return "F"
    elseif ty == "double" then
        return "D"
    else
        if string.sub(ty.name, 1, 1) == "[" then
            return ty.name
        end

        return `L{ty.name};`
    end
end

return descriptor_parser
