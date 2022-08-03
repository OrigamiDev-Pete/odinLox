//+private file
package main

import "core:log"
import "core:strconv"
import "core:strings"

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

ParseFn :: #type proc(canAssign: bool)

ParseRule :: struct {
    prefix: ParseFn,
    infix: ParseFn,
    precedence: Precedence,
}

U8_MAX :: cast(int)max(u8)

Local :: struct {
    name: Token,
    depth: int,
}

Compiler :: struct {
    locals: [U8_MAX + 1]Local,
    localCount: int,
    scopeDepth: int,
}

parser: Parser
current: ^Compiler = nil
compilingChunk: ^Chunk

currentChunk :: proc() -> ^Chunk {
    return compilingChunk
}


compile :: proc(source: string, chunk: ^Chunk) -> bool {
    initScanner(source)
    compiler: Compiler
    initCompiler(&compiler)
    compilingChunk = chunk

	advance()
	for (!match(.EOF)) {
        declaration()
    }
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

check :: proc(type: TokenType) -> bool {
    return parser.current.type == type
}

@(private = "file")
match :: proc(type: TokenType) -> bool {
    if !check(type) { return false }
    advance()
    return true
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

emitBytes_u8 :: proc(byte1: OpCode, byte2: u8) {
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
    emitBytes(OpCode.CONSTANT, makeConstant(value))
}

//

initCompiler :: proc(compiler: ^Compiler) {
    current = compiler
}

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

beginScope :: proc() {
    current.scopeDepth += 1
}

endScope :: proc() {
    current.scopeDepth -= 1

    for current.localCount > 0 && current.locals[current.localCount - 1].depth > current.scopeDepth {
        emitByte(OpCode.POP)
        current.localCount -= 1
    }
}

binary :: proc(canAssign: bool) {
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

literal :: proc(canAssign: bool) {
    #partial switch parser.previous.type {
        case .FALSE: emitByte(OpCode.FALSE)
        case .NIL:   emitByte(OpCode.NIL)
        case .TRUE:  emitByte(OpCode.TRUE)
    }
}

expression :: proc() {
    parsePrecedence(.ASSIGNMENT)
}

block :: proc() {
    for !check(.RIGHT_BRACE) && !check(.EOF) {
        declaration()
    }

    consume(.RIGHT_BRACE, "Expect '}' after block.")
}

varDeclaration :: proc() {
    global := parseVariable("Expect variable name.")

    if match(.EQUAL) {
        expression()
    } else {
        emitByte(OpCode.NIL)
    }
    consume(.SEMICOLON, "Expect ';' after variable declaration.")

    defineVariable(global)
}

expressionStatement :: proc() {
    expression()
    consume(.SEMICOLON, "Expect ';' after expression.")
    emitByte(OpCode.POP)
}

printStatement :: proc() {
    expression()
    consume(.SEMICOLON, "Expect ';' after value.")
    emitByte(OpCode.PRINT)
}

syncronize :: proc() {
    parser.panicMode = false

    for parser.current.type != .EOF {
        if parser.previous.type == .SEMICOLON { return }
        #partial switch parser.current.type {
            case .CLASS, .FUN, .VAR, .FOR, .IF, .WHILE, .PRINT, .RETURN: return
            case: // Do nothing
        }

        advance()
    }
}

declaration :: proc() {
    if match(.VAR) {
        varDeclaration()
    } else {
        statement()
    }

    if parser.panicMode { syncronize() }
}

statement :: proc() {
    if match(.PRINT) {
        printStatement()
    } else if match(.LEFT_BRACE) {
        beginScope()
        block()
        endScope()
    } else {
        expressionStatement()
    }
}

grouping :: proc(canAssign: bool) {
    expression()
    consume(.RIGHT_PAREN, "Expect ')' after expression.")
}

number :: proc(canAssign: bool) {
    value := strconv.atof(parser.previous.value)
    emitConstant(Value{.NUMBER, value})
}

lstring :: proc(canAssign: bool) {
    str := parser.previous.value[1:len(parser.previous.value)-1] // remove the "" from the string literal
    emitConstant(Value{ .OBJ, cast(^Obj) copyString(str) })
}

namedVariable :: proc(name: ^Token, canAssign: bool) {
    getOp, setOp: OpCode
    arg := resolveLocal(current, name)
    if arg != -1 {
        getOp = .GET_LOCAL
        setOp = .SET_LOCAL
    } else {
        arg = int(identifierConstant(name))
        getOp = .GET_GLOBAL
        setOp = .SET_GLOBAL
    }

    if canAssign && match(.EQUAL) {
        expression()
        emitBytes(setOp, u8(arg))
    } else {
        emitBytes(getOp, u8(arg))
    }

}

variable :: proc(canAssign: bool) {
    namedVariable(&parser.previous, canAssign)
}

unary :: proc(canAssign: bool) {
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
    TokenType.IDENTIFIER    = ParseRule{ variable, nil,    .NONE },
    TokenType.STRING        = ParseRule{ lstring,  nil,    .NONE },
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

    canAssign := precedence <= .ASSIGNMENT
    prefixRule(canAssign)

    for precedence <= getRule(parser.current.type).precedence {
        advance()
        infixRule := getRule(parser.previous.type).infix
        infixRule(canAssign)
    }

    if canAssign && match(.EQUAL) {
        error("Invalid assignment target.")
    }
}

identifierConstant :: proc(name: ^Token) -> u8 {
    return makeConstant(Value{.OBJ, cast(^Obj) copyString(name.value)})
}

identifiersEqual :: proc(a, b: ^Token) -> bool {
    if len(a.value) != len(b.value) { return false }
    return strings.compare(a.value, b.value) == 0
}

resolveLocal :: proc(compiler: ^Compiler, name: ^Token) -> int {
    for i := compiler.localCount-1; i >= 0; i -= 1 {
        local := &compiler.locals[i]
        if identifiersEqual(name, &local.name) {
            if local.depth == -1 {
                error("Can't read local variable in its own initializer.")
            }
            return i
        }
    }
    return -1
}

addLocal :: proc(name: Token) {
    if current.localCount == U8_MAX + 1 {
        error("Too many local variables in function.")
        return
    }

    local := &current.locals[current.localCount]
    current.localCount += 1
    local.name = name
    local.depth = -1
}

declareVariable :: proc() {
    if current.scopeDepth == 0 { return }

    name := &parser.previous
    for i := current.localCount-1; i >= 0; i -=1 {
        local := &current.locals[i]
        if local.depth != -1 && local.depth < current.scopeDepth {
            break
        }

        if identifiersEqual(name, &local.name) {
            error("Already a variable with this name in this scope.")
        }
    }
    addLocal(name^)
}

parseVariable :: proc(errorMessage: string) -> u8 {
    consume(.IDENTIFIER, errorMessage)

    declareVariable()
    if current.scopeDepth > 0 { return 0 }
    return identifierConstant(&parser.previous)
}

markInitialized :: proc() {
    current.locals[current.localCount-1].depth = current.scopeDepth
}

defineVariable :: proc(global: u8) {
    if current.scopeDepth > 0 {
        markInitialized()
        return
    }

    emitBytes(OpCode.DEFINE_GLOBAL, global)
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