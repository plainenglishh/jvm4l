export type Operand = {
    type: "u8" | "i8" | "u16" | "i16" | "u32" | "i32" | "f32" | "i64" | "f64",
    usage: "reg_dst" | "reg_src" | "constant" | "jump_target" | "literal" | "dispatch_type",
}

export type Operands = { Operand } | "variable"

export type InstructionInfo = {
    read opcode: number,
    read name: string,
    read operands: Operands,
    --- Whether this instruction requires a step burst to break (e.g. on method invocation, scheduler boundary, method return, etc)
    read breaks: boolean,
    read size: number?,
}

type IntoInstructionInfo = {
    operands: Operands?,
    breaks: boolean?,
}

local INSTRUCTIONS: { [number]: InstructionInfo } = {}

local function DEFINE_OP(op: number, name: string, into: IntoInstructionInfo?)
    local into: IntoInstructionInfo = into or {}

    local size: number? = nil
    if into.operands ~= "variable" then
        local new_size = 1
        for _, operand in into.operands or {} do
            if operand.type == "u8" or operand.type == "i8" then
                new_size += 1
            elseif operand.type == "u16" or operand.type == "i16" then
                new_size += 2
            elseif operand.type == "i32" or operand.type == "f32" then
                new_size += 4
            elseif operand.type == "i64" or operand.type == "f64" then
                new_size += 8
            end
        end
        size = new_size
    end

    INSTRUCTIONS[op] = table.freeze({
        opcode = op,
        name = name,
        operands = into.operands or {},
        breaks = into.breaks or false,
        size = size,
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

--------------------------------------------------------------------------------

DEFINE_OP(0x40, "compare_eq/int", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
    },
})

DEFINE_OP(0x41, "compare_ne/int", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
    },
})

DEFINE_OP(0x42, "compare_lt/int", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
    },
})

DEFINE_OP(0x43, "compare_ge/int", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
    },
})

DEFINE_OP(0x44, "compare_gt/int", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
    },
})

DEFINE_OP(0x45, "compare_le/int", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
    },
})

DEFINE_OP(0x46, "compare_eq/ref", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "reg_src" }, --lhs
        { type = "u16", usage = "reg_src" }, --rhs
    },
})

--------------------------------------------------------------------------------

DEFINE_OP(0x50, "jump", {
    operands = {
        { type = "u32", usage = "jump_target" },
    },
})

DEFINE_OP(0x51, "jump_if", {
    operands = {
        { type = "u16", usage = "reg_src" },
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
})

DEFINE_OP(0x61, "set_field", {
    operands = {
        { type = "u16", usage = "reg_dst" }, -- object
        { type = "u16", usage = "reg_src" }, -- value
        { type = "u16", usage = "constant" }, -- field
    },
})

DEFINE_OP(0x62, "get_static", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "constant" },
    },
})

DEFINE_OP(0x63, "set_static", {
    operands = {
        { type = "u16", usage = "reg_src" },
        { type = "u16", usage = "constant" },
    },
})

--------------------------------------------------------------------------------

DEFINE_OP(0x70, "new", {
    operands = {
        { type = "u16", usage = "reg_dst" },
        { type = "u16", usage = "constant" },
    },
})

DEFINE_OP(0x71, "throw", {
    operands = {
        { type = "u16", usage = "reg_src" },
    },
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
})

DEFINE_OP(0x81, "invoke/void", {
    operands = {
        { type = "u16", usage = "constant" }, -- method
        { type = "u16", usage = "reg_src" }, -- arg_start
        { type = "u8", usage = "literal" }, -- arg_count
        { type = "u8", usage = "dispatch_type" },
    },
    breaks = true,
})

DEFINE_OP(0x82, "return", {
    operands = {
        { type = "u16", usage = "reg_src" },
    },
    breaks = true,
})

DEFINE_OP(0x83, "return/void", {
    breaks = true,
})

--------------------------------------------------------------------------------

return INSTRUCTIONS
