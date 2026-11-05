local descriptors = {}

type SlotSize = "1" | "2"

function descriptors.argument_words(descriptor: string): { SlotSize }
    local slots: { SlotSize } = {}
    local i = 1
    local len = string.len(descriptor)

    local BYTE_LPAREN = 40
    local BYTE_RPAREN = 41
    local BYTE_SEMI = 59
    local BYTE_LBRACK = 91
    local BYTE_J = 74
    local BYTE_D = 68
    local BYTE_L = 76

    while i <= len do
        local b = string.byte(descriptor, i)
        i += 1

        if b == BYTE_LPAREN then
            continue
        elseif b == BYTE_RPAREN then
            break
        end

        if b == BYTE_J or b == BYTE_D then
            table.insert(slots, "2" :: "2")
        elseif b == BYTE_L then
            table.insert(slots, "1" :: "1")
            while i <= len and string.byte(descriptor, i) ~= BYTE_SEMI do
                i += 1
            end
            i += 1
        elseif b == BYTE_LBRACK then
            table.insert(slots, "1" :: "1")
            while i <= len and string.byte(descriptor, i) == BYTE_LBRACK do
                i += 1
            end
            if string.byte(descriptor, i) == BYTE_L then
                while i <= len and string.byte(descriptor, i) ~= BYTE_SEMI do
                    i += 1
                end
                i += 1
            else
                i += 1
            end
        else
            table.insert(slots, "1" :: "1")
        end
    end

    return slots
end

return descriptors
