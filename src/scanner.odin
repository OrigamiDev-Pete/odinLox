package main

import "core:fmt"
import "core:io"
import "core:mem"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import "core:unicode/utf8/utf8string"

String :: utf8string.String

TokenType :: enum {
    // Single-character tokens.
    LEFT_PAREN, RIGHT_PAREN,
    LEFT_BRACE, RIGHT_BRACE,
    COMMA, DOT, MINUS, PLUS,
    SEMICOLON, SLASH, STAR,

    // One or two character tokens.
    BANG, BANG_EQUAL,
    EQUAL, EQUAL_EQUAL,
    GREATER, GREATER_EQUAL,
    LESS, LESS_EQUAL,

    // Literals
    IDENTIFIER, STRING, NUMBER,

    // Keywords
    AND, CLASS, ELSE, FALSE,
    FOR, FUN, IF, NIL, OR,
    PRINT, RETURN, SUPER, THIS,
    TRUE, VAR, WHILE,

    ERROR, EOF,
}

Scanner :: struct {
    buf: String,
    start: int,
    current: int,
    line: int,
}

TokenValue :: union {
    []rune,
    string,
}

Token :: struct {
    type: TokenType,
    value: TokenValue,
    line: int,
}

scanner: Scanner

initScanner :: proc(source: string) {
    utf8string.init(&scanner.buf, source)
    scanner.start = 0
    scanner.current = 0
    scanner.line = 1
}

scanToken :: proc() -> Token {
    skipWhitespace()
    scanner.start = scanner.current
    // fmt.println(scanner)
    // fmt.println(len(scanner.buf))
    if isAtEnd() {
        return makeToken(.EOF)
    }

    c := advance()
    if unicode.is_letter(c) { return identifier() }
    if unicode.is_digit(c) { return numberLiteral() }
    switch c {
        case '(': return makeToken(.LEFT_PAREN)
        case ')': return makeToken(.RIGHT_PAREN)
        case '{': return makeToken(.LEFT_BRACE)
        case '}': return makeToken(.RIGHT_BRACE)
        case ';': return makeToken(.SEMICOLON)
        case ',': return makeToken(.COMMA)
        case '.': return makeToken(.DOT)
        case '-': return makeToken(.MINUS)
        case '+': return makeToken(.PLUS)
        case '/': return makeToken(.SLASH)
        case '*': return makeToken(.STAR)
        case '!': return makeToken(.EQUAL_EQUAL if match('=') else .BANG)
        case '=': return makeToken(.BANG_EQUAL if match('=') else .EQUAL)
        case '<': return makeToken(.LESS_EQUAL if match('=') else .LESS)
        case '>': return makeToken(.GREATER_EQUAL if match('=') else .GREATER)
        case '"': return stringLiteral()
    }

    return errorToken("Unexpected character.")
}

isAtEnd :: proc() -> bool {
    return scanner.current == utf8string.len(&scanner.buf)-1
}

makeToken :: proc(type: TokenType) -> (token: Token) {
    token.type = type
    token.value = utf8string.slice(&scanner.buf, scanner.start, scanner.current)
    token.line = scanner.line
    return
}

errorToken :: proc(error_message: string) -> (token: Token) {
    token.type = .ERROR
    token.value = utf8.string_to_runes(error_message)
    token.line = scanner.line
    return
}

skipWhitespace :: proc() {
    for {
        if isAtEnd() { return }
        c := peek()
        switch c {
            case ' ', '\r', '\t': advance()
            case '\n': {
                scanner.line += 1
                advance()
            }
            case '/': {
                nextChar, err := peekNext()
                if err == nil {
                    if nextChar == '/' {
                        // A comment goes until the end of the line.
                        for peek() != '\n' && !isAtEnd() { advance() }
                    } else {
                        return
                    }
                } else { return }
            }
            case: return
        }
    }
}

checkKeyword :: proc(keyword: string, type: TokenType) -> TokenType {
    slice := utf8string.slice(&scanner.buf, scanner.start, scanner.start + len(keyword))
    if strings.compare(string(slice), keyword) == 0 {
        return type
    }

    return .IDENTIFIER
}

identifierType :: proc() -> TokenType {
    switch utf8string.at(&scanner.buf, scanner.start) {
        case 'a': return checkKeyword("and", .AND)
        case 'c': return checkKeyword("class", .CLASS)
        case 'e': return checkKeyword("else", .ELSE)
        case 'f': {
            if scanner.current - scanner.start > 1 {
                switch utf8string.at(&scanner.buf, scanner.start + 1) {
                case 'a': return checkKeyword("false", .FALSE)
                case 'o': return checkKeyword("for", .FOR)
                case 'u': return checkKeyword("fun", .FUN) 
                }
            }
        }
        case 'i': return checkKeyword("if", .IF)
        case 'n': return checkKeyword("nil", .NIL)
        case 'o': return checkKeyword("or", .OR)
        case 'p': return checkKeyword("print", .PRINT)
        case 'r': return checkKeyword("return", .RETURN)
        case 's': return checkKeyword("super", .SUPER)
        case 't': {
            if scanner.current - scanner.start > 1 {
                switch utf8string.at(&scanner.buf, scanner.start + 1) {
                    case 'h': return checkKeyword("this", .THIS)
                    case 'r': return checkKeyword("true", .TRUE)
                }
            }
        }
        case 'v': return checkKeyword("var", .VAR)
        case 'w': return checkKeyword("while", .WHILE)
    }
    return .IDENTIFIER

}

identifier :: proc() -> Token {
    for unicode.is_letter(peek()) || unicode.is_digit(peek()) {
        advance()
    }
    return makeToken(identifierType())
}

numberLiteral :: proc() -> Token {
    for unicode.is_digit(rune(peek())) { advance() }

    // Look for a fractional part.
    nextChar, _  := peekNext()
    if peek() == '.' && unicode.is_digit(rune(nextChar)) {
        // Consume the ".".
        advance()

        for unicode.is_digit(rune(peek())) { advance() }
    }

    return makeToken(.NUMBER)

}

stringLiteral :: proc() -> Token {
    for peek() != '"' && !isAtEnd() {
        if peek() == '\n' { scanner.line += 1 }
        advance()
    }

    if !isAtEnd() { return errorToken("Unterminated string.") }

    // The closing quote.
    advance()
    return makeToken(.STRING)
}

advance :: proc() -> rune {
    scanner.current += 1
    return utf8string.at(&scanner.buf, scanner.current-1)
}

peek :: proc() -> rune {
    return utf8string.at(&scanner.buf, scanner.current)
}

peekNext :: proc() -> (rune, io.Error) {
    if isAtEnd() { return ' ', io.Error.EOF }
    return utf8string.at(&scanner.buf, scanner.current+1), nil
}

match :: proc(expected: rune) -> bool {
    if isAtEnd() { return false }
    if utf8string.at(&scanner.buf, scanner.current) != expected { return false }
    scanner.current += 1
    return true
}