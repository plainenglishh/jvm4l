local t = require("../t")
local util = require("../util")

export type DispatchType = "static" | "special" | "virtual" | "interface" | "dynamic"
export type DispatchedMethod = {
    read method: t.Method,
}

local function assert_not_abstract(jvm: t.Jvm, method: t.Method)
    if method.abstract then
        jvm:throw_exception("java/lang/AbstractMethodError")
    end
end

local dispatcher = {}

--[=[
    Dispatches a method handle based on the target dispatch mode, throwing relevant runtime errors.
]=]
function dispatcher.dispatch(
    jvm: t.Jvm,
    method: t.Method,
    type: DispatchType,
    executing_class: t.JvmClass,
    executing_object: t.JvmObject?
): DispatchedMethod
    local dispatched_method: t.Method

    if type == "static" then
        if not method.static then
            return jvm:throw_exception(
                "java/lang/IncompatibleClassChangeError",
                `attempt to statically dispatch non static method {method.class.name}.{method.name}{method.descriptor}`
            )
        end
        dispatched_method = method
    elseif type == "special" then
        if method.static then
            return jvm:throw_exception(
                "java/lang/IncompatibleClassChangeError",
                `attempt to specially dispatch static method {method.class.name}.{method.name}{method.descriptor}`
            )
        end

        if method.name == "<init>" or method.private then
            dispatched_method = method
        elseif method.class.interface then
            dispatched_method = method
        else
            dispatched_method = method

            if executing_class.super_flag and executing_class:inherits_from(method.class) then
                local current = executing_class.super
                while current do
                    local info = current:get_method(method.name, method.descriptor)
                    if info then
                        dispatched_method = info
                        break
                    end

                    current = current.super
                end
            end
        end
    elseif type == "virtual" or type == "interface" then
        if method.static then
            return jvm:throw_exception(
                "java/lang/IncompatibleClassChangeError",
                `attempt to virtually/interface dispatch static method {method.class.name}.{method.name}{method.descriptor}`
            )
        end

        if not executing_object then
            return jvm:throw_exception("java/lang/NullPointerException")
        end

        local current = executing_object.class
        while current do
            local info = current:get_method(method.name, method.descriptor)
            if info and not info.static then
                if type == "interface" and not info.public then
                    return jvm:throw_exception("java/lang/IllegalAccessError")
                end

                if type == "virtual" and info.private then
                    -- keep searching
                else
                    dispatched_method = info
                    break
                end
            end
            current = current.super
        end

        if not dispatched_method then
            if type == "interface" then
                return jvm:throw_exception("java/lang/AbstractMethodError")
            else
                dispatched_method = method
            end
        end
    elseif type == "dynamic" then
        return util.unimplemented("dynamic dispatch is unimplemented")
    end

    assert_not_abstract(jvm, dispatched_method)
    return table.freeze({
        method = method,
    })
end

return dispatcher
