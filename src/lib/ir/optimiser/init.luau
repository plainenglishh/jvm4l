local copy_propagation = require("@self/copy_propagation")
local dead_store_elimination = require("@self/dead_store_elimination")
local strip_nop = require("@self/strip_nop")
local t = require("../t")
local analysis = require("./analysis")
local optimiser = {}

function optimiser.optimise(code: t.MethodCodeIr, level: number)
    local blocks = analysis.basic_blocks(code.code, code.exceptions)

    if level > 0 then
        copy_propagation(code.code, blocks)
        dead_store_elimination(code.code, blocks, code.local_register_start)
    end

    --(code :: any).code = strip_nop(code.code, code.exceptions) rework to use
end

return optimiser
