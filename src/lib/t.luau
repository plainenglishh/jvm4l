--[=[
	Private items are specified with the `_` prefix. Privacy is module-wide; 
	that is, a private item is accessible to any file within `src/lib`, not just
	the file it's defined in.

	Specialised library users, such as debugger implementations, should feel 
	feel free to read from private items, but must never set or construct 
	private items.

    Where possible, define types only within the module they're related to. This
    file is for types used across the entire codebase that cannot reasonably be
    kept within a single module (e.g., if it would cause cyclic dependencies,
    or be far too cumbersome).
]=]
local t = {}

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

--// Computational types

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
--- Any value that can be converted into a `JvmValue`
export type IntoJvmValue = boolean | string | number | integer | JvmObjectRef

--// Actual Types

export type JvmType = "boolean" | "byte" | "short" | "char" | "int" | "long" | "float" | "double" | JvmClass
export type JvmMethodType = {
    arguments: { JvmType },
    returns: JvmType | "void",
}

--------------------------------------------------------------------------------
-- Common Types
--------------------------------------------------------------------------------

--- An object representing arguments to be passed into a method.
export type Arguments = { n: number, [number]: JvmValue }
t.Arguments = {}
--- Creates an `Arguments` from a tuple of `JvmValue`s.
function t.Arguments.from_tuple(...: JvmValue): Arguments
    return table.pack(...)
end
--- Creates an `Arguments` from an array of `JvmValue`s.
function t.Arguments.from_array(values: { JvmValue }, count: number?): Arguments
    local count = count or #values
    local args = table.create(count) :: Arguments
    args.n = count
    table.move(values, 1, count, 1, args)
    return args
end

export type Monitor = {
    --- Who owns this monitor.
    held_by: Thread?,
    --- How many times do the own it.
    held_by_depth: number,
    --- Threads waiting to be notified.
    waiting: { Thread },
}
--- Creates an empty `Monitor`.
function t.Monitor(): Monitor
    return { held_by = nil, held_by_depth = 0, waiting = {} }
end

--- A lazily loaded value.
export type Lazy<T> = setmetatable<{
    _init: () -> T,
    _ready: boolean,
    _value: T?,
}, {
    __index: getmetatable<Lazy<T>>,
    new: (init: () -> T) -> Lazy<T>,
    get: (self: Lazy<T>) -> T,
}>

--------------------------------------------------------------------------------
-- Root JVM
--
-- Types relating to the top level structure of the JVM.
--------------------------------------------------------------------------------

--[=[
    A class representing a JVM instance.

    Handles thread scheduling and the registration of classes.
]=]
export type Jvm = setmetatable<
    {
        read _settings: _JvmSettings,
        read _classes: { [JvmClassLoader]: { [string]: JvmClass } },
        read _threads: { Thread },
        current_thread: Thread?,
        _next_thread_id: number,
        _exec_depth: number,

        _gc: GarbageCollector,
        read _interned_strings: { [string]: JvmObject },
        read _interned_method_handles: { [JvmClass]: { [string]: { [string]: MethodHandle } } }, -- class, name, descriptor
        read _interned_field_handles: { [JvmClass]: { [string]: { [string]: FieldHandle } } }, -- class, name, descriptor
    },
    {
        __type: "Jvm",
        __index: getmetatable<Jvm>,
        __tostring: (self: Jvm) -> string,
        __display: (self: Jvm) -> string,

        new: (settings: IntoJvmSettings) -> Jvm,

        create_thread: (self: Jvm, daemon: boolean, runnable: MethodInfo?) -> Thread,
        _interrupt: (self: Jvm) -> (),

        get_loader: (self: Jvm) -> JvmClassLoader,
        load_class: (self: Jvm, name: string, initiating_loader: JvmClassLoader?) -> JvmClass,
        define_class: (self: Jvm, classfile: buffer, defining_loader: JvmClassLoader) -> JvmClass,

        _get_interned_field: (self: Jvm, class: JvmClass, name: string, descriptor: string) -> FieldHandle?,
        _create_interned_field: (self: Jvm, class: JvmClass, field_info: FieldInfo) -> FieldHandle,
        _get_interned_method: (self: Jvm, class: JvmClass, name: string, descriptor: string) -> MethodHandle?,
        _create_interned_method: (self: Jvm, class: JvmClass, method_info: MethodInfo) -> MethodHandle,

        create_string: (self: Jvm, value: string) -> JvmObject,
        create_array: (self: Jvm, element: JvmType, size_or_values: number | { JvmValue }) -> JvmObject,

        create_exception: (
            self: Jvm,
            name: string,
            message: string?,
            cause: JvmObject?,
            skip_stack_capture: boolean?
        ) -> JvmObject,
        throw_exception: (
            self: Jvm,
            name: string,
            message: string?,
            cause: JvmObject?,
            skip_stack_capture: boolean?
        ) -> never,

        --- Creates an `InternalError`, with a `LuauError` as the cause.
        _create_internal_error: (self: Jvm, message: string, level: number?) -> JvmObject,
        _internal_error: (self: Jvm, message: string, level: number?) -> never,

        coerce: (self: Jvm, ...IntoJvmValue) -> ...JvmValue,

        --[=[
			Executes `main_path`.
		]=]
        run: (self: Jvm, main_path: string, ...JvmValue) -> (), -- loads the class and invokes main on it
    }
>

--- Settings used to control JVM behaviour.
export type IntoJvmSettings = {
    quantum: number?,
    interrupt: InterruptCallback?,
    link_native: LinkNativeCallback,
    trace: TraceCallback?,
}

--- Resolved version of `IntoJvmSettings`.
export type _JvmSettings = {
    quantum: number,
    interrupt: InterruptCallback?,
    link_native: LinkNativeCallback,
    trace: TraceCallback?,
}

--- Callback used to link native methods.
export type LinkNativeCallback = (class_name: string, signature: string) -> NativeMethod?
--- Callback called at VM safepoints.
export type InterruptCallback = (jvm: Jvm) -> ()
--- Callback used to emit internal debug traces.
export type TraceCallback = (message: string) -> ()

--- A reference to a class loader. Either "bootstrap", or a reference to a user-defined loader.
export type JvmClassLoader = "bootstrap" | JvmObject

--- The garbage collector, responsible for tracking, finalising and dropping objects (to allow the Luau GC to clear it)
export type GarbageCollector = setmetatable<
    {
        jvm: Jvm,
        _objects: { [JvmObject]: boolean },
    },
    {
        __index: getmetatable<GarbageCollector>,
        _new: (jvm: Jvm) -> GarbageCollector,
        --- Registers a JvmObject with this GC.
        _track: (self: GarbageCollector, object: JvmObject) -> (),
        --- Steps the garbage collector.
        _step: (self: GarbageCollector) -> (),
    }
>

--------------------------------------------------------------------------------
-- Execution
--
-- Types relating to method invocation, multi-threading and execution.
--------------------------------------------------------------------------------

--- Representation of a thread of execution.
export type Thread = {
    id: number,
    stack: { StackFrame },
    state: ThreadState,
    daemon: boolean,
    mirror: JvmObject,
    budget: number,
    waiting_for: JvmObject?,
    wait_until: number?,
}
export type ThreadState = "new" | "runnable" | "blocked" | "waiting" | "timed_waiting" | "terminated"

--- Representation of a single stack frame.
export type StackFrame =
    {
        method: MethodInfo,
        class: JvmClass,
        loader: JvmObjectRef,
        code: MethodCodeJava,
        stack: { JvmValue },
        stack_top: number,
        locals: { JvmValue },
        pc: number,
        start_pc: number,
        invocation: Invocation?,
    }
    | {
        method: MethodInfo,
        class: JvmClass,
        loader: JvmObjectRef,
        code: MethodCodeLuau,
        args: { JvmValue },
        invocation: Invocation?,
    }

--- Invocation token used as executor targets to get method return values synchronously.
export type Invocation =
    {
        state: "running",
    }
    | {
        state: "failed",
        exception: JvmObject,
    }
    | {
        state: "complete",
        value: JvmValue,
    }

--------------------------------------------------------------------------------
-- Classes
--
-- Types relating to Java classes, particularly loaded classes.
--------------------------------------------------------------------------------

--[=[
    A class representing a loaded JVM class.
]=]
export type JvmClass = setmetatable<
    {
        read jvm: Jvm,
        read name: string,
        read fqcn: string,
        read package: string,
        read super: JvmClass?,
        read interfaces: { JvmClass },
        read loader: JvmClassLoader,

        read public: boolean,
        read final: boolean,
        read super_flag: boolean,
        read interface: boolean,
        read abstract: boolean,
        read synthetic: boolean,
        read annotation: boolean,
        read enum: boolean,

        read source_file: string?,

        read _methods: { MethodInfo },
        read _fields: { FieldInfo },
        read _classfile: Classfile?,
        _constant_pool: ConstantPool?,
        read _monitor: Monitor,
        _mirror: JvmObject,
        _state: JvmClassState,
        read _static_field_values: { [FieldHandle]: JvmValue },
    },
    {
        __type: "JvmClass",
        __index: getmetatable<JvmClass>,
        __tostring: (self: JvmClass) -> string,
        __display: (self: JvmClass) -> string,

        --[=[
			Constructs and prepares a new Class.
		]=]
        _prepare: (
            jvm: Jvm,
            loader: JvmClassLoader,
            name: string,
            super: JvmClass?,
            interfaces: { JvmClass },
            methods: { MethodInfo },
            fields: { FieldInfo },
            access_flags: number,
            classfile: Classfile?,
            source_file: string?
        ) -> JvmClass,

        --[=[
			Calls the class initialiser on this class if it hasn't been called
            already.

            Must be called before:
            1. instantiating objects of this class;
            2. interacting with static methods or fields belonging to this class;
            4. initialisation of a subclass;
            5. if an interface, initialisation of a class that implements this interface (if it implements non abstract/non static methods);
            6. its use as the initial class on startup.
            7. some reflection/invoke methods (see jvms 5.5) 
		]=]
        _ensure_initialised: (self: JvmClass) -> (),

        --[=[
			Creates a new Object from this class, without initialising it.
		]=]
        _new_uninitialised: (self: JvmClass, magic: _MagicValue?) -> JvmObject,

        --[=[
			Creates a new Object from this class, dynamically selecting a
			constructor from given values, if one exists.
		]=]
        new: (self: JvmClass, constructor: MethodHandle?, ...JvmValue) -> JvmObject,

        inherits_from: (self: JvmClass, other: JvmClass) -> boolean,
        implements: (self: JvmClass, interface: JvmClass) -> boolean,
        get_static_field: (self: JvmClass, field: FieldHandle) -> JvmValue,
        set_static_field: (self: JvmClass, field: FieldHandle, value: JvmValue) -> (),

        resolve_method: (self: JvmClass, name: string, descriptor: string) -> MethodHandle,
        resolve_field: (self: JvmClass, name: string, descriptor: string) -> FieldHandle,

        invoke_static: (self: JvmClass, method: MethodHandle, ...JvmValue) -> JvmValue,

        -- Reflection

        get_method: (self: JvmClass, name: string, descriptor: string) -> MethodInfo?,
    }
>

export type JvmClassState = "uninitialised" | "initialising" | "initialised" | "error"

export type ConstantValueType =
    "class"
    | "field"
    | "method"
    | "interface_method"
    | "string"
    | "int"
    | "float"
    | "double"
    | "long"

export type ConstantValue =
    | { type: "class", value: JvmClass }
    | { type: "field", value: FieldHandle }
    | { type: "method" | "interface_method", value: MethodHandle }
    | { type: "string", value: JvmObject }
    | { type: "int" | "float" | "double", value: number }
    | { type: "long", value: integer }

export type ConstantPool = setmetatable<
    {
        read _jvm: Jvm,
        read _class: JvmClass,
        read _classfile: Classfile,
        read _resolved: { [number]: ConstantValue },
    },
    {
        read __index: getmetatable<ConstantPool>,
        read new: (class: JvmClass) -> ConstantPool,
        read _resolve: (self: ConstantPool, idx: number) -> ConstantValue,
        read is: (self: ConstantPool, idx: number, type: ConstantValueType) -> boolean,
        read get: & ((self: ConstantPool, idx: number, type: "class") -> JvmClass)
            & ((self: ConstantPool, idx: number, type: "field") -> FieldHandle)
            & ((self: ConstantPool, idx: number, type: "method" | "interface_method") -> MethodHandle)
            & ((self: ConstantPool, idx: number, type: "string") -> JvmObject)
            & ((self: ConstantPool, idx: number, type: "int" | "float" | "double") -> number)
            & ((self: ConstantPool, idx: number, type: "long") -> integer),
    }
>

--------------------------------------------------------------------------------
-- Objects
--
-- Types relating to Java object instances.
----------------------------------------------------------------------------------

--[=[
    A class representing an instantiated JVM object.
]=]
export type JvmObject = setmetatable<
    {
        read jvm: Jvm,
        read class: JvmClass,
        read hash_code: number,

        read _monitor: Monitor,
        _magic: _MagicValue?,
        --- The actual field values. An absent value means it's uninitialised.
        read _field_values: { [FieldHandle]: JvmValue },
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
        _new: (jvm: Jvm, class: JvmClass, magic: _MagicValue?) -> JvmObject,

        --[=[

		]=]
        _initialise: (self: JvmObject, constructor: MethodHandle?, ...JvmValue) -> (),

        instance_of: (self: JvmObject, class: JvmClass) -> boolean,
        implements: (self: JvmObject, interface: JvmClass) -> boolean,

        get_field: (self: JvmObject, field: FieldHandle) -> JvmValue,
        set_field: (self: JvmObject, field: FieldHandle, value: JvmValue) -> (),
        invoke: (self: JvmObject, method: MethodHandle, ...JvmValue) -> JvmValue,

        inner_string: (self: JvmObject) -> string,
        inner_thread: (self: JvmObject) -> Thread,
        inner_class: (self: JvmObject) -> JvmClass,
        get_array_length: (self: JvmObject) -> number,
        get_array_element: (self: JvmObject, index: number) -> JvmValue,
        set_array_element: (self: JvmObject, index: number, value: JvmValue) -> (),
        get_array_elements: (self: JvmObject, index: number?, count: number?) -> { JvmValue },
    }
>

--- 'Magic' values tagged onto special classes.
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
        value: Thread,
    }
    | {
        kind: "throwable", -- java/lang/Throwable
        stack: { StackFrame },
    }

--------------------------------------------------------------------------------
-- Fields
--
-- Types relating to field metadata and references.
--------------------------------------------------------------------------------

--- Field metadata.
export type FieldInfo = {
    read name: string,
    read descriptor: string,
    read signature: string,
    read type: Lazy<JvmType>,

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

--- Resolved field handle.
export type FieldHandle = {
    read class: JvmClass,
    read info: FieldInfo,
}

--------------------------------------------------------------------------------
-- Methods
--
-- Types relating to method references, metadata and implementations. Types
-- relating to method invocation and execution do not belong here.
--------------------------------------------------------------------------------

--- Method metadata.
export type MethodInfo = {
    read name: string,
    read descriptor: string,
    read signature: string,
    read code: MethodCode,
    read type: Lazy<JvmMethodType>,

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

--- Resolved method handle.
export type MethodHandle = {
    read class: JvmClass,
    read info: MethodInfo,
}

--[=[
	A native method implementation.
]=]
export type NativeMethod = (jvm: Jvm, ...JvmValue) -> JvmValue

--[=[
	The implementation of a `JvmMethod`.

	This is independent of the `native` and `abstract` flags, a non-native 
    synthetic method may be implemented with a luau closure, and vice versa.
]=]
export type MethodCode = MethodCodeLuau | MethodCodeJava | MethodCodeAbstract

--[=[
    A Luau (native) implementation of a method.
]=]
export type MethodCodeLuau = {
    read kind: "luau",
    read closure: NativeMethod,
}

--[=[
    A Java (bytecode) implementation of a method.
]=]
export type MethodCodeJava = {
    read kind: "java",
    read max_stack: number,
    read max_locals: number,
    read code: buffer,
    read exceptions: ExceptionTable,
    read line_numbers: LineNumberTable?,
}

export type LineNumberTable = { LineNumberTableEntry }
export type LineNumberTableEntry = {
    start_pc: number,
    line: number,
}

export type ExceptionTable = { ExceptionHandler }
export type ExceptionHandler = {
    start_pc: number,
    end_pc: number,
    handler_pc: number,
    catch_type: JvmClass?,
}

--[=[
    A method without an implementation.
]=]
export type MethodCodeAbstract = {
    read kind: "abstract",
}

--------------------------------------------------------------------------------
-- Classfiles
--
-- This section contains types relating to classfiles.
--
-- As a general rule, if an attribute can be parsed into a live type defined
-- above, it should be. Otherwise, it should be a classfile specific type
-- defined below.
--------------------------------------------------------------------------------

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

export type CfCodeAttribute = {
    max_stack: number,
    max_locals: number,
    code: buffer,
    exceptions: {
        {
            start_pc: number,
            end_pc: number,
            handler_pc: number,
            catch_type: number,
        }
    },
    attributes: { CfAttributeInfo },
}

return t
