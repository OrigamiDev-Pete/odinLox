package main

import "core:fmt"
import "core:log"
import "core:time"

DEBUG_STACK_TRACE :: false
FRAMES_MAX :: 64
STACK_MAX :: FRAMES_MAX * cast(u32) max(u8)

CallFrame :: struct {
    closure: ^ObjClosure,
    ip: int,
    slots: []Value,
}

VM :: struct {
    frames: [FRAMES_MAX]CallFrame,
    frameCount: u32,

    stack: [STACK_MAX]Value,
    stackIndex: i32,
    strings: Table,
    initString: ^ObjString,
    globals: Table,
    openUpvalues: ^ObjUpvalue,

    bytesAllocated: int,
    nextGC: int,
    objects: ^Obj,
    grayStack: [dynamic]^Obj,
    grayCount: int,
}

InterpretResult :: enum {
    OK,
    COMPILE_ERROR,
    RUNTIME_ERROR,
}

vm: VM

clockNative :: proc(argCount: u8, args: []Value) -> Value {
    return NUMBER_VAL(f64(time.now()._nsec))
}

initVM :: proc() {
    resetStack()
    vm.nextGC = 1024 * 1024

    vm.initString = copyString("init")

    defineNative("clock", clockNative)
}

freeVM :: proc() {
    freeTable(&vm.strings)
    freeTable(&vm.globals)
    vm.initString = nil
    freeObjects()
}

interpret :: proc(source: string) -> InterpretResult {
    function := compile(source)
    if (function == nil) { return .COMPILE_ERROR }

    push(OBJ_VAL(function))
    closure := newClosure(function)
    pop()
    push(OBJ_VAL(closure))
    vmCall(closure, 0)

	return run()
}

run :: proc() -> InterpretResult {
    frame := &vm.frames[vm.frameCount - 1]

    for {
        when DEBUG_STACK_TRACE {
            fmt.printf("          ")
            for i in 0..<vm.stackIndex {
                fmt.printf("[ ")
                printValue(vm.stack[i])
                fmt.printf(" ]")
            }
            fmt.println()
            disassembleInstruction(frame.closure.function.chunk, frame.ip)
        }

        instruction := cast(OpCode) readByte()
        switch instruction {
            case .CONSTANT:
                constant := readConstant()
                push(constant)

            case .NIL: push(NIL_VAL())
            case .TRUE: push(BOOL_VAL(true))
            case .FALSE: push(BOOL_VAL(false))
            case .POP: pop()

            case .GET_LOCAL:
                slot := readByte()
                push(frame.slots[slot])

            case .SET_LOCAL:
                slot := readByte()
                frame.slots[slot] = peek(0)

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

            case .GET_UPVALUE:
                slot := readByte()
                push(frame.closure.upvalues[slot-1].location^)

            case .SET_UPVALUE:
                slot := readByte()
                frame.closure.upvalues[slot-1].location^ = peek(0)

            case .GET_PROPERTY: {
                if AS_OBJ(peek(0)).type != .INSTANCE {
                    runtimeError("Only instances have properties.")
                    return .RUNTIME_ERROR
                }

                instance := cast(^ObjInstance) AS_OBJ(peek(0))
                name := readString()

                value: Value
                if value, ok := tableGet(&instance.fields, name); ok {
                    pop() // instance
                    push(value)
                    break
                }

                if !bindMethod(instance.klass, name) {
                    return .RUNTIME_ERROR
                }
            }

            case .SET_PROPERTY: {
                if AS_OBJ(peek(1)).type != .INSTANCE {
                    runtimeError("Only instances have properties.")
                    return .RUNTIME_ERROR
                }

                instance := cast(^ObjInstance) AS_OBJ(peek(1))
                tableSet(&instance.fields, readString(), peek(0))
                value := pop()
                pop()
                push(value)
            }

            case .GET_SUPER: {
                name := readString()
                superclass := cast(^ObjClass) AS_OBJ(pop())

                if !bindMethod(superclass, name) {
                    return .RUNTIME_ERROR
                }
            }

            case .EQUAL:
                b := pop()
                a := pop()
                push(BOOL_VAL(valuesEqual(a, b)))

            case .GREATER:
                checkNumbers() or_return
                b := pop()
                a := pop()
                push(BOOL_VAL(AS_NUMBER(a) > AS_NUMBER(b)))

            case .LESS:
                checkNumbers() or_return
                b := pop()
                a := pop()
                push(BOOL_VAL(AS_NUMBER(a) < AS_NUMBER(b)))

            case .ADD:
                v1 := peek(0)
                v2 := peek(1)
                if IS_OBJ(v1) && AS_OBJ(v1).type == .STRING && IS_OBJ(v2) && AS_OBJ(v2).type == .STRING {
                    concatenate()
                } else if IS_NUMBER(peek(0)) && IS_NUMBER(peek(1)) {
                    b := AS_NUMBER(pop())
                    a := AS_NUMBER(pop())
                    push(NUMBER_VAL(a + b))
                } else {
                    runtimeError("Operands must be two numbers or two strings.")
                    return .RUNTIME_ERROR
                }

            case .SUBTRACT:
                checkNumbers() or_return
                b := AS_NUMBER(pop())
                a := AS_NUMBER(pop())
                push(NUMBER_VAL(a - b))

            case .MULTIPLY:
                checkNumbers() or_return
                b := AS_NUMBER(pop())
                a := AS_NUMBER(pop())
                push(NUMBER_VAL(a * b))

            case .DIVIDE:
                checkNumbers() or_return
                b := AS_NUMBER(pop())
                a := AS_NUMBER(pop())
                push(NUMBER_VAL(a / b))

            case .NOT:
                push(BOOL_VAL(isFalsey(pop())))

            case .NEGATE:
                if !IS_NUMBER(peek(0)) {
                    runtimeError("Operand must be a number.")
                    return .RUNTIME_ERROR
                }
                // vm.stack[vm.stackIndex-1].variant = -vm.stack[vm.stackIndex-1].variant.(f64)
                push(NUMBER_VAL(-AS_NUMBER(pop())))

            case .PRINT:
                printValue(pop())
                fmt.println()

            case .JUMP:
                offset := readShort()
                frame.ip += int(offset)

            case .JUMP_IF_FALSE:
                offset := readShort()
                if isFalsey(peek(0)) {
                   frame.ip += int(offset)
                }

            case .LOOP: 
                offset := readShort()
                frame.ip -= int(offset)

            case .CALL:
                argCount := readByte()
                if !callValue(peek(i32(argCount)), argCount) {
                    return .RUNTIME_ERROR
                }
                frame = &vm.frames[vm.frameCount - 1]

            case .INVOKE: {
                method := readString()
                argCount := readByte()
                if !invoke(method, argCount) {
                    return .RUNTIME_ERROR
                }
                frame = &vm.frames[vm.frameCount - 1]
            }

            case .SUPER_INVOKE: {
                method := readString()
                argCount := readByte()
                superclass := cast(^ObjClass) AS_OBJ(pop())
                if !invokeFromClass(superclass, method, argCount) {
                    return .RUNTIME_ERROR
                }
                frame = &vm.frames[vm.frameCount - 1]
            }

            case .CLOSURE:
                function := cast(^ObjFunction) AS_OBJ(readConstant())
                closure := newClosure(function)
                push(OBJ_VAL(closure))
                for i in 0..<closure.upvalueCount {
                    isLocal := bool(readByte())
                    index := readByte()
                    if isLocal {
                        closure.upvalues[i] = captureUpvalue(&frame.slots[index]) // this could be wrong
                    } else {
                        closure.upvalues[i] = frame.closure.upvalues[index]
                    }
                }

            case .CLOSE_UPVALUE:
                closeUpvalues(&vm.stack[vm.stackIndex - 1])
                pop()

            case .RETURN:
                result := pop()
                closeUpvalues(&frame.slots[0])
                vm.frameCount -= 1
                if vm.frameCount == 0 {
                    pop()
                    return .OK
                }

                // log.debug("%v", vm.stackIndex)
                vm.stackIndex -= i32(frame.closure.function.arity) + 1
                // log.debug("%v", vm.stackIndex)
                push(result)
                frame = &vm.frames[vm.frameCount - 1]

            case .CLASS:
                push(OBJ_VAL(newClass(readString())))
            
            case .METHOD:
                defineMethod(readString())
            
            case .INHERIT: {
                superclass := peek(1)
                if AS_OBJ(superclass).type != .CLASS {
                    runtimeError("Superclass must be a class.")
                    return .RUNTIME_ERROR
                }

                subclass := cast(^ObjClass) AS_OBJ(peek(0))
                tableAddAll(&(cast(^ObjClass) AS_OBJ(superclass)).methods, &subclass.methods)
                pop()
            }
        }
    }
}

checkNumbers :: proc() -> InterpretResult {
    if !IS_NUMBER(peek(0)) || !IS_NUMBER(peek(1)) {
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

// renamed from 'call' because of naming collision
vmCall :: proc(closure: ^ObjClosure, argCount: u8) -> bool {
    if u32(argCount) != closure.function.arity {
        runtimeError("Expected %v arguments but got %v.", closure.function.arity, argCount)
        return false
    }

    if vm.frameCount == FRAMES_MAX {
        runtimeError("Stack overflow.")
        return false
    }

    frame := &vm.frames[vm.frameCount]
    vm.frameCount += 1
    frame.closure = closure
    frame.ip = 0
    // log.debug("%v", frame.slots)
    frame.slots = vm.stack[vm.stackIndex - i32(argCount) - 1:]
    // log.debug("%v", frame.slots[:10])
    return true
}

callValue :: proc(callee: Value, argCount: u8) -> bool {
    if IS_OBJ(callee) {
        calleeObject := AS_OBJ(callee)
        #partial switch calleeObject.type {
            case .BOUND_METHOD: {
                bound := cast(^ObjBoundMethod) calleeObject
                vm.stack[vm.stackIndex - i32(argCount) - 1] = bound.receiver
                return vmCall(bound.method, argCount)
            }
            case .CLASS: {
                klass := cast(^ObjClass) calleeObject
                vm.stack[vm.stackIndex - i32(argCount) - 1] = OBJ_VAL(newInstance(klass))
                if initializer, ok := tableGet(&klass.methods, vm.initString); ok {
                    return vmCall(cast(^ObjClosure) AS_OBJ(initializer), argCount)
                } else if argCount != 0 {
                    runtimeError("Expected 0 arguments but got %v.", argCount)
                    return false
                }

                return true
            }
            case .CLOSURE:
                return vmCall(cast(^ObjClosure) calleeObject, argCount)
            case .NATIVE:
                native_object := cast(^ObjNative) calleeObject
                native := native_object.function
                result := native(argCount, vm.stack[vm.stackIndex - i32(argCount):])
                vm.stackIndex -= i32(argCount) + 1
                push(result)
                return true
        }
    }
    runtimeError("Can only call functions and classes.")
    return false
}

invokeFromClass :: proc(klass: ^ObjClass, name: ^ObjString, argCount: u8) -> bool {
    method: Value
    ok: bool
    if method, ok = tableGet(&klass.methods, name); !ok {
        runtimeError("Undefined property '%v'.", name.str)
        return false
    }
    return vmCall(cast(^ObjClosure) AS_OBJ(method), u8(argCount))
}

invoke :: proc(name: ^ObjString, argCount: u8) -> bool {
    receiver := peek(i32(argCount))

    if AS_OBJ(receiver).type != .INSTANCE {
        runtimeError("Only instances have methods.")
        return false
    }

    instance := cast(^ObjInstance) AS_OBJ(receiver)

    if value, ok := tableGet(&instance.fields, name); ok {
        vm.stack[vm.stackIndex - i32(argCount) - 1] = value
        return callValue(value, argCount)
    }

    return invokeFromClass(instance.klass, name, argCount)
}

bindMethod :: proc(klass: ^ObjClass, name: ^ObjString) -> bool {
    method: Value
    ok: bool
    if method, ok = tableGet(&klass.methods, name); !ok {
        runtimeError("Undefined property '%s'.", name.str)
        return false
    }

    bound := newBoundMethod(peek(0), cast(^ObjClosure) AS_OBJ(method))

    pop()
    push(OBJ_VAL(bound))
    return true
}

captureUpvalue :: proc(local: ^Value) -> ^ObjUpvalue {
    prevUpvalue: ^ObjUpvalue
    upvalue := vm.openUpvalues
    for upvalue != nil && upvalue.location > local {
        prevUpvalue = upvalue
        upvalue = upvalue.nextUpvalue
    }

    if upvalue != nil && upvalue.location == local {
        return upvalue
    }

    createdUpvalue := newUpvalue(local)
    createdUpvalue.nextUpvalue = upvalue

    if prevUpvalue == nil {
        vm.openUpvalues = createdUpvalue
    } else {
        prevUpvalue.nextUpvalue = createdUpvalue
    }

    return createdUpvalue
}

closeUpvalues :: proc(last: ^Value) {
    for vm.openUpvalues != nil && vm.openUpvalues.location >= last {
        upvalue := vm.openUpvalues
        upvalue.closed = upvalue.location^
        upvalue.location = &upvalue.closed
        vm.openUpvalues = upvalue.nextUpvalue
    }
}

defineMethod :: proc(name: ^ObjString) {
    method := peek(0)
    klass := cast(^ObjClass) AS_OBJ(peek(1))
    tableSet(&klass.methods, name, method)
    pop()
}

isFalsey :: proc(value: Value) -> bool {
    return IS_NIL(value) || (IS_BOOL(value) && !AS_BOOL(value))
}

concatenate :: proc() {
    b := cast(^ObjString) AS_OBJ(peek(0))
    a := cast(^ObjString) AS_OBJ(peek(1))

    length := len(a.str) + len(b.str)
    chars := make([]byte, length)
    i := 0
    i =+ copy(chars[i:], a.str)
    copy(chars[i:], b.str)

    result := takeString(string(chars))
    pop()
    pop()
    push(OBJ_VAL(result))
}

readByte :: proc() -> (b: u8) {
    frame := &vm.frames[vm.frameCount - 1]
    b = frame.closure.function.chunk.code[frame.ip]
    frame.ip += 1
    return
}

readShort :: proc() -> (s: u16) {
    frame := &vm.frames[vm.frameCount - 1]
    frame.ip += 2
    s = u16((frame.closure.function.chunk.code[frame.ip - 2] << 8) | frame.closure.function.chunk.code[frame.ip - 1])
    return
}

readConstant :: proc() -> Value {
    frame := &vm.frames[vm.frameCount - 1]
    return frame.closure.function.chunk.constants[readByte()]
}

readString :: proc() -> ^ObjString {
    return cast(^ObjString) AS_OBJ(readConstant())
}

resetStack :: proc() {
    vm.stackIndex = 0
    vm.frameCount = 0
}

runtimeError :: proc(format: string, args: ..any) {
    log.errorf(format, ..args)

    for i := vm.frameCount-1; i >= 0; i -=1 {
        frame := &vm.frames[i]
        function := frame.closure.function
        instruction_index := len(function.chunk.code) - frame.ip - 1
        log.errorf("[line %v] in", function.chunk.lines[instruction_index])
        if function.name == nil {
            log.error("script\n")
        } else {
            log.errorf("%v()\n", function.name.str)
        }
    }

    resetStack()
}

defineNative :: proc(name: string, function: NativeFn) {
    push(OBJ_VAL(copyString(name)))
    push(OBJ_VAL(newNative(function)))
    tableSet(&vm.globals, cast(^ObjString) AS_OBJ(vm.stack[0]), vm.stack[1])
    pop()
    pop()
}

freeObjects :: proc() {
    object := vm.objects
    for object != nil {
        next := object.next
        freeObject(object)
        object = next
    }

    delete(vm.grayStack);
}
