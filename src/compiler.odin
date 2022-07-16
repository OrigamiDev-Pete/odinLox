package main

import "core:fmt"


compile :: proc(source: string) {
    initScanner(source)
    line := -1
    for {
        token := scanToken()
        if token.line != line {
            fmt.printf("%4v ", token.line)
            line = token.line
        } else {
            fmt.printf("   | ")
        }
        fmt.printf("%2v '%v'\n", token.type, token.value)

        if (token.type == .EOF) { return }
    }
}