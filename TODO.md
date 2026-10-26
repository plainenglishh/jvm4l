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

- [ ] Ability to create threads with runnable targets
- [ ] Complete all opcodes
- [ ] Magic luau interop classes (maybe even don't treat java/lang/String as a magic class, but back it with a magic jvl4/luau/String?)