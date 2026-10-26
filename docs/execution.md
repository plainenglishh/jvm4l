# Execution

Jvm4L execution begins either with the host-side invocation of a method, or the
creation of a main thread, which triggers the invocation of its top-level static 
`main` method.

Methods may be implemented in both Java and Luau.

Execution is driven by an 'executor', which takes a target invocation result
and repeatedly executes all runnable threads until its target completes or 
fails. Once finished, it reports the result. This model allows Jvm4L to execute 
methods synchronously while remaining multithreaded.

The top-level main invocation is a special case; instead of completing immediately 
when the main method finishes, it completes only when all non-daemon threads
have finished.

Executors are used whenever the JVM requires a synchronous value from a method
invocation. This includes host-side invocations—such as reentrant method
calls within native methods and static initialisers—as well as the top-level 
invocation. An arbitrary number of nested executors are allowed.

Invocations that do not require synchronous returns are executed 'inline' by 
simply pushing a new stack frame and reusing the current executor. All bytecode
`invoke?` instructions use this mechanism. This is the most common invocation type.

If an invocation fails, be it from a thrown exception, an internal error 
(coerced into `java.lang.InternalError`), or a failed native method, the 
thread's stack will unwind until it is caught in bytecode, or until a native 
frame is hit, after which it is considered caught. If the exception hit a native 
frame, the exception is thrown in the native context as a Luau error to be 
caught by `pcall`. If it is not caught by the native method, the native method 
fails, and unwinding begins again from where it left off.