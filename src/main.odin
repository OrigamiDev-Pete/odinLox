package main

import "core:fmt"

main :: proc() {
	initVM()
	defer(freeVM())

	chunk: Chunk
	defer(freeChunk(chunk))

	constant := addConstant(&chunk, 1.2)
	writeChunk(&chunk, cast(u8)OpCode.OP_CONSTANT, 123)
	writeChunk(&chunk, cast(u8)constant, 123)

	writeChunk(&chunk, cast(u8)OpCode.OP_RETURN, 123)

	disassembleChunk(chunk, "test chunk")
	interpret(chunk)


}
