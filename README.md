# odinLox
An implementation of a Lox bytecode virtual machine and compiler based on Robert Nystrom's Crafting Interpreters written in the [Odin Programming Language](https://odin-lang.org/).

The language is complete, including modulo and NaN Boxing optimizations.

## Usage - Windows
To build and run the VM, simply run:
```
.\run
```

## Usage - Other
I've not included build scripts for other platforms but provided you have an Odin compiler you can run:
```
odin build src -out:lox.exe -opt:3
```
This will produce an executable for your platform.
