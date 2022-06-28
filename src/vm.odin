package main

import "core:fmt"

VM :: struct {
    chunk: Chunk,
    ip: []u8,
}

InterpretResult :: enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
}

vm: VM

initVM :: proc() {

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
        instruction := cast(OpCode) readByte()
        #partial switch instruction {
            case .OP_RETURN:
                return .INTERPRET_OK
            case .OP_CONSTANT:
                constant := readConstant()
                printValue(constant)
                fmt.println()
        }
    }
}

readByte :: proc() -> (b: u8) {
    b = vm.ip[0]
    vm.ip = vm.ip[1:]
    return
}

readConstant :: proc() -> Value {
    return vm.chunk.constants[readByte()]
}