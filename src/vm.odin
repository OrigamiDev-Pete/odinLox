package main

import "core:fmt"
import "core:log"

DEBUG_STACK_TRACE :: true
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
            case .RETURN:
                printValue(pop())
                fmt.println()
                return .OK

            case .CONSTANT:
                constant := readConstant()
                push(constant)

            case .NIL: push(Value{.NIL, nil})
            case .TRUE: push(Value{.BOOL, true})
            case .FALSE: push(Value{.BOOL, false})

            case .EQUAL:
                b := pop()
                a := pop()
                push(Value{ .BOOL, valuesEqual(a, b) })

            case .GREATER:
                checkNumbers() or_return
                b := pop()
                a := pop()
                push(Value{ .BOOL, a.variant.(f64) > b.variant.(f64) })

            case .LESS:
                checkNumbers() or_return
                b := pop()
                a := pop()
                push(Value{ .BOOL, a.variant.(f64) < b.variant.(f64) })


            case .ADD:
                checkNumbers() or_return
                b := pop()
                a := pop()
                a.variant = a.variant.(f64) + b.variant.(f64)
                push(a)

            case .SUBTRACT:
                checkNumbers() or_return
                b := pop()
                a := pop()
                a.variant = a.variant.(f64) - b.variant.(f64)
                push(a)

            case .MULTIPLY:
                checkNumbers() or_return
                b := pop()
                a := pop()
                a.variant = a.variant.(f64) * b.variant.(f64)
                push(a)

            case .DIVIDE:
                checkNumbers() or_return
                b := pop()
                a := pop()
                a.variant = a.variant.(f64) / b.variant.(f64)
                push(a)

            case .NOT:
                push(Value{.BOOL, isFalsey(pop())})

            case .NEGATE:
                if peek(0).type != .NUMBER {
                    runtimeError("Operand must be a number.")
                    return .RUNTIME_ERROR
                }
                vm.stack[vm.stackIndex-1].variant = -vm.stack[vm.stackIndex-1].variant.(f64)
        }
    }
}

checkNumbers :: proc() -> InterpretResult {
    if peek(0).type != .NUMBER || peek(1).type != .NUMBER {
        runtimeError("Operands must be numbers.")
        return .RUNTIME_ERROR
    }
    return nil
}

push :: proc(value: Value) {
    vm.stack[vm.stackIndex] = value
    vm.stackIndex += 1
}

pop :: proc() ->  Value {
    vm.stackIndex -= 1
    return vm.stack[vm.stackIndex]
}

peek :: proc(distance: i32) -> Value {
    return vm.stack[vm.stackIndex - 1 - distance]
}

isFalsey :: proc(value: Value) -> bool {
    return value.type == .NIL || (value.type == .BOOL && !value.variant.(bool))
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

runtimeError :: proc(format: string, args: ..any) {
    log.errorf(format, ..args)
    // log.error()

    instruction_index := len(vm.chunk.code) - len(vm.ip) - 1
    line := vm.chunk.lines[instruction_index]
    log.errorf("[line %v] in script\n", line)
    resetStack()
}
