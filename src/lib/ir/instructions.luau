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

--[[
    Instruction Format:
        `<opcode:u8>{<operand:Operand>}`

    Operand Formats:
        register = `<reg:u16>`
        register_array = `<count:u8>{<reg:u16>}`
        literal:
            i32 = `<value:i32>`
            f32 = `<value:f32>`
            i64 = `<value:i64>`
            f64 = `<value:f64>`
        constant` = `<const:u16>`
        jump_target = `<target:u32>`
        dispatch_type = `<type:u8>` where:
            0 = VIRTUAL
            1 = SPECIAL
            2 = STATIC
            _ = INVALID
        variable `<len:u16>{<data:u8>}`
    ]]

--- An Instruction or Operand size.
export type Size = number | "variable"
export type Operand = IntoOperand & {
    offset: number,
    size: number,
}

export type IntoOperand =
    {
        type: "register",
        direction: "dst" | "src",
    }
    | {
        type: "register_block",
    }
    | {
        type: "literal",
        literal_type: "i32" | "f32" | "i64" | "f64",
    }
    | {
        type: "constant" | "jump_target" | "dispatch_type" | "variable",
    }

local function sizeof_intooperand(operand: IntoOperand): Size
    if operand.type == "register" then
        return 2
    elseif operand.type == "register_block" then
        return 3
    elseif operand.type == "literal" then
        if operand.literal_type == "i32" or operand.literal_type == "f32" then
            return 4
        elseif operand.literal_type == "i64" or operand.literal_type == "f64" then
            return 8
        else
            error("unsupported operand type")
        end
    elseif operand.type == "constant" then
        return 2
    elseif operand.type == "jump_target" then
        return 4
    elseif operand.type == "dispatch_type" then
        return 1
    elseif operand.type == "variable" then
        return "variable"
    else
        error("unsupported operand type" .. operand.type)
    end
end

export type Operands = { Operand }
export type IntoOperands = { IntoOperand }

export type Instruction = {
    read opcode: number,
    read name: string,
    read size: Size,
    read operands: Operands,
    --- Whether this instruction requires a step burst to break (e.g. on method invocation, scheduler boundary, method return, etc)
    read breaks: boolean,
    --- Whether this instruction can jump.
    read can_jump: boolean,
    --- Whether this instruction can fail.
    read fallible: boolean,
    --- Callback used to determine the size of a potentially variable-length instruction.
    read sizeof: (ir: buffer, start_pc: number) -> number,
}

type IntoInstruction = {
    operands: IntoOperands?,
    breaks: boolean?,
    fallible: boolean?,
}

local INSTRUCTIONS: { [number]: Instruction } = {}

local function DEFINE_OP(op: number, name: string, into: IntoInstruction?)
    local into: IntoInstruction = into or {}
    local into_operands: IntoOperands = into.operands or {}

    local can_jump = false
    local operands: Operands = {}

    local encountered_variable = false
    local offset = 1
    local base_size = 0
    for i, into_operand: IntoOperand in into_operands do
        assert(not encountered_variable, "variable operand must be last")

        local operand = table.clone(into_operand) :: Operand
        operand.offset = offset

        if operand.type == "jump_target" then
            can_jump = true
        end

        if into_operand.type == "variable" then
            encountered_variable = true
            base_size = offset
        else
            local operand_size = sizeof_intooperand(into_operand)
            assert(operand_size ~= "variable")
            offset += operand_size
            operand.size = operand_size
        end
        operands[i] = operand
    end

    local size: Size = if encountered_variable then "variable" else offset

    INSTRUCTIONS[op] = table.freeze({
        opcode = op,
        name = name,
        size = size,
        operands = operands,
        breaks = into.breaks or false,
        can_jump = can_jump,
        fallible = into.fallible or false,
        sizeof = function(ir: buffer, start_pc: number): number
            assert(buffer.readu8(ir, start_pc) == op)
            if size ~= "variable" then
                return size
            end

            local len = buffer.readu8(ir, start_pc + base_size)
            return base_size + len + 1
        end,
    })
end

--------------------------------------------------------------------------------

DEFINE_OP(0x00, "nop")

DEFINE_OP(0x01, "move", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "register" :: "register", direction = "src" },
    },
})

--------------------------------------------------------------------------------

DEFINE_OP(0x10, "load_literal/null", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
    },
})

DEFINE_OP(0x11, "load_literal/int", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "literal" :: "literal", literal_type = "i32" },
    },
})

DEFINE_OP(0x12, "load_literal/float", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "literal" :: "literal", literal_type = "f32" },
    },
})

DEFINE_OP(0x13, "load_literal/long", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "literal" :: "literal", literal_type = "i64" },
    },
})

DEFINE_OP(0x14, "load_literal/double", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "literal" :: "literal", literal_type = "f64" },
    },
})

DEFINE_OP(0x15, "load_const", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "constant" },
    },
    fallible = true,
})

--------------------------------------------------------------------------------

DEFINE_OP(0x20, "add/int", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "register" :: "register", direction = "src" }, --lhs
        { type = "register" :: "register", direction = "src" }, --rhs
    },
})

DEFINE_OP(0x21, "sub/int", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "register" :: "register", direction = "src" }, --lhs
        { type = "register" :: "register", direction = "src" }, --rhs
    },
})

-- fast path for iinc
DEFINE_OP(0x22, "add_literal/int", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "register" :: "register", direction = "src" }, --lhs
        { type = "literal" :: "literal", literal_type = "i32" }, --rhs
    },
})

----------------------------------------------------------------------------

DEFINE_OP(0x40, "jump_if_eq/int", {
    operands = {
        { type = "register" :: "register", direction = "src" }, --lhs
        { type = "register" :: "register", direction = "src" }, --rhs
        { type = "jump_target" },
    },
})

DEFINE_OP(0x41, "jump_if_ne/int", {
    operands = {
        { type = "register" :: "register", direction = "src" }, --lhs
        { type = "register" :: "register", direction = "src" }, --rhs
        { type = "jump_target" },
    },
})

DEFINE_OP(0x42, "jump_if_lt/int", {
    operands = {
        { type = "register" :: "register", direction = "src" }, --lhs
        { type = "register" :: "register", direction = "src" }, --rhs
        { type = "jump_target" },
    },
})

DEFINE_OP(0x43, "jump_if_ge/int", {
    operands = {
        { type = "register" :: "register", direction = "src" }, --lhs
        { type = "register" :: "register", direction = "src" }, --rhs
        { type = "jump_target" },
    },
})

DEFINE_OP(0x44, "jump_if_gt/int", {
    operands = {
        { type = "register" :: "register", direction = "src" }, --lhs
        { type = "register" :: "register", direction = "src" }, --rhs
        { type = "jump_target" },
    },
})

DEFINE_OP(0x45, "jump_if_le/int", {
    operands = {
        { type = "register" :: "register", direction = "src" }, --lhs
        { type = "register" :: "register", direction = "src" }, --rhs
        { type = "jump_target" },
    },
})

DEFINE_OP(0x46, "jump_if_eq/ref", {
    operands = {
        { type = "register" :: "register", direction = "src" }, --lhs
        { type = "register" :: "register", direction = "src" }, --rhs
        { type = "jump_target" },
    },
})

DEFINE_OP(0x50, "jump", {
    operands = {
        { type = "jump_target" },
    },
})

--------------------------------------------------------------------------------

DEFINE_OP(0x60, "get_field", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "register" :: "register", direction = "src" }, -- object
        { type = "constant" }, -- field
    },
    fallible = true,
})

DEFINE_OP(0x61, "set_field", {
    operands = {
        { type = "register" :: "register", direction = "dst" }, -- object
        { type = "register" :: "register", direction = "src" }, -- value
        { type = "constant" }, -- field
    },
    fallible = true,
})

DEFINE_OP(0x62, "get_static", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "constant" },
    },
    fallible = true,
})

DEFINE_OP(0x63, "set_static", {
    operands = {
        { type = "register" :: "register", direction = "src" },
        { type = "constant" },
    },
    fallible = true,
})

--------------------------------------------------------------------------------

DEFINE_OP(0x70, "new", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "constant" },
    },
    fallible = true,
})

DEFINE_OP(0x71, "throw", {
    operands = {
        { type = "register" :: "register", direction = "src" },
    },
    fallible = true,
})

--------------------------------------------------------------------------------

DEFINE_OP(0x80, "invoke", {
    operands = {
        { type = "register" :: "register", direction = "dst" },
        { type = "constant" },
        { type = "register_block" :: "register_block" },
        { type = "dispatch_type" },
    },
    breaks = true,
    fallible = true,
})

DEFINE_OP(0x81, "return", {
    operands = {
        { type = "register" :: "register", direction = "src" },
    },
    breaks = true,
})

--------------------------------------------------------------------------------

return INSTRUCTIONS
