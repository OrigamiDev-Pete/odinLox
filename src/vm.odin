package main

import "core:fmt"


DEBUG_STACK_TRACE :: false
STACK_MAX :: 256

VM :: struct {
    chunk: Chunk,
    ip: []u8,
    stack: [STACK_MAX]Value,
    stackIndex: i32,
}

InterpretResult :: enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
}

vm: VM

initVM :: proc() {
    resetStack()
}

freeVM :: proc() {

}

interpret :: proc(chunk: Chunk) -> InterpretResult {
    vm.chunk = chunk
    vm.ip = vm.chunk.code[:]
    return run()
}

run :: proc() -> InterpretResult {
    for {
        when DEBUG_STACK_TRACE {
            fmt.printf("          ")
            for i in 0..<vm.stackIndex {
                fmt.printf("[ ")
                printValue(vm.stack[i])
                fmt.printf(" ]")
            }
            fmt.println()
            disassembleInstruction(vm.chunk,  len(vm.chunk.code) - len(vm.ip))
        }

        instruction := cast(OpCode) readByte()
        switch instruction {
            case .OP_RETURN:
                printValue(pop())
                fmt.println()
                return .INTERPRET_OK

            case .OP_ADD:
                b := pop()
                a := pop()
                push(a + b)

            case .OP_SUBTRACT:
                b := pop()
                a := pop()
                push(a - b)

            case .OP_MULTIPLY:
                b := pop()
                a := pop()
                push(a * b)

            case .OP_DIVIDE:
                b := pop()
                a := pop()
                push(a / b)

            case .OP_NEGATE:
                vm.stack[vm.stackIndex-1] = -vm.stack[vm.stackIndex-1]

            case .OP_CONSTANT:
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