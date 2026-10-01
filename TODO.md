# Todo

- Basic object model is complete, bar special handling for inner classes.

## Short Term Goals

- [X] Descriptor to `JvmType`
- [X] Exceptions (simply the objects themselves, rather than catching)
- [X] Field value get/set
- [ ] Threads
- [ ] Method calling & execution engine
- [ ] Typechecking and access checking the above
- [X] Strings
- [X] Arrays

## Long Term Goals

- [ ] Magic luau interop classes (maybe even don't treat java/lang/String as a magic class, but back it with a magic jvl4/luau/String?)