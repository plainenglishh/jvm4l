# Todo

- Basic object model is complete, bar special handling for inner classes.

## Short Term Goals

- [X] important!: clarify class lifecycle. when classes are loaded, initialised, etc, and when to resolve symbolic references (jvmtype is currently a live reference, should it be symbolic?)
- [X] lazily loaded constant pool (backed by the classfile)
- [ ] TESTING!!
- [X] consider 'unflattening' method/field tables
- [X] transition to invocation to MethodHandle/FieldHandle, and introduce method dispatch seperately in exec engine
- [ ] move jvm:invoke into JvmClass:invoke_static() and JvmObject:invoke()
- [X] Descriptor to `JvmType`
- [X] Exceptions (simply the objects themselves, rather than catching)
- [X] Field value get/set
- [x] Field/Method resolution
- [X] Threads
- [X] Method calling & execution engine
- [ ] Typechecking and access checking the above
- [X] Strings
- [X] Arrays

## Long Term Goals

- [ ] Ability to create threads with runnable targets
- [ ] Complete all opcodes
- [ ] Magic luau interop classes (maybe even don't treat java/lang/String as a magic class, but back it with a magic jvl4/luau/String?)