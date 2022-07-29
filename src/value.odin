package main

import "core:fmt"
import "core:log"

ValueType :: enum {
    BOOL,
    NIL,
    NUMBER,
}

Value :: struct {
    type: ValueType,
    variant: union {
        bool,
        f64,
    },
}

printValue :: proc(value: Value) {
    fmt.print(value.variant)
}

valuesEqual :: proc(a, b: Value) -> bool {
    if a.type != b.type { return false }
    switch a.type {
        case .BOOL:   return a.variant.(bool) == b.variant.(bool)
        case .NIL:    return true
        case .NUMBER: return a.variant.(f64) == b.variant.(f64)
        case: return false // unreachable
    }
}