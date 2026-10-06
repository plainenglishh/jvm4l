--[[
    design notes:

    1. execution is driven through the execution engine, invoked through host
       level method calls (called native calls, note: not calling native methods). 
    
    2. non-top level native calls drive the execution engine until a target 
       thread's stack reaches a certain level, after which it reads a returned 
       value from the stack to give back to the caller. the top level native 
       call runs until all non-daemon threads are finished.

    3. the execution engine drives *all* threads. it has no notion of a target,
       the native call simply uses the target to know when to stop driving the 
       execution engine. 
       
    4. the execution engine repeatedly pops a frame from the current thread and 
       runs it until it yields, is blocked, or reaches a quota, after which it
       asks the scheduler to assign the next thread, and continues on that new
       thread. (note: unify scheduler & exec engine?)
    
    5. native calls may be nested, and the outermost native call is the one
       driving the execution engine.

    6. native calls must check whether its target is complete *before* driving
       the execution engine, as a nested call may have completed its target.
]]
