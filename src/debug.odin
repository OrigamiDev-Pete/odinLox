package main

import "core:fmt"

disassembleChunk :: proc(chunk: Chunk, name: string) {
    fmt.printf("== %s ==\n", name)

    for offset := 0; offset < len(chunk.code); {
        offset = disassembleInstruction(chunk, offset)
    }
}

disassembleInstruction :: proc(chunk: Chunk, offset: int) -> int {
    fmt.printf("%04d ", offset)
    if offset > 0 && chunk.lines[offset] == chunk.lines[offset - 1] {
        fmt.printf("   | ")
    } else {
        fmt.printf("%4d ", chunk.lines[offset])
    }

    instruction := cast(OpCode)chunk.code[offset]
    switch instruction {
    case .OP_RETURN:
        return simpleInstruction(.OP_RETURN, offset)
    case .OP_CONSTANT:
        return constantInstruction(.OP_CONSTANT, chunk, offset)
    case: // default
        return offset + 1
    }
}

@private
simpleInstruction :: proc(name: OpCode, offset: int) -> int {
    fmt.println(name)
    return offset + 1
}

@private
constantInstruction :: proc(name: OpCode, chunk: Chunk, offset: int) -> int {
    constant := chunk.code[offset + 1]
    fmt.printf("%s    %v '", name, constant)
    printValue(chunk.constants[constant])
    fmt.printf("'\n")
    return offset + 2
}