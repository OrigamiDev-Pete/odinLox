package main

import "core:log"
import "core:fmt"

DEBUG_STRESS_GC :: false
DEBUG_LOG_GC :: false

GC_HEAP_GROW_FACTOR :: 2

collectGarbage :: proc() {
    when DEBUG_LOG_GC {
        log.debug("-- gc begin")
        before := vm.bytesAllocated
    }

    markRoots()
    traceReferences()
    tableRemoveWhite(&vm.strings)
    sweep()

    vm.nextGC = vm.bytesAllocated * GC_HEAP_GROW_FACTOR

    when DEBUG_LOG_GC {
        log.debug("-- gc end\n")
        log.debugf("   collected %v bytes (from %v to %v) next at %v",
                before - vm.bytesAllocated, before, vm.bytesAllocated, vm.nextGC)
    }
}

markObject :: proc(object: ^Obj) {
    if object == nil { return }
    if object.isMarked { return }

    when DEBUG_LOG_GC {
        fmt.printf("[DEBUG] --- %p mark ", object)
        printValue(Value{.OBJ, object})
        fmt.println()
    }
    object.isMarked = true

    append(&vm.grayStack, object)
    vm.grayCount += 1
}

markValue :: proc(value: Value) {
    if value.type == .OBJ {
        markObject(value.variant.(^Obj))
    }
}

markArray :: proc(array: ^[dynamic]Value) {
    for value in array {
        markValue(value)
    }
}

blackenObject :: proc(object: ^Obj) {
    when DEBUG_LOG_GC {
        fmt.printf("[DEBUG] --- %p blacken ", object)
        printValue(Value{.OBJ, object})
        fmt.println()
    }

    switch object.type {
        case .CLASS: {
            klass := cast(^ObjClass)object
            markObject(klass.name)
        }
        case .CLOSURE: {
            closure := cast(^ObjClosure)object
            markObject(closure.function)
            for upvalue in closure.upvalues {
                markObject(upvalue)
            }
        }
        case .FUNCTION: {
            function := cast(^ObjFunction)object
            markObject(function.name)
            markArray(&function.chunk.constants)
        }
        case .INSTANCE: {
            instance := cast(^ObjInstance)object
            markObject(instance.klass)
            markTable(&instance.fields)
        }
        case .UPVALUE:
            markValue((cast(^ObjUpvalue)object).closed)
        case .NATIVE:
            fallthrough
        case .STRING:
    }
}

markRoots :: proc() {
    for i in 0..<vm.stackIndex {
        markValue(vm.stack[i])
    }

    for i in 0..<vm.frameCount {
        markObject(vm.frames[i].closure)
    }

    for upvalue := vm.openUpvalues; upvalue != nil; upvalue = upvalue.nextUpvalue {
        markObject(upvalue)
    }

    markTable(&vm.globals)
    markCompilerRoots()
}

traceReferences :: proc() {
    for vm.grayCount > 0 {
        vm.grayCount -= 1
        object := vm.grayStack[vm.grayCount]
        blackenObject(object)
    }
}

sweep :: proc() {
    previous: ^Obj
    object := vm.objects
    for object != nil {
        if object.isMarked {
            object.isMarked = false
            previous = object
            object = object.next
        } else {
            unreached := object
            object = object.next
            if previous != nil {
                previous.next = object
            } else {
                vm.objects = object
            }

            freeObject(unreached)
        }
    }
}