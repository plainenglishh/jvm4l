--[=[
	Private items are specified with the `_` prefix. Privacy is module-wide; 
	that is, a private item is accessible to any file within `src/lib`, not just
	the file it's defined in.

	Specialised library users, such as debugger implementations, should feel 
	feel free to read from private items, but must never set or construct 
	private items.
]=]

local t = {}

--------------------------------------------------------------------------------

--// Computational Types

--- A runtime 32-bit integer. Also represents booleans, bytes, shorts and chars.
export type JvmInt = number
--- A runtime 32-bit float.
export type JvmFloat = number
--- A runtime 64-bit integer.
export type JvmLong = integer
--- A runtime 64-bit float.
export type JvmDouble = number
--- Any runtime integral number.
export type JvmIntegral = JvmInt | JvmLong
--- Any runtime real number.
export type JvmReal = JvmFloat | JvmDouble
--- Any runtime primitive.
export type JvmPrimitive = JvmIntegral | JvmReal
--- Any runtime object reference, including null.
export type JvmObjectRef = JvmObject?
--- Any runtime value.
export type JvmValue = JvmPrimitive | JvmObjectRef

--// Actual Types

export type JvmType = "boolean" | "byte" | "short" | "char" | "int" | "long" | "float" | "double" | "void" | JvmClass

--------------------------------------------------------------------------------

--// Entities

--[=[
    A class representing a JVM instance.

    Handles thread scheduling and the registration of classes.
]=]
export type Jvm = setmetatable<
    {
        read _classes: { [JvmClassLoader]: { [string]: JvmClass } },
        read _threads: { JvmThread },
        read current_thread: JvmThread?,
        _gc: IGarbageCollector,
        _link_user_native: LinkNativeCallback,
        read _interned_strings: { [string]: JvmObject },
        read _interned_method_refs: { [JvmClass]: { [string]: { [string]: MethodRef } } },
        read _interned_field_refs: { [JvmClass]: { [string]: { [string]: FieldRef } } },
    },
    {
        __type: "Jvm",
        __index: getmetatable<Jvm>,
        __tostring: (self: Jvm) -> string,
        __display: (self: Jvm) -> string,

        new: (link_native: LinkNativeCallback) -> Jvm,
        get_loader: (self: Jvm) -> JvmClassLoader,
        get_class: (self: Jvm, name: string, initiating_loader: JvmClassLoader?) -> JvmClass?,
        resolve_class: (self: Jvm, name: string, initiating_loader: JvmClassLoader?) -> JvmClass,
        define_class: (self: Jvm, classfile: buffer, defining_loader: JvmClassLoader) -> JvmClass,

        get_method_ref: (self: Jvm, class: JvmClass, name: string, descriptor: string) -> MethodRef,
        get_field_ref: (self: Jvm, class: JvmClass, name: string, descriptor: string) -> FieldRef,

        create_string: (self: Jvm, value: string) -> JvmObject,
        create_array: (self: Jvm, element: JvmType, size: number) -> JvmObject,

        create_exception: (self: Jvm, name: string, message: string?, cause: JvmObject?) -> JvmObject,
        throw_exception: (self: Jvm, name: string, message: string?, cause: JvmObject?) -> never,

        --[=[
			Executes `main_path`.
		]=]
        run: (self: Jvm, main_path: string) -> (), -- loads the class and invokes main on it
    }
>

export type LinkNativeCallback = (class_name: string, signature: string) -> NativeMethod?

--- A reference to a class loader. Either "bootstrap", or a reference to a user-defined loader.
export type JvmClassLoader = "bootstrap" | JvmObject

--- A Garbage Collector implementation.
export type IGarbageCollector = setmetatable<
    {
        [any]: any,
    },
    {
        __index: getmetatable<IGarbageCollector>,
        --- Constructor, called by JVM when creating the GC.
        new: (jvm: Jvm, finalise: GcFinalise) -> IGarbageCollector,
        --- Registers a JvmObject with this GC.
        track: (self: IGarbageCollector, object: JvmObject) -> (),
        --- Steps the garbage collector.
        step: (self: IGarbageCollector) -> (),
        [any]: any,
    }
>

--- Callback provided to GC implementations by the JVM to run finalisers on an object. Return value indicates whether to resurrect. Handles deallocation of classes under classloaders.
export type GcFinalise = (object: JvmObject) -> boolean

--[=[
    A class representing a thread of execution in a JVM. 
    
    This is a handler owned by the root Jvm that handles the dispatching of 
    methods to its internal thread.
]=]
export type JvmThread = setmetatable<{
    read jvm: Jvm,
    read _stack: { StackFrame },
    _state: ThreadState,
    _daemon: boolean,
    _mirror: JvmObject,
}, {
    __type: "JvmThread",
    __index: getmetatable<JvmThread>,
    __tostring: (self: JvmThread) -> string,
    __display: (self: JvmThread) -> string,

    _allocate: (jvm: Jvm) -> JvmThread,
}>

export type ThreadState = "new" | "runnable" | "blocked" | "waiting" | "timed_waiting" | "terminated"

export type StackFrame = {
    read jvm: Jvm,
    read method: MethodInfo,
    read class: JvmClass,
    read loader: JvmObjectRef,
    read code: MethodCode,
    read stack: { JvmValue },
    read locals: { JvmValue },
    read pc: number,
    -- Execeptions and debugging info later
}

export type _InvocationResult =
    {
        --- This invocation completed normally with a value.
        read kind: "completed",
        read value: JvmValue,
    }
    | {
        --- This invocation failed.
        read kind: "abrupt",
        read thrown: JvmObject,
    }
    | {
        --- This invocattion yielded (preempted, awaiting lock, etc)
        read kind: "yielded",
    }

export type Monitor = {
    held_by: JvmThread?,
    waiting: { JvmThread },
}

--[=[
    A class representing a loaded JVM class.
]=]
export type JvmClass = setmetatable<
    {
        read jvm: Jvm,
        read name: string,
        read fqcn: string,
        read super: JvmClass?,
        read interfaces: { JvmClass },
        read loader: JvmClassLoader,
        read _methods: { [MethodRef]: MethodInfo },
        read _fields: { [FieldRef]: FieldInfo },
        read _classfile: Classfile?,
        read _monitor: Monitor,
        _mirror: JvmObject,
        _state: JvmClassState,
        read _static_field_values: { [FieldRef]: JvmValue },
    },
    {
        __type: "JvmClass",
        __index: getmetatable<JvmClass>,
        __tostring: (self: JvmClass) -> string,
        __display: (self: JvmClass) -> string,

        --[=[
			Constructs a new class. Not to be confused with `JvmClass:new`, 
			which creates an Object from this class.
		]=]
        _allocate: (
            jvm: Jvm,
            loader: JvmClassLoader,
            name: string,
            super: JvmClass?,
            interfaces: { JvmClass },
            methods: { MethodInfo },
            fields: { FieldInfo },
            classfile: Classfile?
        ) -> JvmClass,

        --[=[
			Calls the class initialiser on this class.
		]=]
        _initialise: (self: JvmClass) -> (),

        --[=[
			Creates a new Object from this class, without initialising it.
		]=]
        new_uninitialised: (self: JvmClass, magic: _MagicValue?) -> JvmObject,

        --[=[
			Creates a new Object from this class, dynamically selecting a
			constructor from given values, if one exists.
		]=]
        new: (self: JvmClass, ...JvmValue) -> JvmObject,

        inherits_from: (self: JvmClass, other: JvmClass) -> boolean,
        implements: (self: JvmClass, interface: JvmClass) -> boolean,
        resolve_method: (self: JvmClass, ref: MethodRef) -> MethodInfo?,
        resolve_field: (self: JvmClass, ref: FieldRef) -> FieldInfo?,
        get_static_field: (self: JvmClass, field: FieldRef) -> JvmValue,
        set_static_field: (self: JvmClass, field: FieldRef, value: JvmValue) -> (),
        --invoke_static_method: (self: JvmClass, method: MethodRef, ...JvmValue) -> JvmValue,
    }
>

export type JvmClassState = "uninitialised" | "initialising" | "initialised" | "error"

--[=[
    A class representing an instantiated JVM object.
]=]
export type JvmObject = setmetatable<
    {
        read jvm: Jvm,
        read class: JvmClass,
        read hash_code: number,

        read _monitor: Monitor,
        read _magic: _MagicValue?,
        --- The actual field values. An absent value means it's uninitialised.
        read _field_values: { [FieldRef]: JvmValue },
    },
    {
        __type: "JvmObject",
        __index: getmetatable<JvmObject>,
        __tostring: (self: JvmObject) -> string,
        __display: (self: JvmObject) -> string,

        --[=[
			Creates a new `Object` without calling initialisers.

			@private
		]=]
        _allocate: (jvm: Jvm, class: JvmClass, magic: _MagicValue?) -> JvmObject,

        --[=[

		]=]
        _initialise: (self: JvmObject, ...JvmValue) -> (),

        instance_of: (self: JvmObject, class: JvmClass) -> boolean,
        implements: (self: JvmObject, interface: JvmClass) -> boolean,

        get_field: (self: JvmObject, field: FieldRef) -> JvmValue,
        set_field: (self: JvmObject, field: FieldRef, value: JvmValue) -> (),
        --invoke_method: (self: JvmObject, method: MethodRef, ...JvmValue) -> JvmValue,

        inner_string: (self: JvmObject) -> string,
        inner_thread: (self: JvmObject) -> JvmThread,
        get_array_length: (self: JvmObject) -> number,
        get_array_element: (self: JvmObject, index: number) -> JvmValue,
        set_array_element: (self: JvmObject, index: number, value: JvmValue) -> (),
        get_array_elements: (self: JvmObject, index: number?, count: number?) -> { JvmValue },
    }
>

export type _MagicValue =
    {
        kind: "string", -- java/lang/String
        value: string,
    }
    | {
        kind: "array", -- synthetic array classes
        length: number,
        element: JvmType,
        values: { JvmValue },
    }
    | {
        kind: "class", -- java/lang/Class
        value: JvmClass,
    }
    | {
        kind: "thread", -- java/lang/Thread
        value: JvmThread,
    }

export type FieldInfo = {
    read name: string,
    read descriptor: string,
    read signature: string,

    read public: boolean,
    read private: boolean,
    read protected: boolean,
    read static: boolean,
    read final: boolean,
    read volatile: boolean,
    read transient: boolean,
    read synthetic: boolean,
    read enum: boolean,
}

export type FieldRef = {
    read class: JvmClass,
    read name: string,
    read descriptor: string,
}

export type MethodInfo = {
    read name: string,
    read descriptor: string,
    read signature: string,
    read code: MethodCode,

    read public: boolean,
    read private: boolean,
    read protected: boolean,
    read static: boolean,
    read final: boolean,
    read synchronised: boolean,
    read varargs: boolean,
    read bridge: boolean,
    read native: boolean,
    read abstract: boolean,
    read strictfp: boolean,
    read synthetic: boolean,
}

export type MethodRef = {
    read class: JvmClass,
    read name: string,
    read descriptor: string,
}

--[=[
	A native method implementation.
]=]
export type NativeMethod = (jvm: Jvm, ...JvmValue) -> JvmValue

--[=[
	The implementation of a `JvmMethod`.

	This is independent of the `native` flag, a non-native synthetic method
	may be implemented with a luau closure, and vice versa.
]=]
export type MethodCode =
    {
        read kind: "luau",
        read closure: NativeMethod,
    }
    | {
        read kind: "java",
        read code: buffer,
    }
    | {
        read kind: "abstract",
    }

--// Classfile Types

export type Classfile = {
    read minor_version: number,
    read major_version: number,
    read constant_pool: { CfCpInfo },
    read access_flags: number,
    read this_class: number,
    read super_class: number,
    read interfaces: { number },
    read fields: { CfFieldInfo },
    read methods: { CfMethodInfo },
    read attributes: { CfAttributeInfo },
}

export type CfCpInfo_Class = {
    read tag: "Class",
    read name_index: number,
}

export type CfCpInfo_Fieldref = {
    read tag: "Fieldref",
    read class_index: number,
    read name_and_type_index: number,
}

export type CfCpInfo_Methodref = {
    read tag: "Methodref",
    read class_index: number,
    read name_and_type_index: number,
}

export type CfCpInfo_InterfaceMethodref = {
    read tag: "InterfaceMethodref",
    read class_index: number,
    read name_and_type_index: number,
}

export type CfCpInfo_String = {
    read tag: "String",
    read string_index: number,
}

export type CfCpInfo_Integer = {
    read tag: "Integer",
    read value: number,
}

export type CfCpInfo_Float = {
    read tag: "Float",
    read value: number,
}

export type CfCpInfo_Long = {
    read tag: "Long",
    read value: integer,
}

export type CfCpInfo_Double = {
    read tag: "Double",
    read value: number,
}

export type CfCpInfo_NameAndType = {
    read tag: "NameAndType",
    read name_index: number,
    read descriptor_index: number,
}

export type CfCpInfo_Utf8 = {
    read tag: "Utf8",
    read value: string,
}

export type CfCpInfo_MethodHandle = {
    read tag: "MethodHandle",
    read reference_kind: number,
    read reference_index: number,
}

export type CfCpInfo_MethodType = {
    read tag: "MethodType",
    read descriptor_index: number,
}

export type CfCpInfo_InvokeDynamic = {
    read tag: "InvokeDynamic",
    read bootstrap_method_attr_index: number,
    read name_and_type_index: number,
}

export type CfCpInfo =
    CfCpInfo_Class
    | CfCpInfo_Fieldref
    | CfCpInfo_Methodref
    | CfCpInfo_InterfaceMethodref
    | CfCpInfo_String
    | CfCpInfo_Integer
    | CfCpInfo_Float
    | CfCpInfo_Long
    | CfCpInfo_Double
    | CfCpInfo_NameAndType
    | CfCpInfo_Utf8
    | CfCpInfo_MethodHandle
    | CfCpInfo_MethodType
    | CfCpInfo_InvokeDynamic

export type CfFieldInfo = {
    read access_flags: number,
    read name_index: number,
    read descriptor_index: number,
    read attributes: { CfAttributeInfo },
}

export type CfMethodInfo = {
    read access_flags: number,
    read name_index: number,
    read descriptor_index: number,
    read attributes: { CfAttributeInfo },
}

export type CfAttributeInfo = {
    read name_index: number,
    read data: buffer,
}

return t
