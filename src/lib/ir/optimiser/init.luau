local copy_propagation = require("@self/copy_propagation")
local dead_store_elimination = require("@self/dead_store_elimination")
local strip_nop = require("@self/strip_nop")
local t = require("../t")
local analysis = require("./analysis")
local optimiser = {}

function optimiser.optimise(
    ir: buffer,
    handlers: { t.ExceptionHandler },
    locals_start_reg: number,
    level: number
): buffer
    local blocks = analysis.basic_blocks(ir, handlers)

    if level > 0 then
        --copy_propagation(ir, blocks)
        dead_store_elimination(ir, blocks, locals_start_reg)
    end

    return strip_nop(ir, handlers)
end

return optimiser
