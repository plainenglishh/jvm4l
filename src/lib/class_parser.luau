--!native

local t = require("./t")
local class_parser = {}

local function read_u16be(b: buffer, offset: number): number
    return bit32.rshift(bit32.byteswap(buffer.readu16(b, offset)), 16)
end

local function read_u32be(b: buffer, offset: number): number
    return bit32.byteswap(buffer.readu32(b, offset))
end

local scratch = buffer.create(8)

local function read_f32be(b: buffer, offset: number): number
    for i = 0, 3 do
        buffer.writeu8(scratch, i, buffer.readu8(b, offset + (3 - i)))
    end
    return buffer.readf32(scratch, 0)
end

local function read_f64be(b: buffer, offset: number): number
    for i = 0, 7 do
        buffer.writeu8(scratch, i, buffer.readu8(b, offset + (7 - i)))
    end
    return buffer.readf64(scratch, 0)
end

local function read_integerbe(b: buffer, offset: number): integer
    for i = 0, 7 do
        buffer.writeu8(scratch, i, buffer.readu8(b, offset + (7 - i)))
    end
    return buffer.readinteger(scratch, 0)
end

local function read_attribute_infos(b: buffer, offset: number): ({ t.CfAttributeInfo }, number)
    local attribute_count = read_u16be(b, offset)
    offset += 2
    local attributes = {}
    for i = 1, attribute_count do
        local name_index = read_u16be(b, offset)
        local attribute_length = read_u32be(b, offset + 2)

        local data = buffer.create(attribute_length)
        buffer.copy(data, 0, b, offset + 6, attribute_length)

        offset += 6 + attribute_length

        table.insert(attributes, {
            name_index = name_index,
            data = data,
        })
    end

    return attributes, offset
end

function class_parser.parse(b: buffer): t.Classfile
    local cursor = 0

    local function read_u8(): number
        local value = buffer.readu8(b, cursor)
        cursor += 1
        return value
    end

    local function read_u16(): number
        local value = read_u16be(b, cursor)
        cursor += 2
        return value
    end

    local function read_u32(): number
        local value = read_u32be(b, cursor)
        cursor += 4
        return value
    end

    local function read_f32(): number
        local value = read_f32be(b, cursor)
        cursor += 4
        return value
    end

    local function read_f64(): number
        local value = read_f64be(b, cursor)
        cursor += 8
        return value
    end

    local function read_integer(): integer
        local value = read_integerbe(b, cursor)
        cursor += 8
        return value
    end

    local function read_string(length: number): string
        local value = buffer.readstring(b, cursor, length)
        cursor += length
        return value
    end

    local function read_buffer(length: number): buffer
        local value = buffer.create(length)
        buffer.copy(value, 0, b, cursor, length)
        cursor += length
        return value
    end

    local function read_cp_info(): t.CfCpInfo
        local tag = read_u8()

        if tag == 7 then
            local name_index = read_u16()
            return {
                tag = "Class",
                name_index = name_index,
            }
        elseif tag == 9 or tag == 10 or tag == 11 then
            local tag_name = if tag == 9 then "Fieldref" elseif tag == 10 then "Methodref" else "InterfaceMethodref"

            local class_index = read_u16()
            local name_and_type_index = read_u16()

            return {
                tag = tag_name :: "Fieldref",
                class_index = class_index,
                name_and_type_index = name_and_type_index,
            }
        elseif tag == 8 then
            local string_index = read_u16()
            return {
                tag = "String",
                string_index = string_index,
            }
        elseif tag == 3 then
            local value = read_u32()
            return {
                tag = "Integer",
                value = value,
            }
        elseif tag == 4 then
            local value = read_f32()
            return {
                tag = "Float",
                value = value,
            }
        elseif tag == 5 then
            local value = read_integer()
            return {
                tag = "Long",
                value = value,
            }
        elseif tag == 6 then
            local value = read_f64()
            return {
                tag = "Double",
                value = value,
            }
        elseif tag == 12 then
            local name_index = read_u16()
            local descriptor_index = read_u16()
            return {
                tag = "NameAndType",
                name_index = name_index,
                descriptor_index = descriptor_index,
            }
        elseif tag == 1 then
            local length = read_u16()
            local value = read_string(length)
            return {
                tag = "Utf8",
                value = value,
            }
        elseif tag == 15 then
            local reference_kind = read_u8()
            local reference_index = read_u16()
            return {
                tag = "MethodHandle",
                reference_kind = reference_kind,
                reference_index = reference_index,
            }
        elseif tag == 16 then
            local descriptor_index = read_u16()
            return {
                tag = "MethodType",
                descriptor_index = descriptor_index,
            }
        elseif tag == 18 then
            local bootstrap_method_attr_index = read_u16()
            local name_and_type_index = read_u16()
            return {
                tag = "InvokeDynamic",
                bootstrap_method_attr_index = bootstrap_method_attr_index,
                name_and_type_index = name_and_type_index,
            }
        else
            print(tag, cursor)
            error("")
        end
    end

    local function read_field_info(): t.CfFieldInfo
        local access_flags = read_u16()
        local name_index = read_u16()
        local descriptor_index = read_u16()

        local attributes, new_cursor = read_attribute_infos(b, cursor)
        cursor = new_cursor

        return {
            access_flags = access_flags,
            name_index = name_index,
            descriptor_index = descriptor_index,
            attributes = attributes,
        }
    end

    local function read_method_info(): t.CfMethodInfo
        local access_flags = read_u16()
        local name_index = read_u16()
        local descriptor_index = read_u16()

        local attributes, new_cursor = read_attribute_infos(b, cursor)
        cursor = new_cursor

        return {
            access_flags = access_flags,
            name_index = name_index,
            descriptor_index = descriptor_index,
            attributes = attributes,
        }
    end

    local function read_classfile(): t.Classfile
        assert(read_u32() == 0xCAFEBABE)
        local minor_version = read_u16()
        local major_version = read_u16()
        assert(major_version <= 52)

        local constant_pool_count = read_u16()
        local constant_pool = table.create(constant_pool_count) :: { t.CfCpInfo }
        local i = 1
        while i < constant_pool_count do
            local entry = read_cp_info()
            constant_pool[i] = entry

            if entry.tag == "Long" or entry.tag == "Double" then
                i += 2
            else
                i += 1
            end
        end

        local access_flags = read_u16()
        local this_class = read_u16()
        local super_class = read_u16()

        local interface_count = read_u16()
        local interfaces = table.create(interface_count, 0)
        for i = 1, interface_count do
            interfaces[i] = read_u16()
        end

        local fields_count = read_u16()
        local fields = table.create(fields_count) :: { t.CfFieldInfo }
        for i = 1, fields_count do
            fields[i] = read_field_info()
        end

        local methods_count = read_u16()
        local methods = table.create(methods_count) :: { t.CfMethodInfo }
        for i = 1, methods_count do
            methods[i] = read_method_info()
        end

        local attributes, new_cursor = read_attribute_infos(b, cursor)
        cursor = new_cursor

        return {
            minor_version = minor_version,
            major_version = major_version,
            constant_pool = constant_pool,
            access_flags = access_flags,
            this_class = this_class,
            super_class = super_class,
            interfaces = interfaces,
            fields = fields,
            methods = methods,
            attributes = attributes,
        }
    end

    return read_classfile()
end

function class_parser.class(classfile: t.Classfile, idx: number): t.CfCpInfo_Class
    local class = classfile.constant_pool[idx]
    assert(class.tag == "Class")
    return class
end

function class_parser.class_name(classfile: t.Classfile, class: t.CfCpInfo_Class): string
    local utf8 = classfile.constant_pool[class.name_index]
    assert(utf8.tag == "Utf8")
    return utf8.value
end

function class_parser.string_value(classfile: t.Classfile, idx: number): string
    local utf8 = classfile.constant_pool[idx]
    assert(utf8.tag == "Utf8")
    return utf8.value
end

function class_parser.get_utf8_idx(classfile: t.Classfile, str: string): number?
    for idx, k in classfile.constant_pool do
        if k.tag == "Utf8" and k.value == str then
            return idx
        end
    end

    return nil
end

function class_parser.get_attribute_info(
    classfile: t.Classfile,
    attributes: { t.CfAttributeInfo },
    name: string
): t.CfAttributeInfo?
    for _, attribute in attributes do
        if class_parser.string_value(classfile, attribute.name_index) == name then
            return attribute
        end
    end

    return nil
end

function class_parser.get_code_attribute(classfile: t.Classfile, method: t.CfMethodInfo): t.CfCodeAttribute?
    local attribute = class_parser.get_attribute_info(classfile, method.attributes, "Code")
    if not attribute then
        return nil
    end

    local b = attribute.data
    local cursor = 0

    local max_stack = read_u16be(b, cursor)
    cursor += 2
    local max_locals = read_u16be(b, cursor)
    cursor += 2
    local code_length = read_u32be(b, cursor)
    cursor += 4

    local code = buffer.create(code_length)
    buffer.copy(code, 0, b, cursor, code_length)
    cursor += code_length

    local exception_count = read_u16be(b, cursor)
    cursor += 2
    local exceptions = {}

    for i = 1, exception_count do
        local start_pc = read_u16be(b, cursor)
        cursor += 2
        local end_pc = read_u16be(b, cursor)
        cursor += 2
        local handler_pc = read_u16be(b, cursor)
        cursor += 2
        local catch_type = read_u16be(b, cursor)
        cursor += 2

        table.insert(exceptions, {
            start_pc = start_pc,
            end_pc = end_pc,
            handler_pc = handler_pc,
            catch_type = catch_type,
        })
    end

    local attributes = read_attribute_infos(b, cursor)

    return {
        max_stack = max_stack,
        max_locals = max_locals,
        code_length = code_length,
        code = code,
        exceptions = exceptions,
        attributes = attributes,
    }
end

return class_parser
