package main

import "core:fmt"
import "core:strings"

ObjType :: enum {
    STRING,
}

Obj :: struct {
    type: ObjType,
    next: ^Obj,
}

ObjString :: struct {
    using obj: Obj,
    str: string,
    hash: u32,
}

isObjType :: proc(value: Value, type: ObjType) -> bool {
    return value.type == .OBJ && value.variant.(^Obj).type == type
}

printObject :: proc(object: ^Obj) {
    switch object.type {
        case .STRING: fmt.printf("\"%v\"", (cast(^ObjString) object).str)
        case: fmt.print(object)
    }
}

copyString :: proc(str: string) -> ^ObjString {
    s := strings.clone(str[1:len(str)-1])
    hash := hashString(s)

    interned := tableFindString(&vm.strings, s, hash)
    if interned != nil { return interned }

    return allocateString(s, hash)
}

allocateObject :: proc($T: typeid, type: ObjType) -> ^Obj {
    object := new(T)
    object.type = type
    object.next = vm.objects
    vm.objects = object
    return object
}

allocateString :: proc(str: string, hash: u32) -> ^ObjString {
    lstring := cast(^ObjString) allocateObject(ObjString, .STRING)
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
        case .STRING:
            lstring := cast(^ObjString) object
            delete(lstring.str)
            free(lstring)
    }
}