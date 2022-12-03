package main

import "core:fmt"

OpCode :: enum u8 {
    CONSTANT,
    NIL,
    TRUE,
    FALSE,
    POP,
    GET_LOCAL,
    SET_LOCAL,
    GET_GLOBAL,
    DEFINE_GLOBAL,
    SET_GLOBAL,
    GET_UPVALUE,
    SET_UPVALUE,
    EQUAL,
    GREATER,
    LESS,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    NOT,
    NEGATE,
    PRINT,
    JUMP,
    JUMP_IF_FALSE,
    LOOP,
    CALL,
    CLOSURE,
    CLOSE_UPVALUE,
    RETURN,
}

Chunk :: struct {
    code: [dynamic]u8,
    lines: [dynamic]int,
    constants: [dynamic]Value,
}

freeChunk :: proc(c: ^Chunk) {
    delete(c.code)
    delete(c.constants)
}

@(private = "file")
writeChunk_proc :: proc(c: ^Chunk, byte: u8, line: int) {
    if DEBUG_STRESS_GC {
        collectGarbage()
    }
    append(&c.code, byte)
    append(&c.lines, line)
} 

@(private = "file")
writeChunk_OpCode :: proc(c: ^Chunk, op: OpCode, line: int) {
    writeChunk_proc(c, cast(u8)op, line)
}

@(private = "file")
writeChunk_Int :: proc(c: ^Chunk, i: int, line: int) {
    writeChunk_proc(c, cast(u8)i, line)
}

writeChunk_byte :: proc(c: ^Chunk, byte: u8, line: int) {
    writeChunk_proc(c, byte, line)
}

writeChunk :: proc {
    writeChunk_OpCode,
    writeChunk_Int,
    writeChunk_byte,
}

addConstant :: proc(c: ^Chunk, value: Value) -> int {
    if DEBUG_STRESS_GC {
        collectGarbage()
    }
    push(value)
    append(&c.constants, value)
    pop()
    return len(c.constants) - 1
}
