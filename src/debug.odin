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
    case .RETURN:
        return simpleInstruction(.RETURN, offset)
    case .CONSTANT:
        return constantInstruction(.CONSTANT, chunk, offset)
    case .NIL:
        return simpleInstruction(.NIL, offset)
    case .TRUE:
        return simpleInstruction(.TRUE, offset)
    case .FALSE:
        return simpleInstruction(.FALSE, offset)
    case .EQUAL:
        return simpleInstruction(.EQUAL, offset)
    case .GREATER:
        return simpleInstruction(.GREATER, offset)
    case .LESS:
        return simpleInstruction(.LESS, offset)
    case .ADD:
        return simpleInstruction(.ADD, offset)
    case .SUBTRACT:
        return simpleInstruction(.SUBTRACT, offset)
    case .MULTIPLY:
        return simpleInstruction(.MULTIPLY, offset)
    case .DIVIDE:
        return simpleInstruction(.DIVIDE, offset)
    case .NOT:
        return simpleInstruction(.NOT, offset)
    case .NEGATE:
        return simpleInstruction(.NEGATE, offset)
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