//+private
package main

import "core:fmt"

disassembleChunk :: proc(chunk: Chunk, name: string) {
    fmt.printf("== %s ==\n", name)

    offset := 0; 
    for offset < len(chunk.code) {
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
    case .CONSTANT:
        return constantInstruction(.CONSTANT, chunk, offset)
    case .NIL:
        return simpleInstruction(.NIL, offset)
    case .TRUE:
        return simpleInstruction(.TRUE, offset)
    case .FALSE:
        return simpleInstruction(.FALSE, offset)
    case .POP:
        return simpleInstruction(.POP, offset)
    case .GET_LOCAL:
        return byteInstruction(.GET_LOCAL, chunk, offset)
    case .SET_LOCAL:
        return byteInstruction(.SET_LOCAL, chunk, offset)
    case .GET_GLOBAL:
        return constantInstruction(.GET_GLOBAL, chunk, offset)
    case .DEFINE_GLOBAL:
        return constantInstruction(.DEFINE_GLOBAL, chunk, offset)
    case .SET_GLOBAL:
        return constantInstruction(.SET_GLOBAL, chunk, offset)
    case .GET_UPVALUE:
        return byteInstruction(.GET_UPVALUE, chunk, offset)
    case .SET_UPVALUE:
        return byteInstruction(.SET_UPVALUE, chunk, offset)
    case .GET_PROPERTY:
        return constantInstruction(.GET_PROPERTY, chunk, offset)
    case .SET_PROPERTY:
        return constantInstruction(.SET_PROPERTY, chunk, offset)
    case .GET_SUPER:
        return constantInstruction(.GET_SUPER, chunk, offset)
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
    case .METHOD:
        return constantInstruction(.METHOD, chunk, offset)
    case .MULTIPLY:
        return simpleInstruction(.MULTIPLY, offset)
    case .DIVIDE:
        return simpleInstruction(.DIVIDE, offset)
    case .NOT:
        return simpleInstruction(.NOT, offset)
    case .NEGATE:
        return simpleInstruction(.NEGATE, offset)
    case .PRINT:
        return simpleInstruction(.PRINT, offset)
    case .JUMP:
        return jumpInstruction(.JUMP, 1, chunk, offset)
    case .JUMP_IF_FALSE:
        return jumpInstruction(.JUMP_IF_FALSE, 1, chunk, offset)
    case .LOOP:
        return jumpInstruction(.LOOP, -1, chunk, offset)
    case .CALL:
        return byteInstruction(.CALL, chunk, offset)
    case .INVOKE:
        return invokeInstruction(.INVOKE, chunk, offset)
    case .SUPER_INVOKE:
        return invokeInstruction(.SUPER_INVOKE, chunk, offset)
    case .CLOSURE:
        offset := offset
        offset += 1
        constant := chunk.code[offset]
        offset += 1
        fmt.printf("%-16s %4d ", "CLOSURE", constant)
        printValue(chunk.constants[constant])
        fmt.println()

        function := cast(^ObjFunction) AS_OBJ(chunk.constants[constant])
        for j in 0..<function.upvalueCount {
            isLocal := bool(chunk.code[offset])
            offset += 1
            index := chunk.code[offset]
            offset += 1
            fmt.printf("%04d    |               %s %d\n", offset - 2, "local" if isLocal else "upvalue", index)
        }
        return offset

    case .CLOSE_UPVALUE:
        return simpleInstruction(.CLOSE_UPVALUE, offset)
    case .RETURN:
        return simpleInstruction(.RETURN, offset)
    case .CLASS:
        return constantInstruction(.CLASS, chunk, offset)
    case .INHERIT:
        return simpleInstruction(.INHERIT, offset)
    case: // default
        return offset + 1
    }
}

@(private = "file")
simpleInstruction :: proc(name: OpCode, offset: int) -> int {
    fmt.println(name)
    return offset + 1
}

@(private = "file")
byteInstruction :: proc(name: OpCode, chunk: Chunk, offset: int) -> int {
    slot := chunk.code[offset + 1]
    buf: [32]u8
    name_str := fmt.bprintf(buf[:], "%v", name)
    fmt.printf("%-16v %v '\n", name_str, slot)
    return offset + 2
}

@(private = "file")
jumpInstruction :: proc(name: OpCode, sign: int, chunk: Chunk, offset: int) -> int {
    jump := u16(chunk.code[offset + 1] << 8)
    jump |= u16(chunk.code[offset + 2])
    fmt.printf("%-16v %4d -> %d\n", name, offset, offset + 3 + sign * int(jump))
    return offset + 3
}

@(private = "file")
constantInstruction :: proc(name: OpCode, chunk: Chunk, offset: int) -> int {
    constant := chunk.code[offset + 1]
    buf: [32]u8
    name_str := fmt.bprintf(buf[:], "%v", name)
    fmt.printf("%-16v %v '", name_str, constant)
    printValue(chunk.constants[constant])
    fmt.printf("'\n")
    return offset + 2
}

invokeInstruction :: proc(name: OpCode, chunk: Chunk, offset: int) -> int {
    constant := chunk.code[offset + 1]
    argCount := chunk.code[offset + 2]
    fmt.printf("%-16v (%v args) %4v '", name, argCount, constant)
    printValue(chunk.constants[constant])
    fmt.println("'")
    return offset + 3
}

