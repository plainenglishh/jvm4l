local util = {}

function util.unimplemented(note: string?): never
    local msg = "unimplemented"
    if note then
        msg ..= `: {note}`
    end
    error(msg, 2)
end

function util.is_object(value: unknown): boolean
    return type(value) == "table" and (value :: any).__type == "JvmObject"
end

function util.is_class(value: unknown): boolean
    return type(value) == "table" and (value :: any).__type == "JvmClass"
end

return util
