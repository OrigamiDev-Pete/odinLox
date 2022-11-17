package main

import "core:fmt"
import "core:strings"

ObjType :: enum {
    FUNCTION,
    NATIVE,
    STRING,
}

Obj :: struct {
    type: ObjType,
    next: ^Obj,
}

ObjFunction :: struct {
    using obj: Obj,
    arity: u32,
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

newFunction :: proc() -> ^ObjFunction {
    function := allocateObject(ObjFunction, .FUNCTION)
    
    return function
}

newNative :: proc(function: NativeFn) -> ^ObjNative {
    native := allocateObject(ObjNative, .NATIVE)
    native.function = function
    return native
}

isObjType :: proc(value: Value, type: ObjType) -> bool {
    return value.type == .OBJ && value.variant.(^Obj).type == type
}

printObject :: proc(object: ^Obj) {
    switch object.type {
        case .FUNCTION: printFunction(cast(^ObjFunction) object)
        case .NATIVE: fmt.print("<native fn>")
        case .STRING: fmt.printf("%v", (cast(^ObjString) object).str)
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
    return object
}

allocateString :: proc(str: string, hash: u32) -> ^ObjString {
    lstring := allocateObject(ObjString, .STRING)
    lstring.str = str
    lstring.hash = hash
    tableSet(&vm.strings, lstring, Value{.NIL, nil})
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
    switch object.type {
        case .FUNCTION:
            function := cast(^ObjFunction) object
            freeChunk(&function.chunk)
            free(function)
        case .NATIVE:
            free(object)
        case .STRING:
            lstring := cast(^ObjString) object
            delete(lstring.str)
            free(lstring)
    }
}