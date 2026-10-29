local class_parser = require("./class_parser")
local t = require("./t")

local ConstantPool = {}
ConstantPool.__index = ConstantPool

function ConstantPool.new(class: t.JvmClass): t.ConstantPool
    local classfile = assert(class._classfile, `class has no class file`)
    local self: t.ConstantPool = setmetatable({
        _jvm = class.jvm,
        _class = class,
        _classfile = classfile,
        _resolved = {},
        _types = {},
    }, ConstantPool)

    for i, cp_info in classfile.constant_pool do
        local ktype: t.ConstantValueType
        if cp_info.tag == "Class" then
            ktype = "class"
        elseif cp_info.tag == "Fieldref" then
            ktype = "field"
        elseif cp_info.tag == "Methodref" then
            ktype = "method"
        elseif cp_info.tag == "InterfaceMethodref" then
            ktype = "method"
        elseif cp_info.tag == "String" then
            ktype = "string"
        elseif cp_info.tag == "Integer" then
            ktype = "int"
        elseif cp_info.tag == "Float" then
            ktype = "float"
        elseif cp_info.tag == "Double" then
            ktype = "double"
        elseif cp_info.tag == "Long" then
            ktype = "long"
        end
        self._types[i] = ktype
    end

    return table.freeze(self) :: t.ConstantPool
end

function ConstantPool._resolve(self: t.ConstantPool, idx: number): t.ConstantValue
    local resolved = self._resolved[idx]
    if resolved then
        return resolved
    end

    local classfile = self._classfile
    local cp_info = classfile.constant_pool[idx]
    local value: t.ConstantValue

    if cp_info.tag == "Class" then
        local class_name = class_parser.utf8_value(classfile, cp_info.name_index)
        value = { type = "class" :: "class", value = self._jvm:load_class(class_name, self._class.loader) }
    elseif cp_info.tag == "Fieldref" then
        local name_and_type = classfile.constant_pool[cp_info.name_and_type_index]
        assert(name_and_type.tag == "NameAndType")
        local name, descriptor =
            class_parser.utf8_value(classfile, name_and_type.name_index),
            class_parser.utf8_value(classfile, name_and_type.descriptor_index)
        local class = self:get(cp_info.class_index, "class")
        value = { type = "field" :: "field", value = class:resolve_field(name, descriptor) }
    elseif cp_info.tag == "Methodref" then
        local name_and_type = classfile.constant_pool[cp_info.name_and_type_index]
        assert(name_and_type.tag == "NameAndType")
        local name, descriptor =
            class_parser.utf8_value(classfile, name_and_type.name_index),
            class_parser.utf8_value(classfile, name_and_type.descriptor_index)
        local class = self:get(cp_info.class_index, "class")
        value = { type = "method" :: "method", value = class:resolve_method(name, descriptor) }
    elseif cp_info.tag == "InterfaceMethodref" then
        local name_and_type = classfile.constant_pool[cp_info.name_and_type_index]
        assert(name_and_type.tag == "NameAndType")
        local name, descriptor =
            class_parser.utf8_value(classfile, name_and_type.name_index),
            class_parser.utf8_value(classfile, name_and_type.descriptor_index)
        local class = self:get(cp_info.class_index, "class")
        value = {
            type = "interface_method" :: "interface_method",
            value = class:resolve_method(name, descriptor),
        }
    elseif cp_info.tag == "String" then
        local str = self._jvm:create_string(class_parser.utf8_value(classfile, cp_info.string_index))
        value = { type = "string" :: "string", value = str }
    elseif cp_info.tag == "Integer" then
        value = { type = "int" :: "int", value = cp_info.value }
    elseif cp_info.tag == "Float" then
        value = { type = "float" :: "float", value = cp_info.value }
    elseif cp_info.tag == "Double" then
        value = { type = "double" :: "double", value = cp_info.value }
    elseif cp_info.tag == "Long" then
        value = { type = "long" :: "long", value = cp_info.value }
    else
        self._jvm:_internal_error(`cant resolve constant type {cp_info.tag}`)
    end

    local value = value :: t.ConstantValue
    self._resolved[idx] = value
    return value
end

function ConstantPool.is(self: t.ConstantPool, idx: number, type: t.ConstantValueType): boolean
    return self._types[idx] == type
end

function ConstantPool.get(self: t.ConstantPool, idx: number, type: t.ConstantValueType): any
    if not self:is(idx, type) then
        error(`expected constant #{idx} to be {type}, got {self._types[idx]}`, 2)
    end

    local value = self:_resolve(idx)
    return value.value
end

return table.freeze(ConstantPool)
