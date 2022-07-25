package main

import "core:fmt"
import "core:log"

DEBUG_STACK_TRACE :: false
STACK_MAX :: 256

VM :: struct {
    chunk: Chunk,
    ip: []u8,
    stack: [STACK_MAX]Value,
    stackIndex: i32,
}

InterpretResult :: enum {
    OK,
    COMPILE_ERROR,
    RUNTIME_ERROR,
}

vm: VM

initVM :: proc() {
    resetStack()
}

freeVM :: proc() {

}

interpret :: proc(source: string) -> InterpretResult {
	chunk: Chunk
	defer freeChunk(&chunk)

	if !compile(source, &chunk) {
		return .COMPILE_ERROR
	}

	vm.chunk = chunk
	vm.ip = vm.chunk.code[:]

	return run()
}

run :: proc() -> InterpretResult {
    for {
        when DEBUG_STACK_TRACE {
            log.debugf("          ")
            for i in 0..<vm.stackIndex {
                log.debugf("[ ")
                printValue(vm.stack[i])
                log.debugf(" ]")
            }
            fmt.println()
            disassembleInstruction(vm.chunk,  len(vm.chunk.code) - len(vm.ip))
        }

        instruction := cast(OpCode) readByte()
        switch instruction {
            case .RETURN:
                printValue(pop())
                fmt.println()
                return .OK

            case .ADD:
                b := pop()
                a := pop()
                push(a + b)

            case .SUBTRACT:
                b := pop()
                a := pop()
                push(a - b)

            case .MULTIPLY:
                b := pop()
                a := pop()
                push(a * b)

            case .DIVIDE:
                b := pop()
                a := pop()
                push(a / b)

            case .NEGATE:
                vm.stack[vm.stackIndex-1] = -vm.stack[vm.stackIndex-1]

            case .CONSTANT:
                constant := readConstant()
                push(constant)
        }
    }
}

push :: proc(value: Value) {
    vm.stack[vm.stackIndex] = value
    vm.stackIndex += 1
}

pop :: proc() ->  Value {
    vm.stackIndex -= 1
    return vm.stack[vm.stackIndex]
}

@private
readByte :: proc() -> (b: u8) {
    b = vm.ip[0]
    vm.ip = vm.ip[1:]
    return
}

@private
readConstant :: proc() -> Value {
    return vm.chunk.constants[readByte()]
}

@private
resetStack :: proc() {
    vm.stackIndex = 0
}
