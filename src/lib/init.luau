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
export type JvmType = t.JvmType
export type Jvm = t.Jvm
export type LinkNativeCallback = t.LinkNativeCallback
export type JvmClassLoader = t.JvmClassLoader
export type GarbageCollector = t.GarbageCollector
export type GcFinalise = t.GcFinalise
export type JvmThread = t.JvmThread
export type ThreadState = t.ThreadState
export type StackFrame = t.StackFrame
export type Monitor = t.Monitor
export type JvmClass = t.JvmClass
export type JvmClassState = t.JvmClassState
export type JvmObject = t.JvmObject
export type FieldInfo = t.FieldInfo
export type FieldRef = t.FieldRef
export type MethodInfo = t.MethodInfo
export type MethodRef = t.MethodRef
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

return jvm4l
