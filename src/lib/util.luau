local util = {}

function util.unimplemented(note: string?): never
    local msg = "unimplemented"
    if note then
        msg ..= `: {note}`
    end
    error(msg, 2)
end

return util
