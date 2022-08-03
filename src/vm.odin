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
    strings: Table,
    globals: Table,
    objects: ^Obj,
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
    freeTable(&vm.strings)
    freeTable(&vm.globals)
    freeObjects()
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
            case .CONSTANT:
                constant := readConstant()
                push(constant)

            case .NIL: push(Value{.NIL, nil})
            case .TRUE: push(Value{.BOOL, true})
            case .FALSE: push(Value{.BOOL, false})
            case .POP: pop()

            case .GET_LOCAL:
                slot := readByte()
                push(vm.stack[slot])

            case .SET_LOCAL:
                slot := readByte()
                vm.stack[slot] = peek(0)

            case .GET_GLOBAL:
                name := readString()
                value: Value
                ok: bool
                if value, ok = tableGet(&vm.globals, name); !ok {
                    runtimeError("Undefined variable '%s'.", name.str)
                    return .RUNTIME_ERROR
                }
                push(value)

            case .DEFINE_GLOBAL:
                name := readString()
                tableSet(&vm.globals, name, peek(0))
                pop()

            case .SET_GLOBAL:
                name := readString()
                if tableSet(&vm.globals, name, peek(0)) {
                    tableDelete(&vm.globals, name)
                    runtimeError("Undefined variable '%s'.", name.str)
                    return .RUNTIME_ERROR
                }

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
                v1, ok1 := peek(0).variant.(^Obj)
                v2, ok2 := peek(1).variant.(^Obj)
                if ok1 && ok2 {
                    if v1.type == .STRING && v2.type == .STRING {
                        concatenate()
                    }
                } else if peek(0).type == .NUMBER && peek(0).type == .NUMBER {
                    b := pop()
                    a := pop()
                    a.variant = a.variant.(f64) + b.variant.(f64)
                    push(a)
                } else {
                    runtimeError("Operands must be two numbers or two strings.")
                    return .RUNTIME_ERROR
                }

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

            case .PRINT:
                printValue(pop())
                fmt.println()

            case .RETURN:
                // Exit interpreter.
                return .OK
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

concatenate :: proc() {
    b := cast(^ObjString) pop().variant.(^Obj)
    a := cast(^ObjString) pop().variant.(^Obj)

    length := len(a.str) + len(b.str)
    chars := make([]byte, length)
    i := 0
    i =+ copy(chars[i:], a.str)
    copy(chars[i:], b.str)

    result := takeString(string(chars))
    push(Value{.OBJ, cast(^Obj)result})
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

readString :: proc() -> ^ObjString {
    return cast(^ObjString) readConstant().variant.(^Obj)
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

freeObjects :: proc() {
    object := vm.objects
    for object != nil {
        next := object.next
        freeObject(object)
        object = next
    }
}
