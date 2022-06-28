package main

import "core:fmt"

Value :: distinct f64

printValue :: proc(value: Value) {
    fmt.printf("%f", value)
}