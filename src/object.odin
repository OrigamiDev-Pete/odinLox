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
    return allocateString(s)
}

allocateObject :: proc($T: typeid, type: ObjType) -> ^Obj {
    object := new(T)
    object.type = type
    object.next = vm.objects
    vm.objects = object
    return object
}

allocateString :: proc(str: string) -> ^ObjString {
    lstring := cast(^ObjString) allocateObject(ObjString, .STRING)
    lstring.str = str
    return lstring
}

takeString :: proc(str: string) -> ^ObjString {
    return allocateString(str)
}

freeObject :: proc(object: ^Obj) {
    switch object.type {
        case .STRING:
            lstring := cast(^ObjString) object
            delete(lstring.str)
            free(lstring)
    }
}