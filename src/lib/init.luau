--!optimize 2

local t = require("@self/t")

--EXPORT_BEGIN
export type Lazy<T> = t.Lazy<T>
export type ConstantValueType = t.ConstantValueType
export type ConstantValue = t.ConstantValue
export type ConstantPool = t.ConstantPool
export type JvmInt = t.JvmInt
export type JvmFloat = t.JvmFloat
export type JvmLong = t.JvmLong
export type JvmDouble = t.JvmDouble
export type JvmIntegral = t.JvmIntegral
export type JvmReal = t.JvmReal
export type JvmPrimitive = t.JvmPrimitive
export type JvmObjectRef = t.JvmObjectRef
export type JvmValue = t.JvmValue
export type IntoJvmValue = t.IntoJvmValue
export type JvmType = t.JvmType
export type JvmMethodType = t.JvmMethodType
export type Jvm = t.Jvm
export type IntoJvmSettings = t.IntoJvmSettings
export type LinkNativeCallback = t.LinkNativeCallback
export type InterruptCallback = t.InterruptCallback
export type TraceCallback = t.TraceCallback
export type JvmClassLoader = t.JvmClassLoader
export type GarbageCollector = t.GarbageCollector
export type GcFinalise = t.GcFinalise
export type Thread = t.Thread
export type ThreadState = t.ThreadState
export type StackFrame = t.StackFrame
export type Invocation = t.Invocation
export type Monitor = t.Monitor
export type JvmClass = t.JvmClass
export type JvmClassState = t.JvmClassState
export type JvmObject = t.JvmObject
export type FieldInfo = t.FieldInfo
export type FieldHandle = t.FieldHandle
export type MethodInfo = t.MethodInfo
export type MethodHandle = t.MethodHandle
export type NativeMethod = t.NativeMethod
export type MethodCode = t.MethodCode
export type MethodCodeLuau = t.MethodCodeLuau
export type MethodCodeJava = t.MethodCodeJava
export type ExceptionHandler = t.ExceptionHandler
export type MethodCodeAbstract = t.MethodCodeAbstract
export type Classfile = t.Classfile
export type CfCpInfo_Class = t.CfCpInfo_Class
export type CfCpInfo_Fieldref = t.CfCpInfo_Fieldref
export type CfCpInfo_Methodref = t.CfCpInfo_Methodref
export type CfCpInfo_InterfaceMethodref = t.CfCpInfo_InterfaceMethodref
export type CfCpInfo_String = t.CfCpInfo_String
export type CfCpInfo_Integer = t.CfCpInfo_Integer
export type CfCpInfo_Float = t.CfCpInfo_Float
export type CfCpInfo_Long = t.CfCpInfo_Long
export type CfCpInfo_Double = t.CfCpInfo_Double
export type CfCpInfo_NameAndType = t.CfCpInfo_NameAndType
export type CfCpInfo_Utf8 = t.CfCpInfo_Utf8
export type CfCpInfo_MethodHandle = t.CfCpInfo_MethodHandle
export type CfCpInfo_MethodType = t.CfCpInfo_MethodType
export type CfCpInfo_InvokeDynamic = t.CfCpInfo_InvokeDynamic
export type CfCpInfo = t.CfCpInfo
export type CfFieldInfo = t.CfFieldInfo
export type CfMethodInfo = t.CfMethodInfo
export type CfAttributeInfo = t.CfAttributeInfo
export type CfCodeAttribute = t.CfCodeAttribute
--EXPORT_END

--[=[
    A Java Virtual Machine written in pure-Luau.
]=]
local jvm4l = {}

jvm4l.Jvm = require("@self/entities/Jvm")

function jvm4l.display_exception(exception: t.JvmObject): string
    if type(exception) == "string" then
        return `uncoerced exception: {exception}`
    end

    local jvm = exception.jvm
    local Throwable = jvm:resolve_class("java/lang/Throwable")
    if not exception:instance_of(Throwable) then
        return `non-throwable exception: {exception:__tostring()}`
    end

    local message_ref = jvm:resolve_field(Throwable, "message", "Ljava/lang/String;")
    local message = exception:get_field(message_ref) :: t.JvmObjectRef
    local message_str = ""
    if message then
        message_str = `: {message:inner_string()}`
    end

    local stack_trace = ""
    if exception._magic then
        assert(exception._magic.kind == "throwable")
        local builder = {}

        for _, frame in exception._magic.stack do
            local where: string
            if frame.method.native then
                where = "Native Method"
            elseif frame.class.source_file then
                where = frame.class.source_file

                if frame.code.kind == "java" and frame.code.line_numbers then
                    local line = -1
                    local best_start_pc = -1

                    for i = 1, #frame.code.line_numbers do
                        local entry = frame.code.line_numbers[i]
                        if frame.start_pc >= entry.start_pc and entry.start_pc > best_start_pc then
                            line = entry.line
                            best_start_pc = entry.start_pc
                        end
                    end
                    where ..= `:{line}`
                end
            else
                where = "Unknown Source"
            end

            table.insert(builder, 1, `    at {frame.class.fqcn}.{frame.method.name}({where})`)
        end

        stack_trace = "\n" .. table.concat(builder, "\n")
    end

    local cause = exception:get_field(jvm:resolve_field(Throwable, "cause", "Ljava/lang/Throwable;"))
    local cause_str = ""
    if cause then
        cause_str = "\nCaused by: " .. jvm4l.display_exception(cause :: t.JvmObject)
    end

    return `{exception.class.fqcn}{message_str}{stack_trace}{cause_str}`
end

return jvm4l
