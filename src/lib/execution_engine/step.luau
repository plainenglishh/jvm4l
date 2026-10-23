local class_parser = require("../class_parser")
local t = require("../t")
local frame = require("./frame")

local function invoke_inline(jvm: t.Jvm, class: t.JvmClass, method: t.MethodInfo, ...: t.JvmValue)
    if method.code.kind == "abstract" then
        jvm:throw_exception("java/lang/AbstractMethodError", method.descriptor)
        error("^")
    end

    local thread = jvm.current_thread
    local stack = thread.stack
    local this_frame = stack[#stack]
    if not this_frame or this_frame.code.kind == "native" then
        jvm:throw_exception(
            "java/lang/InternalError",
            "attempt to use invoke_inline in native context, use invoke_sync"
        )
        error("^")
    end

    frame.push_on(stack, class, method, nil, ...)
end

local function read_u16be(b: buffer, offset: number): number
    return bit32.rshift(bit32.byteswap(buffer.readu16(b, offset)), 16)
end

local function get_method_ref_from_k(jvm: t.Jvm, classfile: t.Classfile, idx: number): (t.JvmClass, t.MethodRef)
    local k = classfile.constant_pool
    local methodref = k[idx]
    if methodref.tag ~= "Methodref" then
        error("expected Methodref")
    end

    local classref = k[methodref.class_index]
    if classref.tag ~= "Class" then
        error("expected Class")
    end

    local name_and_type = k[methodref.name_and_type_index]
    if name_and_type.tag ~= "NameAndType" then
        error("expected NameAndType")
    end

    local class_name, name, descriptor =
        class_parser.class_name(classfile, classref),
        class_parser.string_value(classfile, name_and_type.name_index),
        class_parser.string_value(classfile, name_and_type.descriptor_index)

    local class = jvm:resolve_class(class_name)
    local method_ref = jvm:get_method_ref(class, name, descriptor)
    return class, method_ref
end

--[=[ 
    Execute a single VM step (a native call, or a single bytecode instruction)

    Throws either an exception, or a generic luau error, to be caught by the 
    execution driver.
]=]
@native
local function step(jvm: t.Jvm)
    local thread, f = frame.current(jvm)
    if not f then
        error("expected frame") -- shouldve been caught by scheduler.
    end

    local method = f.method

    if f.code.kind == "luau" then
        local value = f.code.closure(jvm, unpack(f.args))
        return frame.return_from_current_frame(thread, method.ret_count, value)
    end

    local code = f.code.code
    local stack = f.stack
    local locals = f.locals
    local classfile = f.class._classfile or error("expected classfile")
    local k = classfile.constant_pool

    local start_pc = f.pc
    f.start_pc = start_pc
    local op = buffer.readu8(code, start_pc)
    f.pc += 1

    if op >= 0x02 and op <= 0x8 then
        table.insert(stack, op - 0x03)
    elseif op >= 0x4B and op <= 0x4E then
        local idx = op - 0x4B
        local ref = table.remove(stack)
        locals[idx] = ref
    elseif op == 0xB8 then
        local idx = read_u16be(code, f.pc)
        f.pc += 2

        local class, method_ref = get_method_ref_from_k(jvm, classfile, idx)
        local method_info = class:resolve_method(method_ref) or error("unable to resolve method")
        local args = { table.remove(stack) } -- one arg for now

        invoke_inline(jvm, class, method_info, unpack(args))
    elseif op == 0xAC then -- ireturn
        frame.return_from_current_frame(thread, 1, table.remove(stack))
    elseif op == 0xB1 then -- return
        frame.return_from_current_frame(thread, 0, nil)
    elseif op == 0xA7 then -- goto
        local raw_offset = read_u16be(code, f.pc)
        f.pc += 2

        local offset = bit32.arshift(bit32.lshift(raw_offset, 16), 16)
        if offset >= 0x80000000 then
            offset = offset - 4294967296
        end

        f.pc = start_pc + offset
    else
        jvm:throw_exception("java/lang/InternalError", `invalid opcode {op}`)
    end
end

return step
