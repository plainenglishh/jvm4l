# Jvm4L IR

## Purpose

This document sets out the Jvm4L Intermediate Representation (the 'IR'), as well
as the abstract machine used to execute it.

## The IR

Rather than executing Java bytecode directly, Jvm4L transpiles Java bytecode 
into an IR better suited for optimised Luau interpretation and JIT compilation
to Luau source.

The intent of transpilation is to:
1. eliminate stack overhead with stack -> register mapping;
2. eliminate java-quirks at odds with Luau, e.g. endianness, absolute jump 
   targets, 1/2 slot distinction;
3. simplify instructions;
4. enable transpile-time optimisations;
5. simplify jit-compiler implementation;
6. reduce runtime typechecking and assertions in lieu of a proper verification 
   pass;
7. reduce runtime field/method/constant resolution overhead.

The IR is register based and maps the Java operand stack and locals variables 
into a single slot register space. Each IR register holds a single value, 
including `long` and `double`.

All register operands use a 16-bit encoding, allowing a maximum of 65,536 
addressable registers. Jvm4L rejects methods whose required register space 
exceeds this limit. Actual registers begin at 1, as `R0` is reserved for a 
'zero' register (0, or null, depending on context) for instructions like 
`compare_eq`.

The instruction set is defined in `src/lib/ir/instructions.luau`. The IR is not
to be used for precompilation as the IR format can be changed at any time.