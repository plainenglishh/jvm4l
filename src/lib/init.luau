--!optimize 2

local t = require("@self/t")

--EXPORT_BEGIN
export type JvmInt = t.JvmInt
export type JvmFloat = t.JvmFloat
export type JvmLong = t.JvmLong
export type JvmDouble = t.JvmDouble
export type JvmIntegral = t.JvmIntegral
export type JvmReal = t.JvmReal
export type JvmPrimitive = t.JvmPrimitive
export type JvmObjectRef = t.JvmObjectRef
export type JvmValue = t.JvmValue
export type JvmBooleanType = t.JvmBooleanType
export type JvmByteType = t.JvmByteType
export type JvmShortType = t.JvmShortType
export type JvmCharType = t.JvmCharType
export type JvmIntType = t.JvmIntType
export type JvmLongType = t.JvmLongType
export type JvmIntegralType = t.JvmIntegralType
export type JvmFloatType = t.JvmFloatType
export type JvmDoubleType = t.JvmDoubleType
export type JvmRealType = t.JvmRealType
export type JvmVoidType = t.JvmVoidType
export type JvmPrimitiveType = t.JvmPrimitiveType
export type JvmObjectType = t.JvmObjectType
export type JvmArrayType = t.JvmArrayType
export type JvmFieldType = t.JvmFieldType
export type JvmMethodType = t.JvmMethodType
export type Jvm = t.Jvm
export type LinkNativeCallback = t.LinkNativeCallback
export type JvmClassLoader = t.JvmClassLoader
export type IGarbageCollector = t.IGarbageCollector
export type GcFinalise = t.GcFinalise
export type JvmThread = t.JvmThread
export type ThreadState = t.ThreadState
export type StackFrame = t.StackFrame
export type Monitor = t.Monitor
export type JvmClass = t.JvmClass
export type JvmClassState = t.JvmClassState
export type JvmObject = t.JvmObject
export type FieldInfo = t.FieldInfo
export type MethodInfo = t.MethodInfo
export type NativeMethod = t.NativeMethod
export type MethodCode = t.MethodCode
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
--EXPORT_END

--[=[
    A Java Virtual Machine written in pure-Luau.
]=]
local jvm4l = {}

jvm4l.Jvm = require("@self/classes/Jvm")

function jvm4l.pretty_errors<A..., R...>(fn: (A...) -> R..., ...: A...): R...
    local r: { any } = { pcall(fn, ...) }
    local ok = table.remove(r, 1)
    if ok then
        return unpack(r)
    end

    local e = table.remove(r, 1)
    if type(e) ~= "table" or e.__type ~= "JvmObject" then
        error(tostring(e), 0)
    end

    local e: t.JvmObject = e
    local jvm = e.jvm
    local Throwable = jvm:resolve_class("java/lang/Throwable")
    local message_ref = jvm:get_field_ref(Throwable, "message", "Ljava/lang/String;")
    local message = e:get_field(message_ref) :: t.JvmObjectRef
    local message_str = (message and message:inner_string()) or "no message given"
    error(`{e.class.fqcn}: {message_str}`, 0)
end

return jvm4l
