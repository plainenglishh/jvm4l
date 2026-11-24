# Jvm4L

An experimental pure-Luau implementation of a Java 8 Virtual Machine.

> [!WARNING]
> Use for experimentation only. The vast majority of features are unimplemented. 
> For the love of god, please do not use this in serious projects.

> [!CAUTION]
> Jvm4L currently lacks a bytecode verifier. Only use classfiles you trust, or 
> those generated using an official Java compiler.

## About

The purpose of this repository is to document my progress. 

While I hope to eventually complete a JVM capable of executing most Java 
programs, a production-grade JVM is not the goal. Regardless of how many 
features are implemented, this project is intended for experimental and hobby 
use only.

Jvm4L supports two modes of execution:
1. Interpreted mode, using a Java bytecode -> Jvm4L IR transpiler; and
2. JIT mode, using a Jvm4L -> Luau source compiler, although this 
relies on a host provided `load` function.

Currently, a 1m `i++` iteration loop (see `jcl/src/jvm4l/test/Test.java`) takes 
~100ms in interpreted mode, and ~50ms in JIT mode on my Ryzen 5 4500 using Lute.
On some runtimes, such as Seal, JIT mode takes ~20ms, which I assume is due
to how `@native` is handled in different runtimes' `load` implementation.

Experimental optimising passes for both the IR transpiler and the JIT compiler
are in the works.

Testing and general JVMS compliance is in a bit of a dire state, although 
workloads supported by the implemented instruction set and the broader object 
model work mostly okay.

## Contributing

As this is a personal hobby project, I am not currently accepting code 
contributions.

However, If you spot a flaw, missed edge case or missed JVMS compliance that 
isn't covered in my TODO, or have general advice, I would greatly appreciate
a heads-up by way of a GitHub issue or Discord message (`@plainenglish`).

## Licence

This project does not yet have an official licence, and is provided "as is" 
without warranty of any kind.

I personally don't mind if you tinker with the code privately, but no general
permission is granted to redistribute or publicly publish modified versions of 
the source code.

I hope to move to an open-source licence once the project has matured.
