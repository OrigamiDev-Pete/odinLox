package main

import "core:fmt"

OpCode :: enum u8 {
    CONSTANT,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    NEGATE,
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

@private
writeChunk_proc :: proc(c: ^Chunk, byte: u8, line: int) {
    append(&c.code, byte)
    append(&c.lines, line)
} 

@private
writeChunk_OpCode :: proc(c: ^Chunk, op: OpCode, line: int) {
    writeChunk_proc(c, cast(u8)op, line)
}

@private
writeChunk_Int :: proc(c: ^Chunk, i: int, line: int) {
    writeChunk_proc(c, cast(u8)i, line)
}

writeChunk :: proc {
    writeChunk_OpCode,
    writeChunk_Int,
}

addConstant :: proc(c: ^Chunk, value: Value) -> int {
    append(&c.constants, value)
    return len(c.constants) - 1
}
