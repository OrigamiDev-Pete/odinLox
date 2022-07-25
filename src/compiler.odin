//+private file
package main

import "core:log"
import "core:strconv"

DEBUG_PRINT_CODE :: true

Parser :: struct {
	current: Token,
	previous: Token,
    hadError: bool,
    panicMode: bool,
}

Precedence :: enum {
    NONE,
    ASSIGNMENT, // =
    OR,         // or
    AND,        // and
    EQUALITY,   // == !=
    COMPARISON, // < > <= >=
    TERM,       // + -
    FACTOR,     // * /
    UNARY,      // ! -
    CALL,       // . ()
    PRIMARY,
}

ParseFn :: #type proc()

ParseRule :: struct {
    prefix: ParseFn,
    infix: ParseFn,
    precedence: Precedence,
}

parser: Parser
compilingChunk: ^Chunk

currentChunk :: proc() -> ^Chunk {
    return compilingChunk
}


compile :: proc(source: string, chunk: ^Chunk) -> bool {
    initScanner(source)
    compilingChunk = chunk

	advance()
	expression()
	consume(.EOF, "Expect end of expression.")
    endCompiler()
    return !parser.hadError
}

advance :: proc() {
	parser.previous = parser.current

	for {
		parser.current = scanToken()
		if parser.current.type != .ERROR { break }

		errorAtCurrent(parser.current.value)
	}
}

consume :: proc(type: TokenType, message: string) {
    if parser.current.type == type {
        advance()
        return
    }

    errorAtCurrent(message)
}

// Emitters

emitByte :: proc(byte: u8) {
    writeChunk(currentChunk(), byte, parser.previous.line)
}

emitBytes :: proc(byte1: u8, byte2: u8) {
    emitByte(byte1)
    emitByte(byte2)
}

emitReturn :: proc() {
    writeChunk(currentChunk(), OpCode.RETURN, parser.previous.line)
}

emitConstant :: proc(value: Value) {
    emitBytes(cast(u8)OpCode.CONSTANT, makeConstant(value))
}

//

U8_MAX :: cast(int)max(u8)

makeConstant :: proc(value: Value) -> u8 {
    constant := addConstant(currentChunk(), value)
    if constant > U8_MAX {
        error("Too many constants in one chunk.")
        return 0
    }

    return cast(u8) constant
}

endCompiler :: proc() {
    emitReturn()
    when DEBUG_PRINT_CODE {
        if !parser.hadError {
            disassembleChunk(currentChunk()^, "code")
        }
    }
}

binary :: proc() {
    operatoryType := parser.previous.type
    rule := getRule(operatoryType)
    parsePrecedence(cast(Precedence)(int(rule.precedence) + 1))

    #partial switch (operatoryType) {
        case .PLUS:  { emitByte(cast(u8)OpCode.ADD) }
        case .MINUS: { emitByte(cast(u8)OpCode.SUBTRACT) }
        case .STAR:  { emitByte(cast(u8)OpCode.MULTIPLY) }
        case .SLASH:  { emitByte(cast(u8)OpCode.DIVIDE) }
    }
}

expression :: proc() {
    parsePrecedence(.ASSIGNMENT)
}

grouping :: proc() {
    expression()
    consume(.RIGHT_PAREN, "Expect ')' after expression.")
}

number :: proc() {
    value := strconv.atof(parser.previous.value)
    emitConstant(value)
}

unary :: proc() {
    operatorType := parser.previous.type

    // Compile the operand
    parsePrecedence(.UNARY)

    // Emit the operator instruction
    #partial switch operatorType {
        case .MINUS: { emitByte(cast(u8) OpCode.NEGATE)}
    }
}

rules: []ParseRule = {
    TokenType.LEFT_PAREN    = ParseRule{ grouping, nil,    .NONE },
    TokenType.RIGHT_PAREN   = ParseRule{ nil,      nil,    .NONE },
    TokenType.LEFT_BRACE    = ParseRule{ nil,      nil,    .NONE },
    TokenType.RIGHT_BRACE   = ParseRule{ nil,      nil,    .NONE },
    TokenType.COMMA         = ParseRule{ nil,      nil,    .NONE },
    TokenType.DOT           = ParseRule{ nil,      nil,    .NONE },
    TokenType.MINUS         = ParseRule{ unary,    binary, .TERM },
    TokenType.PLUS          = ParseRule{ nil,      binary, .TERM },
    TokenType.SEMICOLON     = ParseRule{ nil,      nil,    .NONE },
    TokenType.SLASH         = ParseRule{ nil,      binary, .FACTOR },
    TokenType.STAR          = ParseRule{ nil,      binary, .FACTOR },
    TokenType.BANG          = ParseRule{ nil,      nil,    .NONE },
    TokenType.BANG_EQUAL    = ParseRule{ nil,      nil,    .NONE },
    TokenType.EQUAL         = ParseRule{ nil,      nil,    .NONE },
    TokenType.EQUAL_EQUAL   = ParseRule{ nil,      nil,    .NONE },
    TokenType.GREATER       = ParseRule{ nil,      nil,    .NONE },
    TokenType.GREATER_EQUAL = ParseRule{ nil,      nil,    .NONE },
    TokenType.LESS          = ParseRule{ nil,      nil,    .NONE },
    TokenType.LESS_EQUAL    = ParseRule{ nil,      nil,    .NONE },
    TokenType.IDENTIFIER    = ParseRule{ nil,      nil,    .NONE },
    TokenType.STRING        = ParseRule{ nil,      nil,    .NONE },
    TokenType.NUMBER        = ParseRule{ number,      nil,    .NONE },
    TokenType.AND           = ParseRule{ nil,      nil,    .NONE },
    TokenType.CLASS         = ParseRule{ nil,      nil,    .NONE },
    TokenType.ELSE          = ParseRule{ nil,      nil,    .NONE },
    TokenType.FALSE         = ParseRule{ nil,      nil,    .NONE },
    TokenType.FOR           = ParseRule{ nil,      nil,    .NONE },
    TokenType.FUN           = ParseRule{ nil,      nil,    .NONE },
    TokenType.IF            = ParseRule{ nil,      nil,    .NONE },
    TokenType.NIL           = ParseRule{ nil,      nil,    .NONE },
    TokenType.OR            = ParseRule{ nil,      nil,    .NONE },
    TokenType.PRINT         = ParseRule{ nil,      nil,    .NONE },
    TokenType.RETURN        = ParseRule{ nil,      nil,    .NONE },
    TokenType.SUPER         = ParseRule{ nil,      nil,    .NONE },
    TokenType.THIS          = ParseRule{ nil,      nil,    .NONE },
    TokenType.TRUE          = ParseRule{ nil,      nil,    .NONE },
    TokenType.VAR           = ParseRule{ nil,      nil,    .NONE },
    TokenType.WHILE         = ParseRule{ nil,      nil,    .NONE },
    TokenType.ERROR         = ParseRule{ nil,      nil,    .NONE },
    TokenType.EOF           = ParseRule{ nil,      nil,    .NONE },
}

parsePrecedence :: proc(precedence: Precedence) {
    advance()
    prefixRule := getRule(parser.previous.type).prefix
    if prefixRule == nil {
        error("Expect expression.")
        return
    }

    prefixRule()

    for precedence <= getRule(parser.current.type).precedence {
        advance()
        infixRule := getRule(parser.previous.type).infix
        infixRule()
    }
}

getRule :: proc(type: TokenType) -> ParseRule {
    return rules[type]
}

errorAtCurrent :: proc(message: string) {
	errorAt(parser.current, message)
}

error :: proc(message: string) {
    errorAt(parser.previous, message)
}

errorAt :: proc(token: Token, message: string) {
    if parser.panicMode { return }
    parser.panicMode = true
    log.errorf("[line %v] Error", token.line)

    if token.type == .EOF {
        log.errorf(" at end")
    } else if token.type == .ERROR {
        // Nothing
    } else {
        log.errorf(" at '%v'", token.value)
    }

    log.errorf(": %v\n", message)
    parser.hadError = true
}