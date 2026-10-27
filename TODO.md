# Todo

- Basic object model is complete, bar special handling for inner classes.

## Short Term Goals

- [ ] move some work (e.g. resolution) out of `Jvm`. it shouldnt be a god class!
- [ ] threading:
    - [X] current_thread no longer always set, create ephemeral thread for host side :invoke if none are set
    - [ ] ability to create new threads with runnable targets/main class
    - [ ] proper scheduling
    - [ ] monitorenter/exit
- [x] type/access check on frame push
- [ ] reflection methods on JvmClass.
- [ ] TESTING!!
- [X] important!: clarify class lifecycle. when classes are loaded, initialised, etc, and when to resolve symbolic references (jvmtype is currently a live reference, should it be symbolic?)
- [X] lazily loaded constant pool (backed by the classfile)
- [X] consider 'unflattening' method/field tables
- [X] transition to invocation to MethodHandle/FieldHandle, and introduce method dispatch seperately in exec engine
- [X] move jvm:invoke into JvmClass:invoke_static() and JvmObject:invoke()
- [X] Descriptor to `JvmType`
- [X] Exceptions (simply the objects themselves, rather than catching)
- [X] Field value get/set
- [x] Field/Method resolution
- [X] Threads
- [X] Method calling & execution engine
- [X] Strings
- [X] Arrays

## Long Term Goals

- [ ] GC
    - [X] track all JvmObjects
    - [ ] trace references (inc. weak references), and mark unreachable objects for deletion
    - [ ] delete objects by calling its finaliser (which can prevent deletion), and dropping the object from the GC tracking table to allow the Luau GC to properly deallocate it
- [ ] Complete all opcodes
- [ ] Magic luau interop classes (maybe even don't treat java/lang/String as a magic class, but back it with a magic jvl4/luau/String?)
- [ ] JIT
    - transpile java bytecode into luau source code to be loaded by a host provided 'load' function.
    - split into basic blocks, use trampoline for gotos
    - tailor output for native codegen, and return 'status' tokens for stuff like budget exhaustion, monitor waits, etc
    - treeshake top level functions (e.g. `pop`)
- [ ] Bytecode verification