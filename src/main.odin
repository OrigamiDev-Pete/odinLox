package main

import "core:fmt"
import "core:mem"
import "core:time"

main :: proc() {
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	initVM()
	defer(freeVM())

	chunk: Chunk
	defer(freeChunk(&chunk))

	using OpCode {
		constant := addConstant(&chunk, 1.2)
		writeChunk(&chunk, OP_CONSTANT, 123)
		writeChunk(&chunk, constant, 123)

		constant = addConstant(&chunk, 3.4)
		writeChunk(&chunk, OP_CONSTANT, 123)
		writeChunk(&chunk, constant, 123)
		
		writeChunk(&chunk, OP_ADD, 123)

		constant = addConstant(&chunk, 5.6)
		writeChunk(&chunk, OP_CONSTANT, 123)
		writeChunk(&chunk, constant, 123)

		writeChunk(&chunk, OP_DIVIDE, 123)
		writeChunk(&chunk, OP_NEGATE, 123)

		writeChunk(&chunk, OP_RETURN, 123)
	}

	interpret(chunk)

}
