local fs = require("@std/fs")
local content = fs.readFileToString("profile.out")

local output = {}

for line in string.gmatch(content, "[^\r\n]+") do
    line = string.gsub(line, "^%s+", "")

    local count, stack = string.match(line, "^(%d+)%s+(.*)$")
    if not count or not stack then
        continue
    end

    stack = string.gsub(stack, ",%d+$", "")
    stack = string.gsub(stack, ",", ":")

    local frames: { string } = {}
    for frame in string.gmatch(stack, "[^;]+") do
        table.insert(frames, frame)
    end

    local reversed = {}
    for i = #frames, 1, -1 do
        table.insert(reversed, frames[i])
    end

    table.insert(output, table.concat(reversed, ";") .. " " .. count)
end

fs.writeStringToFile("firefox.out", table.concat(output, "\n") .. "\n")
