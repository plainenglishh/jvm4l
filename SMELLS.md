# code smells

this document is a slightly rambly list of 'code smells' within this project to
consider fixing later on.

## needs improvement

- !!! testing is very lackluster
- fuzzy distinction between what types are 'metadata' and what are 
  'live objects'
- fuzzy distinction between when classes (and methods) are loaded, linked 
  and initialised. should a class be entirely linked when one if it's 
  methods is linked? think `Lazy` might be an anti pattern that encourages
  this.
- documentation is outdated. consider working on this first to get a clearer
  picture of how the system should operate
- cant tell when a certain component is 'done', consider an improved TODO with
  completion conditions + completed components need tests
- unsure of when something should be a class. i like having public APIs as
  classes, but internals should be POT, and im not sure where that distinction
  should lie. internals never need serialising, trying data with behaviour is
  okay, if not good, in most cases here?
- descriptor parsing and typechecking is confusing right now. probably due to
  the linking issues stated above.
- lots of components have been left to rot. havent done anything with scheduling
  or gc.
- can i move typechecking to transpilation in a verification pass? remove 
  runtime checks entirely? still need it for native ofc
- jvm configuration STINKS.
- need nicer way to patch the JCL for runtime specific functionality. a module
  system would be cool too, tying classfiles with native functions, but does 
  diverge too much from real JVMs?

## going well

- happy with the IR format and the execution model