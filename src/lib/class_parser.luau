local t = require("./t")
local class_parser = {}

local scratch = buffer.create(8)

function class_parser.parse(b: buffer): t.Classfile
    local cursor = 0

    local function read_u8(): number
        local value = buffer.readu8(b, cursor)
        cursor += 1
        return value
    end

    local function read_u16(): number
        local value = buffer.readu16(b, cursor)
        cursor += 2
        return bit32.rshift(bit32.byteswap(value), 16)
    end

    local function read_u32(): number
        local value = buffer.readu32(b, cursor)
        cursor += 4
        return bit32.byteswap(value)
    end

    local function read_f32(): number
        for i = 0, 3 do
            buffer.writeu8(scratch, i, buffer.readu8(b, cursor + (3 - i)))
        end
        cursor += 4
        return buffer.readf32(scratch, 0)
    end

    local function read_f64(): number
        for i = 0, 7 do
            buffer.writeu8(scratch, i, buffer.readu8(b, cursor + (7 - i)))
        end
        cursor += 8
        return buffer.readf64(scratch, 0)
    end

    local function read_integer(): integer
        for i = 0, 7 do
            buffer.writeu8(scratch, i, buffer.readu8(b, cursor + (7 - i)))
        end
        cursor += 8
        return buffer.readinteger(scratch, 0)
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

    local function read_attribute_info(): t.CfAttributeInfo
        local name_index = read_u16()
        local attribute_length = read_u32()
        local info = read_buffer(attribute_length)

        return {
            name_index = name_index,
            data = info,
        }
    end

    local function read_field_info(): t.CfFieldInfo
        local access_flags = read_u16()
        local name_index = read_u16()
        local descriptor_index = read_u16()

        local attributes_count = read_u16()
        local attributes = table.create(attributes_count) :: { t.CfAttributeInfo }
        for i = 1, attributes_count do
            attributes[i] = read_attribute_info()
        end

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

        local attributes_count = read_u16()
        local attributes = table.create(attributes_count) :: { t.CfAttributeInfo }
        for i = 1, attributes_count do
            attributes[i] = read_attribute_info()
        end

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

        local attributes_count = read_u16()
        local attributes = table.create(attributes_count) :: { t.CfAttributeInfo }
        for i = 1, attributes_count do
            attributes[i] = read_attribute_info()
        end

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

return class_parser
