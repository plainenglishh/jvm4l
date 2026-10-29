# Opcodes

This document lists the currently implemented opcodes, as well as considerations 
for implementing opcodes in both the interpreter and the JIT compiler.

Note: this document does not pertain to native methods, which are currently 
deemed atomic (i.e, do not break under any circumstances, and invoke methods 
synchronously).

## Implementing the Interpreter/JIT loops and Opcodes

### Stepping, Bursts, and Breaks

Jvm4L executes instructions in bursts (a 'step') in both interpreted mode and 
JIT mode.

Events that modify the stack or signal a scheduler condition must 'break' out of
the burst to allow the executor to begin executing a new frame, return from the
current frame, or reschedule on budget exhaustion/memory contention.

The full list of events that require a step break is:-
1. budget exhaustion, which may be checked before every instruction, or at a 
branch;
2. inline method invocations (excluding class initialisers and bootstrap 
methods, which are invoked synchronously below the step) and method returns;
3. thread synchronisation, which may be implemented within `monitor` and 
`monitorexit`.

## Implemented Opcodes

Len - Instruction length in bytes, or `?` if variable
Bra - Instruction can branch (excluding athrow, returns and invocations)
Int - Implemented in interpreter
Jit - Implemented in JIT
Brk - Instruction should break from a burst (S = Synchronisation, R = Method Return, I = Inline Method Invocation)

| Opcode(s)     | Mnemonic          | Len | Bra | Int | Jit | Brk |
|:--------------|:------------------|:----|:---:|:---:|:---:|:---:|
| `0x00`        | `nop`             | 1   |     |  X  |     |     |
| `0x01`        | `aconst_null`     | 1   |     |  X  |     |     |
| `0x02`-`0x08` | `iconst_<n>`      | 1   |     |  X  |     |     |
| `0x09`-`0x0A` | `lconst_<n>`      | 1   |     |  X  |     |     |
| `0x0B`-`0x0D` | `fconst_<n>`      | 1   |     |  X  |     |     |
| `0x0E`-`0x0F` | `dconst_<n>`      | 1   |     |  X  |     |     |
| `0x10`        | `bipush`          | 2   |     |  X  |     |     |
| `0x11`        | `sipush`          | 3   |     |  X  |     |     |
| `0x12`        | `ldc`             | 2   |     |  X  |     |     |
| `0x13`        | `ldc_w`           | 3   |     |     |     |     |
| `0x14`        | `ldc2_w`          | 3   |     |     |     |     |
| `0x15`        | `iload`           | 2   |     |     |     |     |
| `0x16`        | `lload`           | 2   |     |     |     |     |
| `0x17`        | `fload`           | 2   |     |     |     |     |
| `0x18`        | `dload`           | 2   |     |     |     |     |
| `0x19`        | `aload`           | 2   |     |     |     |     |
| `0x1A`-`0x1D` | `iload_<n>`       | 1   |     |  X  |     |     |
| `0x1E`-`0x21` | `lload_<n>`       | 1   |     |     |     |     |
| `0x22`-`0x25` | `fload_<n>`       | 1   |     |     |     |     |
| `0x26`-`0x29` | `dload_<n>`       | 1   |     |     |     |     |
| `0x2A`-`0x2D` | `aload_<n>`       | 1   |     |  X  |     |     |
| `0x2E`        | `iaload`          | 1   |     |     |     |     |
| `0x2F`        | `laload`          | 1   |     |     |     |     |
| `0x30`        | `faload`          | 1   |     |     |     |     |
| `0x31`        | `daload`          | 1   |     |     |     |     |
| `0x32`        | `aaload`          | 1   |     |     |     |     |
| `0x33`        | `baload`          | 1   |     |     |     |     |
| `0x34`        | `caload`          | 1   |     |     |     |     |
| `0x35`        | `saload`          | 1   |     |     |     |     |
| `0x36`        | `istore`          | 2   |     |     |     |     |
| `0x37`        | `lstore`          | 2   |     |     |     |     |
| `0x38`        | `fstore`          | 2   |     |     |     |     |
| `0x39`        | `dstore`          | 2   |     |     |     |     |
| `0x3A`        | `astore`          | 2   |     |     |     |     |
| `0x3B`-`0x3E` | `istore_<n>`      | 1   |     |  X  |     |     |
| `0x3F`-`0x42` | `lstore_<n>`      | 1   |     |     |     |     |
| `0x43`-`0x46` | `fstore_<n>`      | 1   |     |     |     |     |
| `0x47`-`0x4A` | `dstore_<n>`      | 1   |     |     |     |     |
| `0x4B`-`0x4E` | `astore_<n>`      | 1   |     |     |     |     |
| `0x4F`        | `iastore`         | 1   |     |     |     |     |
| `0x50`        | `lastore`         | 1   |     |     |     |     |
| `0x51`        | `fastore`         | 1   |     |     |     |     |
| `0x52`        | `dastore`         | 1   |     |     |     |     |
| `0x53`        | `aastore`         | 1   |     |     |     |     |
| `0x54`        | `bastore`         | 1   |     |     |     |     |
| `0x55`        | `castore`         | 1   |     |     |     |     |
| `0x56`        | `sastore`         | 1   |     |     |     |     |
| `0x57`        | `pop`             | 1   |     |     |     |     |
| `0x58`        | `pop2`            | 1   |     |     |     |     |
| `0x59`        | `dup`             | 1   |     |  X  |     |     |
| `0x5A`        | `dup_x1`          | 1   |     |     |     |     |
| `0x5B`        | `dup_x2`          | 1   |     |     |     |     |
| `0x5C`        | `dup2`            | 1   |     |     |     |     |
| `0x5D`        | `dup2_x1`         | 1   |     |     |     |     |
| `0x5E`        | `dup2_x2`         | 1   |     |     |     |     |
| `0x5F`        | `swap`            | 1   |     |     |     |     |
| `0x60`        | `iadd`            | 1   |     |  X  |     |     |
| `0x61`        | `ladd`            | 1   |     |     |     |     |
| `0x62`        | `fadd`            | 1   |     |     |     |     |
| `0x63`        | `dadd`            | 1   |     |     |     |     |
| `0x64`        | `isub`            | 1   |     |  X  |     |     |
| `0x65`        | `lsub`            | 1   |     |     |     |     |
| `0x66`        | `fsub`            | 1   |     |     |     |     |
| `0x67`        | `dsub`            | 1   |     |     |     |     |
| `0x68`        | `imul`            | 1   |     |     |     |     |
| `0x69`        | `lmul`            | 1   |     |     |     |     |
| `0x6A`        | `fmul`            | 1   |     |     |     |     |
| `0x6B`        | `dmul`            | 1   |     |     |     |     |
| `0x6C`        | `idiv`            | 1   |     |     |     |     |
| `0x6D`        | `ldiv`            | 1   |     |     |     |     |
| `0x6E`        | `fdiv`            | 1   |     |     |     |     |
| `0x6F`        | `ddiv`            | 1   |     |     |     |     |
| `0x70`        | `irem`            | 1   |     |     |     |     |
| `0x71`        | `lrem`            | 1   |     |     |     |     |
| `0x72`        | `frem`            | 1   |     |     |     |     |
| `0x73`        | `drem`            | 1   |     |     |     |     |
| `0x74`        | `ineg`            | 1   |     |     |     |     |
| `0x75`        | `lneg`            | 1   |     |     |     |     |
| `0x76`        | `fneg`            | 1   |     |     |     |     |
| `0x77`        | `dneg`            | 1   |     |     |     |     |
| `0x78`        | `ishl`            | 1   |     |     |     |     |
| `0x79`        | `lshl`            | 1   |     |     |     |     |
| `0x7A`        | `ishr`            | 1   |     |     |     |     |
| `0x7B`        | `lshr`            | 1   |     |     |     |     |
| `0x7C`        | `iushr`           | 1   |     |     |     |     |
| `0x7D`        | `lushr`           | 1   |     |     |     |     |
| `0x7E`        | `iand`            | 1   |     |     |     |     |
| `0x7F`        | `land`            | 1   |     |     |     |     |
| `0x80`        | `ior`             | 1   |     |     |     |     |
| `0x81`        | `lor`             | 1   |     |     |     |     |
| `0x82`        | `ixor`            | 1   |     |     |     |     |
| `0x83`        | `lxor`            | 1   |     |     |     |     |
| `0x84`        | `iinc`            | 3   |     |  X  |     |     |
| `0x85`        | `i2l`             | 1   |     |     |     |     |
| `0x86`        | `i2f`             | 1   |     |     |     |     |
| `0x87`        | `i2d`             | 1   |     |     |     |     |
| `0x88`        | `l2i`             | 1   |     |     |     |     |
| `0x89`        | `l2f`             | 1   |     |     |     |     |
| `0x8A`        | `l2d`             | 1   |     |     |     |     |
| `0x8B`        | `f2i`             | 1   |     |     |     |     |
| `0x8C`        | `f2l`             | 1   |     |     |     |     |
| `0x8D`        | `f2d`             | 1   |     |     |     |     |
| `0x8E`        | `d2i`             | 1   |     |     |     |     |
| `0x8F`        | `d2l`             | 1   |     |     |     |     |
| `0x90`        | `d2f`             | 1   |     |     |     |     |
| `0x91`        | `i2b`             | 1   |     |     |     |     |
| `0x92`        | `i2c`             | 1   |     |     |     |     |
| `0x93`        | `i2s`             | 1   |     |     |     |     |
| `0x94`        | `lcmp`            | 1   |     |     |     |     |
| `0x95`        | `fcmpl`           | 1   |     |     |     |     |
| `0x96`        | `fcmpg`           | 1   |     |     |     |     |
| `0x97`        | `dcmpl`           | 1   |     |     |     |     |
| `0x98`        | `dcmpg`           | 1   |     |     |     |     |
| `0x99`-`0x9E` | `if<cond>`        | 3   |  X  |  X  |     |     |
| `0x9F`-`0xA4` | `if_icmp<cond>`   | 3   |  X  |  X  |     |     |
| `0xA5`-`0xA6` | `if_acmp<cond>`   | 3   |  X  |     |     |     |
| `0xA7`        | `goto`            | 3   |  X  |  X  |     |     |
| `0xA8`        | `jsr`             | 3   |  X  |     |     |     |
| `0xA9`        | `ret`             | 2   |  X  |     |     |     |
| `0xAA`        | `tableswitch`     | ?   |  X  |     |     |     |
| `0xAB`        | `lookupswitch`    | ?   |  X  |     |     |     |
| `0xAC`        | `ireturn`         | 1   |     |  X  |     |  R  |
| `0xAD`        | `lreturn`         | 1   |     |  X  |     |  R  |
| `0xAE`        | `freturn`         | 1   |     |  X  |     |  R  |
| `0xAF`        | `dreturn`         | 1   |     |  X  |     |  R  |
| `0xB0`        | `areturn`         | 1   |     |  X  |     |  R  |
| `0xB1`        | `return`          | 1   |     |  X  |     |  R  |
| `0xB2`        | `getstatic`       | 3   |     |  X  |     |     |
| `0xB3`        | `putstatic`       | 3   |     |  X  |     |     |
| `0xB4`        | `getfield`        | 3   |     |  X  |     |     |
| `0xB5`        | `putfield`        | 3   |     |  X  |     |     |
| `0xB6`        | `invokevirtual`   | 3   |     |  X  |     |  I  |
| `0xB7`        | `invokespecial`   | 3   |     |  X  |     |  I  |
| `0xB8`        | `invokestatic`    | 3   |     |  X  |     |  I  |
| `0xB9`        | `invokeinterface` | 5   |     |     |     |  I  |
| `0xBA`        | `invokedynamic`   | 5   |     |     |     |  I  |
| `0xBB`        | `new`             | 3   |     |  X  |     |     |
| `0xBC`        | `newarray`        | 2   |     |     |     |     |
| `0xBD`        | `anewarray`       | 3   |     |     |     |     |
| `0xBE`        | `arraylength`     | 1   |     |     |     |     |
| `0xBF`        | `athrow`          | 1   |     |  X  |     |     |
| `0xC0`        | `checkcast`       | 3   |     |     |     |     |
| `0xC1`        | `instanceof`      | 3   |     |     |     |     |
| `0xC2`        | `monitorenter`    | 1   |     |     |     |  S  |
| `0xC3`        | `monitorexit`     | 1   |     |     |     |  S  |
| `0xC4`        | `wide`            | 1   |     |  X  |     |     |
| `0xC5`        | `multianewarray`  | 4   |     |     |     |     |
| `0xC6`        | `ifnull`          | 3   |  X  |     |     |     |
| `0xC7`        | `ifnonnull`       | 3   |  X  |     |     |     |
| `0xC8`        | `goto_w`          | 5   |  X  |     |     |     |
| `0xC9`        | `jsr_w`           | 5   |  X  |     |     |     |
| `0xCA`        | `breakpoint`      | 1   |     |     |     |     |
| `0xCB`-`0xFD` | Reserved          | -   |     |     |     |     |
| `0xFE`        | `impdep1`         | -   |  -  |     |     |     |
| `0xFF`        | `impdep2`         | -   |  -  |     |     |     |
