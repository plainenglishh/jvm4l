local fs = require("@std/fs")

local content = fs.readFileToString("profile.out")
local output = {}

for line in string.gmatch(content, "[^\r\n]+") do
    line = string.match(line, "^%s*(.-)%s*$") or error("")

    local count, stack = string.match(line, "^(%d+)%s+(.+)$")

    if count and stack then
        stack = string.gsub(stack, ",%d+$", "")
        stack = string.gsub(stack, ",", ":")

        local frames: { string } = {}
        for frame in string.gmatch(stack, "[^;]+") do
            frame = string.match(frame, "^%s*(.-)%s*$") or error("")

            if frame ~= "" then
                table.insert(frames, frame)
            end
        end

        local reversed = {}

        for i = #frames, 1, -1 do
            table.insert(reversed, frames[i])
        end

        if #reversed > 0 then
            table.insert(output, table.concat(reversed, ";") .. " " .. count)
        end
    end
end

fs.writeStringToFile("firefox.out", table.concat(output, "\n") .. "\n")
