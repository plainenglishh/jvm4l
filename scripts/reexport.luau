--[=[
    This script is responsible for reexporting public times from 
    `src/lib/t.luau` to `src/lib/init.luau`.
]=]

local fs = require("@std/fs")

local syntax = require("@std/syntax")
local visitor = require("@std/syntax/visitor")

local src = fs.readFileToString("src/lib/t.luau")

local function discover_types(src: string): { string }
    local parse_result = syntax.parse(src)

    local type_def_visitor = visitor.create()

    local types = {}
    type_def_visitor.visitStatTypeAlias = function(t: syntax.CstStatTypeAlias)
        local name = t.name.text
        if string.sub(name, 1, 1) == "_" then
            return false
        end

        table.insert(types, name)

        return true
    end

    visitor.visit(parse_result.root, type_def_visitor)

    return types
end

local types = discover_types(src)
local out = {}

for _, type_name in types do
    table.insert(out, `export type {type_name} = t.{type_name}`)
end

local reexport_block = `--EXPORT_BEGIN\n{table.concat(out, "\n")}\n--EXPORT_END`

local dst = fs.readFileToString("./src/lib/init.luau")
dst = dst:gsub("%-%-EXPORT_BEGIN\n(.-)%-%-EXPORT_END", reexport_block)

fs.writeStringToFile("./src/lib/init.luau", dst)
