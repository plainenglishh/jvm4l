--[[
    This file serves as the authorative source on the Jvm4L IR.
    Metadata fields can be used for debugging information, for codegen
    decisions, or to help guide implementation involving the IR where
    using this table in a hot loop is too slow.

    The IR described herein is not stable.

    When making an update to IR, the following places may need to be manually 
    updated:
    1. this file, obviously;
    2. the interpreter loop (`src/lib/execution/step.luau`);
    3. the jit code generator (`src/lib/jit/generate.luau`);
    4. the ir transpiler (`src/lib/ir/*.luau`).
]]

export type Operand = {
    type: "u8" | "i8" | "u16" | "i16" | "u32" | "i32" | "f32" | "i64" | "f64",
    usage: "reg_dst" | "reg_src" | "constant" | "jump_target" | "literal" | "dispatch_type",
}

export type Operands = { Operand } | "variable"

export type InstructionInfo = {
    read opcode: number,
    read name: string,
    read size: number?,
    read operands: Operands,

    --- Whether this instruction requires a step burst to break (e.g. on method invocation, scheduler boundary, method return, etc)
    read breaks: boolean,
    --- Whether this instruction can jump.
    read can_jump: boolean,
    --- Whether this instruction can fail.
    read fallible: boolean,
}

type IntoInstructionInfo = {
    operands: Operands?,
    breaks: boolean?,
    fallible: boolean?,
}

local INSTRUCTIONS: { [number]: InstructionInfo } = {}

local function DEFINE_OP(op: number, name: string, into: IntoInstructionInfo?)
    local into: IntoInstructionInfo = into or {}

    local size: number? = nil
    local can_jump = false
    if into.operands ~= "variable" then
        local new_size = 1
        for _, operand in (into.operands or {}) :: { Operand } do
            if operand.type == "u8" or operand.type == "i8" then
                new_size += 1
            elseif operand.type == "u16" or operand.type == "i16" then
                new_size += 2
            elseif operand.type == "u32" or operand.type == "i32" or operand.type == "f32" then
                new_size += 4
            elseif operand.type == "i64" or operand.type == "f64" then
                new_size += 8
            else
                error("bad")
            end

            if operand.usage == "jump_target" then
                can_jump = true
            end
        end
        size = new_size
    end

    INSTRUCTIONS[op] = table.freeze({
        opcode = op,
        name = name,
        size = size,
        operands = into.operands or {},
        breaks = into.breaks or false,
        can_jump = can_jump,
        fallible = into.fallible or false,
    })
end

--------------------------------------------------------------------------------

DEFINE_OP(0x00, "nop")

DEFINE_OP(0x01, "move", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" },
    },
})

--------------------------------------------------------------------------------

DEFINE_OP(0x10, "load_literal/null", {
    operands = {
        { type = "u16", usage = "reg_dst" },
    },
})

DEFINE_OP(0x11, "load_literal/int", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "i32", usage = "literal" },
    },
})

DEFINE_OP(0x12, "load_literal/float", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "f32", usage = "literal" },
    },
})

DEFINE_OP(0x13, "load_literal/long", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "i64", usage = "literal" },
    },
})

DEFINE_OP(0x14, "load_literal/double", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "f64", usage = "literal" },
    },
})

DEFINE_OP(0x15, "load_const", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "constant" },
    },
    fallible = true,
})

--------------------------------------------------------------------------------

DEFINE_OP(0x20, "add/int", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
    },
})

DEFINE_OP(0x21, "sub/int", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
    },
})

-- fast path for iinc
DEFINE_OP(0x22, "add_literal/int", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "i32", usage = "literal" }, --rhs
    },
})

----------------------------------------------------------------------------

DEFINE_OP(0x40, "jump_if_eq/int", {
    operands = {
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
        { type = "u32", usage = "jump_target" },
    },
})

DEFINE_OP(0x41, "jump_if_ne/int", {
    operands = {
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
        { type = "u32", usage = "jump_target" },
    },
})

DEFINE_OP(0x42, "jump_if_lt/int", {
    operands = {
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
        { type = "u32", usage = "jump_target" },
    },
})

DEFINE_OP(0x43, "jump_if_ge/int", {
    operands = {
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
        { type = "u32", usage = "jump_target" },
    },
})

DEFINE_OP(0x44, "jump_if_gt/int", {
    operands = {
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
        { type = "u32", usage = "jump_target" },
    },
})

DEFINE_OP(0x45, "jump_if_le/int", {
    operands = {
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
        { type = "u32", usage = "jump_target" },
    },
})

DEFINE_OP(0x46, "jump_if_eq/ref", {
    operands = {
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
        { type = "u32", usage = "jump_target" },
    },
})

DEFINE_OP(0x50, "jump", {
    operands = {
        { type = "u32", usage = "jump_target" },
    },
})

--------------------------------------------------------------------------------

DEFINE_OP(0x60, "get_field", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, -- object
        { type = "u16", usage = "constant" }, -- field
    },
    fallible = true,
})

DEFINE_OP(0x61, "set_field", {
    operands = {
        { type = "u16", usage = "reg_dst" }, -- object
        { type = "u16", usage = "reg_src" }, -- value
        { type = "u16", usage = "constant" }, -- field
    },
    fallible = true,
})

DEFINE_OP(0x62, "get_static", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "constant" },
    },
    fallible = true,
})

DEFINE_OP(0x63, "set_static", {
    operands = {
        { type = "u16", usage = "reg_src" },
        { type = "u16", usage = "constant" },
    },
    fallible = true,
})

--------------------------------------------------------------------------------

DEFINE_OP(0x70, "new", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "constant" },
    },
    fallible = true,
})

DEFINE_OP(0x71, "throw", {
    operands = {
        { type = "u16", usage = "reg_src" },
    },
    fallible = true,
})

--------------------------------------------------------------------------------

DEFINE_OP(0x80, "invoke", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "constant" }, -- method
        { type = "u16", usage = "reg_src" }, -- arg_start
        { type = "u8", usage = "literal" }, -- arg_count
        { type = "u8", usage = "dispatch_type" },
    },
    breaks = true,
    fallible = true,
})

DEFINE_OP(0x81, "return", {
    operands = {
        { type = "u16", usage = "reg_src" },
    },
    breaks = true,
})

--------------------------------------------------------------------------------

return INSTRUCTIONS
