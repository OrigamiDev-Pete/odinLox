package main

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:log"
import "core:mem"
import "core:os"
import "core:time"

main :: proc() {
	context.logger = log.create_console_logger()

	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	initVM()
	defer(freeVM())

	if (len(os.args) == 1) {
		repl()
	} else if (len(os.args) == 2) {
		runFile(os.args[1])	
	} else {
		fmt.println("Usage: olox [path]")
		os.exit(64)
	}
}

repl :: proc() {
	line: [1024]u8
	reader: bufio.Reader
	bufio.reader_init_with_buf(&reader, io.to_reader(os.stream_from_handle(os.stdin)), line[:])
	for {
		fmt.printf("> ")

		line, err := bufio.reader_read_slice(&reader, '\n')
		if err != nil {
			fmt.println(err)
			break;
		}
		interpret(string(line[:]))
	}
}

runFile :: proc(path: string) {
	fmt.println(os.get_current_directory())
	source, success := os.read_entire_file(path)
	if (!success) {
		fmt.printf("Could not open file \"%v\".\n", path)
		os.exit(74)
	}
	defer delete(source)
	result := interpret(string(source[:]))

	if result == InterpretResult.COMPILE_ERROR { os.exit(65) }
	if result == InterpretResult.RUNTIME_ERROR { os.exit(70) }

}