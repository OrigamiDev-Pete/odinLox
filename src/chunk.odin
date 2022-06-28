package main

import "core:fmt"

OpCode :: enum u8 {
    OP_CONSTANT,
    OP_RETURN,
}

Chunk :: struct {
    code: [dynamic]u8,
    lines: [dynamic]int,
    constants: [dynamic]Value,
}

freeChunk :: proc(c: Chunk) {
    delete(c.code)
    delete(c.constants)
}

writeChunk :: proc(c: ^Chunk, byte: u8, line: int) {
    append(&c.code, byte)
    append(&c.lines, line)
}

addConstant :: proc(c: ^Chunk, value: Value) -> int {
    append(&c.constants, value)
    return len(c.constants) - 1
}