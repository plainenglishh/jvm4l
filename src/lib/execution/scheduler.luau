local t = require("../t")
local scheduler = {}

--[=[
    Checks whether a new thread should be scheduled, and schedules a new thread
    if necessary.

    Reschedule conditions are:
    1. the current thread has reached its budget;
    2. the current thread is blocked or terminated. 
]=]
function scheduler.try_reschedule(jvm: t.Jvm) end

return scheduler
