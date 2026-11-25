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
invocation. This includes host-side invocations-such as reentrant method
calls within native methods and static initialisers-as well as the top-level 
invocation. An arbitrary number of nested executors are allowed.

Synchronous invocations can be marked 'exclusive' to constrain it into *only* 
executing the thread on which its invocation object exists. 

Invocations that do not require synchronous returns are executed 'inline' by 
simply pushing a new stack frame and reusing the current executor. All bytecode
`invoke` instructions use this mechanism. This is the most common invocation 
type.

If an invocation fails, be it from a thrown exception, an internal error 
(coerced into `java.lang.InternalError`), or a failed native method, the 
thread's stack will unwind until it is caught in bytecode, or until a native 
frame is hit, after which it is considered caught. If the exception hit a native 
frame, the exception is thrown in the native context as a Luau error to be 
caught by `pcall`. If it is not caught by the native method, the native method 
fails, and unwinding begins again from where it left off.

In practice, the Luau call stack remains relatively flat, except for host-side 
invocations, regardless of how many JVM stack frames are used.

## Steps and Step Breaks

Execution is performed in steps. A step consists of executing either Java 
bytecode or a Luau function (be it a native method, or a JIT compiled method),
until a 'step break'. A step break is a point at which a step halts, recommits
any cached information (if relevant), and returns to the executor loop. Step 
breaks occur *after* the instruction has finished.

This is distinct from method returns, which do not require the step to be 
resumed again, and from exception throwing/handling.

The conditions that require a step break are:-
1. an inline invocation, to allow the executor to begin executing the new frame;
2. thread synchronisation (e.g. `monitorenter`/`monitorexit`);
3. budget exhaustion (which may be determined by either instruction count or 
   jump count).

Native methods also support break to enable asynchronous methods.

The handling of breaks in the IR interpreter is trivial, as very few values are
cached and execution can resume at any instruction, and the few cached values it
uses are committed at the end of the function. 

JIT methods, however, require careful consideration, as the points at which
execution can resume are limited. Currently, JIT uses a simple trampoline, so 
only the beginning of basic blocks can be entered externally. It is for this
reason the `ir.analysis` library terminates basic blocks when encountering a
breakable instruction.

It is safe to make *exclusive* synchronous invocations directly underneath 
bytecode instructions. This is intentionally used for instructions that may 
cause a class to be initialised to prevent unnecessary step breaks. Note that
these methods may still fail, so such instructions are marked as fallible,
and require some cached values to be committed (dirty cached registers and the 
pc of the current instruction) *before* executing.
