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

emitByte_u8 :: proc(byte: u8) {
    writeChunk(currentChunk(), byte, parser.previous.line)
}

emitByte_OpCode :: proc(byte: OpCode) {
    writeChunk(currentChunk(), u8(byte), parser.previous.line)
}

emitByte :: proc {
    emitByte_u8,
    emitByte_OpCode,
}

emitBytes_u8 :: proc(byte1, byte2: u8) {
    emitByte(byte1)
    emitByte(byte2)
}

emitBytes_OpCode :: proc(byte1, byte2: OpCode) {
    emitByte(byte1)
    emitByte(byte2)
}

emitBytes :: proc {
    emitBytes_u8,
    emitBytes_OpCode,
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
        case .BANG_EQUAL:    emitBytes(OpCode.EQUAL, OpCode.NOT)
        case .EQUAL_EQUAL:   emitByte(OpCode.EQUAL)
        case .GREATER:       emitByte(OpCode.GREATER)
        case .GREATER_EQUAL: emitBytes(OpCode.LESS, OpCode.NOT)
        case .LESS:          emitByte(OpCode.LESS)
        case .LESS_EQUAL:    emitBytes(OpCode.GREATER, OpCode.NOT)
        case .PLUS:          emitByte(OpCode.ADD)
        case .MINUS:         emitByte(OpCode.SUBTRACT)
        case .STAR:          emitByte(OpCode.MULTIPLY)
        case .SLASH:         emitByte(OpCode.DIVIDE)
    }
}

literal :: proc() {
    #partial switch parser.previous.type {
        case .FALSE: emitByte(OpCode.FALSE)
        case .NIL:   emitByte(OpCode.NIL)
        case .TRUE:  emitByte(OpCode.TRUE)
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
    emitConstant(Value{.NUMBER, value})
}

lstring :: proc() {
    emitConstant(Value{ .OBJ, cast(^Obj) copyString(parser.previous.value) })
}

unary :: proc() {
    operatorType := parser.previous.type

    // Compile the operand
    parsePrecedence(.UNARY)

    // Emit the operator instruction
    #partial switch operatorType {
        case .BANG:  emitByte(OpCode.NOT)
        case .MINUS: emitByte(OpCode.NEGATE)
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
    TokenType.BANG          = ParseRule{ unary,    nil,    .NONE },
    TokenType.BANG_EQUAL    = ParseRule{ nil,      binary, .EQUALITY },
    TokenType.EQUAL         = ParseRule{ nil,      nil,    .NONE },
    TokenType.EQUAL_EQUAL   = ParseRule{ nil,      binary, .EQUALITY },
    TokenType.GREATER       = ParseRule{ nil,      binary, .COMPARISON },
    TokenType.GREATER_EQUAL = ParseRule{ nil,      binary, .COMPARISON },
    TokenType.LESS          = ParseRule{ nil,      binary, .COMPARISON },
    TokenType.LESS_EQUAL    = ParseRule{ nil,      binary, .COMPARISON },
    TokenType.IDENTIFIER    = ParseRule{ nil,      nil,    .NONE },
    TokenType.STRING        = ParseRule{ lstring,   nil,    .NONE },
    TokenType.NUMBER        = ParseRule{ number,   nil,    .NONE },
    TokenType.AND           = ParseRule{ nil,      nil,    .NONE },
    TokenType.CLASS         = ParseRule{ nil,      nil,    .NONE },
    TokenType.ELSE          = ParseRule{ nil,      nil,    .NONE },
    TokenType.FALSE         = ParseRule{ literal,  nil,    .NONE },
    TokenType.FOR           = ParseRule{ nil,      nil,    .NONE },
    TokenType.FUN           = ParseRule{ nil,      nil,    .NONE },
    TokenType.IF            = ParseRule{ nil,      nil,    .NONE },
    TokenType.NIL           = ParseRule{ literal,      nil,    .NONE },
    TokenType.OR            = ParseRule{ nil,      nil,    .NONE },
    TokenType.PRINT         = ParseRule{ nil,      nil,    .NONE },
    TokenType.RETURN        = ParseRule{ nil,      nil,    .NONE },
    TokenType.SUPER         = ParseRule{ nil,      nil,    .NONE },
    TokenType.THIS          = ParseRule{ nil,      nil,    .NONE },
    TokenType.TRUE          = ParseRule{ literal,      nil,    .NONE },
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