package main

import "core:fmt"
import "core:strings"

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
    case .OP_ADD:
        return simpleInstruction(.OP_ADD, offset)
    case .OP_SUBTRACT:
        return simpleInstruction(.OP_SUBTRACT, offset)
    case .OP_MULTIPLY:
        return simpleInstruction(.OP_MULTIPLY, offset)
    case .OP_DIVIDE:
        return simpleInstruction(.OP_DIVIDE, offset)
    case .OP_NEGATE:
        return simpleInstruction(.OP_NEGATE, offset)
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
    buf: [32]u8
    name_str := fmt.bprintf(buf[:], "%v", name)
    fmt.printf("%-16v %v '", name_str, constant)
    printValue(chunk.constants[constant])
    fmt.printf("'\n")
    return offset + 2
}