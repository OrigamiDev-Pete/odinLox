package main

import "core:log"
import "core:fmt"
import "core:strings"

ObjType :: enum {
    BOUND_METHOD,
    CLASS,
    CLOSURE,
    FUNCTION,
    INSTANCE,
    NATIVE,
    STRING,
    UPVALUE,
}

Obj :: struct {
    type: ObjType,
    isMarked: bool,
    next: ^Obj,
}

ObjFunction :: struct {
    using obj: Obj,
    arity: u32,
    upvalueCount: int,
    chunk: Chunk,
    name: ^ObjString,
}

NativeFn :: proc (argCount: u8, args: []Value) -> Value

ObjNative :: struct {
    using obj: Obj,
    function: NativeFn,
}

ObjString :: struct {
    using obj: Obj,
    str: string,
    hash: u32,
}

ObjUpvalue :: struct {
    using obj: Obj,
    location: ^Value,
    closed: Value,
    nextUpvalue: ^ObjUpvalue,
}

ObjClass :: struct {
    using obj: Obj,
    name: ^ObjString,
    methods: Table,
}

ObjInstance :: struct {
    using obj: Obj,
    klass: ^ObjClass,
    fields: Table,
}

ObjClosure :: struct {
    using obj: Obj,
    function: ^ObjFunction,
    upvalues: [dynamic]^ObjUpvalue,
    upvalueCount: int,
}

ObjBoundMethod :: struct {
    using obj: Obj,
    receiver: Value,
    method: ^ObjClosure,
}

newBoundMethod :: proc(receiver: Value, method: ^ObjClosure) -> ^ObjBoundMethod {
    bound := allocateObject(ObjBoundMethod, .BOUND_METHOD)
    bound.receiver = receiver
    bound.method = method
    return bound
}

newFunction :: proc() -> ^ObjFunction {
    function := allocateObject(ObjFunction, .FUNCTION)
    
    return function
}

newInstance :: proc(klass: ^ObjClass) -> ^ObjInstance {
    instance := allocateObject(ObjInstance, .INSTANCE)
    instance.klass = klass
    return instance
}

newNative :: proc(function: NativeFn) -> ^ObjNative {
    native := allocateObject(ObjNative, .NATIVE)
    native.function = function
    return native
}

isObjType :: proc(value: Value, type: ObjType) -> bool {
    return IS_OBJ(value) && AS_OBJ(value).type == type
}

printObject :: proc(object: ^Obj) {
    switch object.type {
        case .BOUND_METHOD: printFunction((cast(^ObjBoundMethod) object).method.function)
        case .CLASS: fmt.printf("%v", (cast(^ObjClass) object).name.str)
        case .CLOSURE: printFunction((cast(^ObjClosure) object).function)
        case .FUNCTION: printFunction(cast(^ObjFunction) object)
        case .INSTANCE: fmt.printf("%v instance", (cast(^ObjInstance) object).klass.name.str)
        case .NATIVE: fmt.print("<native fn>")
        case .STRING: fmt.printf("%v", (cast(^ObjString) object).str)
        case .UPVALUE: fmt.print("upvalue")
        case: fmt.print(object)
    }
}

copyString :: proc(str: string) -> ^ObjString {
    s := strings.clone(str)
    hash := hashString(s)

    interned := tableFindString(&vm.strings, s, hash)
    if interned != nil { return interned }

    return allocateString(s, hash)
}

newUpvalue :: proc(slot: ^Value) -> ^ObjUpvalue {
    upvalue := allocateObject(ObjUpvalue, .UPVALUE)
    upvalue.closed = NIL_VAL()
    upvalue.location = slot
    return upvalue
}

printFunction :: proc(function: ^ObjFunction) {
    if (function.name == nil) {
        fmt.printf("<script>")
        return
    }
    fmt.printf("<fn %v>", function.name)
}

allocateObject :: proc($T: typeid, type: ObjType) -> ^T {
    object := new(T)
    object.type = type
    object.next = vm.objects
    vm.objects = object

    vm.bytesAllocated += size_of(T)
    if (vm.bytesAllocated > vm.nextGC) {
        collectGarbage()
    }

    when DEBUG_LOG_GC {
        log.debugf("%p allocate %v for %v", object, size_of(T), type)
    }

    return object
}

newClass :: proc(name: ^ObjString) -> ^ObjClass {
    klass := allocateObject(ObjClass, .CLASS)
    klass.name = name
    return klass
}

newClosure :: proc(function: ^ObjFunction) -> (closure: ^ObjClosure) {
    upvalues := make([dynamic]^ObjUpvalue, function.upvalueCount)
    
    closure = allocateObject(ObjClosure, .CLOSURE)
    closure.function = function
    closure.upvalues = upvalues
    closure.upvalueCount = function.upvalueCount
    return
}

allocateString :: proc(str: string, hash: u32) -> ^ObjString {
    lstring := allocateObject(ObjString, .STRING)
    lstring.str = str
    lstring.hash = hash

    push(OBJ_VAL(lstring))
    tableSet(&vm.strings, lstring, NIL_VAL())
    pop()

    return lstring
}

hashString :: proc(str: string) -> u32 {
    hash : u32 = 2166136261
    for c in str {
        hash ~= u32(c)
        hash *= 16777619
    }
    return hash
}

takeString :: proc(str: string) -> ^ObjString {
    hash := hashString(str)

    interned := tableFindString(&vm.strings, str, hash)
    if interned != nil {
        delete(str)
        return interned
    }

    return allocateString(str, hash)
}

freeObject :: proc(object: ^Obj) {
    when DEBUG_LOG_GC {
        log.debugf("%p free type %v", object, object.type)
    }

    switch object.type {
        case .BOUND_METHOD:
            vm.bytesAllocated -= size_of(object)
            free(object)
        case .CLASS:
            klass := cast(^ObjClass)object
            vm.bytesAllocated -= size_of(klass.methods)
            freeTable(&klass.methods)
            vm.bytesAllocated -= size_of(object)
            free(object)
        case .CLOSURE:
            vm.bytesAllocated -= size_of(object)
            free(object)
        case .FUNCTION:
            vm.bytesAllocated -= size_of(object)
            free(object)
            function := cast(^ObjFunction) object
            vm.bytesAllocated -= size_of(function.chunk)
            freeChunk(&function.chunk)
            vm.bytesAllocated -= size_of(function)
            free(function)
        case .INSTANCE:
            instance := cast(^ObjInstance)object
            freeTable(&instance.fields)
            vm.bytesAllocated -= size_of(object)
            free(object)
        case .NATIVE:
            vm.bytesAllocated -= size_of(object)
            free(object)
        case .STRING:
            lstring := cast(^ObjString) object
            vm.bytesAllocated -= size_of(lstring.str)
            delete(lstring.str)
            vm.bytesAllocated -= size_of(lstring)
            free(lstring)
        case .UPVALUE:
            vm.bytesAllocated -= size_of(object)
            free(object)
            closure := cast(^ObjClosure) object
            vm.bytesAllocated -= size_of(closure.upvalues)
            delete(closure.upvalues)
    }
}