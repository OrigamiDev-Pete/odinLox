package main

import "core:fmt"
import "core:log"

ValueType :: enum {
    BOOL,
    NIL,
    NUMBER,
    OBJ,
}

Value :: struct {
    type: ValueType,
    variant: union {
        bool,
        f64,
        ^Obj,
    },
}

printValue :: proc(value: Value) {
    #partial switch value.type {
        case .OBJ: printObject(value.variant.(^Obj))
        case: fmt.print(value.variant)
    }
}

valuesEqual :: proc(a, b: Value) -> bool {
    if a.type != b.type { return false }
    switch a.type {
        case .BOOL:   return a.variant.(bool) == b.variant.(bool)
        case .NIL:    return true
        case .NUMBER: return a.variant.(f64) == b.variant.(f64)
        case .OBJ:    return a.variant == b.variant // Valid because of string interning
        case: return false // unreachable
    }
}