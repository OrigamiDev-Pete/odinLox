//+private file
package main

import "core:log"
import "core:strconv"
import "core:strings"

DEBUG_PRINT_CODE :: false

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
    isCaptured: bool,
}

Upvalue :: struct {
    index: u8,
    isLocal: bool,
}

FunctionType :: enum {
    FUNCTION,
    SCRIPT,
}

Compiler :: struct {
    enclosing: ^Compiler,
    function: ^ObjFunction,
    type: FunctionType,

    locals: [U8_MAX + 1]Local,
    localCount: int,
    upvalues: [U8_MAX + 1]Upvalue,
    scopeDepth: int,
}

parser: Parser
current: ^Compiler = nil
compilingChunk: ^Chunk

currentChunk :: proc() -> ^Chunk {
    return &current.function.chunk
}

compile :: proc(source: string) -> ^ObjFunction {
    initScanner(source)
    compiler: Compiler
    initCompiler(&compiler, .SCRIPT)

	advance()
	for !match(.EOF) {
        declaration()
    }
	consume(.EOF, "Expect end of expression.")
    function := endCompiler()
    return function if !parser.hadError else nil
}

markCompilerRoots :: proc() {
    compiler := current
    for compiler != nil {
        markObject(compiler.function)
        compiler = compiler.enclosing
    }
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

emitLoop :: proc(loopStart: int) {
    emitByte(OpCode.LOOP)

    offset := len(currentChunk().code) - loopStart + 2
    if offset > int(max(u16)) {
        error("Loop body too large.")
    }

    emitByte(u8((offset >> 8) & 0xff))
    emitByte(u8(offset & 0xff))
}

emitJump :: proc(instruction: OpCode) -> int {
    emitByte(instruction)
    emitByte(0xff)
    emitByte(0xff)
    return len(currentChunk().code) - 2
}

emitReturn :: proc() {
    emitByte(OpCode.NIL)
    emitByte(OpCode.RETURN)
    // writeChunk(currentChunk(), OpCode.RETURN, parser.previous.line)
}

emitConstant :: proc(value: Value) {
    emitBytes(OpCode.CONSTANT, makeConstant(value))
}

patchJump :: proc(offset: int) {
    // -2 to adjust for the bytecode for the jump offset itself.
    jump := len(currentChunk().code) - offset - 2

    if jump > int(max(u16)) {
        error("Too much code to jump over.")
    }

    currentChunk().code[offset] =  u8((jump >> 8) & 0xff)
    currentChunk().code[offset + 1] = u8(jump & 0xff)
}

//

initCompiler :: proc(compiler: ^Compiler, type: FunctionType) {
    compiler.enclosing = current
    compiler.type = type
    compiler.function = newFunction()
    current = compiler

    if type != .SCRIPT {
        current.function.name = copyString(parser.previous.value)
    }

    local := &current.locals[current.localCount]
    current.localCount += 1
    local.depth = 0
    local.name.value = ""
}

makeConstant :: proc(value: Value) -> u8 {
    constant := addConstant(currentChunk(), value)
    if constant > U8_MAX {
        error("Too many constants in one chunk.")
        return 0
    }

    return cast(u8) constant
}

endCompiler :: proc() -> ^ObjFunction {
    emitReturn()
    function := current.function

    when DEBUG_PRINT_CODE {
        if !parser.hadError {
            disassembleChunk(currentChunk()^, function.name.str if function.name != nil  else "<script>")
        }
    }

    current = current.enclosing
    return function
}

beginScope :: proc() {
    current.scopeDepth += 1
}

endScope :: proc() {
    current.scopeDepth -= 1

    for current.localCount > 0 && current.locals[current.localCount - 1].depth > current.scopeDepth {
        if current.locals[current.localCount - 1].isCaptured {
            emitByte(OpCode.CLOSE_UPVALUE)
        } else {
            emitByte(OpCode.POP)
        }
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

call :: proc(canAssign: bool) {
    argCount := argumentList()
    emitBytes(.CALL, argCount)
}

dot :: proc(canAssign: bool) {
    consume(.IDENTIFIER, "Expect property name after '.'.")
    name := identifierConstant(&parser.previous)

    if canAssign && match(.EQUAL) {
        expression()
        emitBytes(OpCode.SET_PROPERTY, name)
    } else {
        emitBytes(OpCode.GET_PROPERTY, name)
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

function :: proc(type: FunctionType) {
    compiler: Compiler
    initCompiler(&compiler, type)
    beginScope()
    
    consume(.LEFT_PAREN, "Expect '(' after function name.")
    if !check(.RIGHT_PAREN) {
        for {
            current.function.arity += 1
            if current.function.arity > 255 {
                errorAtCurrent("Can't have more than 255 parameters.")
            }
            constant := parseVariable("Expect parameter name.")
            defineVariable(constant)

            if !match(.COMMA) { break }
        }
    }
    consume(.RIGHT_PAREN, "Expect ')' after parameters.")
    consume(.LEFT_BRACE, "Expect '{' before function body.")
    block()

    function := endCompiler()
    emitBytes(OpCode.CLOSURE, makeConstant(Value{.OBJ, cast(^Obj) function}))

    for i in 0..<function.upvalueCount {
        emitByte_u8(1 if compiler.upvalues[i].isLocal else 0)
        emitByte(compiler.upvalues[i].index)
    }
}

classDeclaration :: proc() {
    consume(.IDENTIFIER, "Expect class name.")
    nameConstant := identifierConstant(&parser.previous)
    declareVariable()

    emitBytes(OpCode.CLASS, nameConstant)
    defineVariable(nameConstant)

    consume(.LEFT_BRACE, "Expect '{' before class body.")
    consume(.RIGHT_BRACE, "Expect '}' after class body.")
}

funDeclaration :: proc() {
    global := parseVariable("Expect function name.")
    markInitialized()
    function(.FUNCTION)
    defineVariable(global)
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

forStatement :: proc() {
    beginScope()
    consume(.LEFT_PAREN, "Expect '(' after 'for'.")
    if match(.SEMICOLON) {
        // No initializer.
    } else if match(.VAR) {
        varDeclaration()
    } else {
        expressionStatement()
    }

    loopStart := len(currentChunk().code)
    exitJump := -1
    if !match(.SEMICOLON) {
        expression()
        consume(.SEMICOLON, "Expect ';' after loop condition.")

        // Jump out of the loop if the condition is false.
        exitJump = emitJump(.JUMP_IF_FALSE)
        emitByte(OpCode.POP)
    }

    if !match(.RIGHT_PAREN) {
        bodyJump := emitJump(.JUMP)
        incrementStart := len(currentChunk().code)
        expression()
        emitByte(OpCode.POP)
        consume(.RIGHT_PAREN, "Expect ')' after for clauses.")

        emitLoop(loopStart)
        loopStart = incrementStart
        patchJump(bodyJump)
    }

    statement()
    emitLoop(loopStart)

    if exitJump != -1 {
        patchJump(exitJump)
        emitByte(OpCode.POP)
    }
    endScope()
}

ifStatement :: proc() {
    consume(.LEFT_PAREN, "Expect '(' after 'if'.")
    expression()
    consume(.RIGHT_PAREN, "Expect ')' after condition.")

    thenJump := emitJump(OpCode.JUMP_IF_FALSE)
    emitByte(OpCode.POP)
    statement()

    elseJump := emitJump(OpCode.JUMP)

    patchJump(thenJump)
    emitByte(OpCode.POP)

    if match(.ELSE) {
        statement()
    }
    patchJump(elseJump)
}

printStatement :: proc() {
    expression()
    consume(.SEMICOLON, "Expect ';' after value.")
    emitByte(OpCode.PRINT)
}

returnStatement :: proc() {
    if current.type == .SCRIPT {
        error("Can't return from  top-level code.")
    }

    if match(.SEMICOLON) {
        emitReturn()
    } else {
        expression()
        consume(.SEMICOLON, "Expect ';' after return value.")
        emitByte(OpCode.RETURN)
    }
}

whileStatement :: proc() {
    loopStart := len(currentChunk().code)
    consume(.LEFT_PAREN, "Expect '(' after 'while'.")
    expression()
    consume(.RIGHT_PAREN, "Expect ')' after condition.")

    exitJump := emitJump(.JUMP_IF_FALSE)
    emitByte(OpCode.POP)
    statement()
    emitLoop(loopStart)

    patchJump(exitJump)
    emitByte(OpCode.POP)
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
    if match(.CLASS) {
        classDeclaration()
    } else if match(.FUN) {
        funDeclaration()
    } else if match(.VAR) {
        varDeclaration()
    } else {
        statement()
    }

    if parser.panicMode { syncronize() }
}

statement :: proc() {
    if match(.PRINT) {
        printStatement()
    } else if match(.FOR) {
        forStatement()
    } else if match(.IF) {
        ifStatement()
    } else if match(.RETURN) {
        returnStatement()
    } else if match(.WHILE) {
        whileStatement()
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

or_ :: proc(canAssign: bool) {
    elseJump := emitJump(.JUMP_IF_FALSE)
    endJump := emitJump(.JUMP)

    patchJump(elseJump)
    emitByte(OpCode.POP)

    parsePrecedence(.OR)
    patchJump(endJump)
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
    } else if arg = resolveUpvalue(current, name); arg != -1 {
        getOp = .GET_UPVALUE
        setOp = .SET_UPVALUE
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
    TokenType.LEFT_PAREN    = ParseRule{ grouping, call,   .CALL },
    TokenType.RIGHT_PAREN   = ParseRule{ nil,      nil,    .NONE },
    TokenType.LEFT_BRACE    = ParseRule{ nil,      nil,    .NONE },
    TokenType.RIGHT_BRACE   = ParseRule{ nil,      nil,    .NONE },
    TokenType.COMMA         = ParseRule{ nil,      nil,    .NONE },
    TokenType.DOT           = ParseRule{ nil,      dot,    .CALL },
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
    TokenType.AND           = ParseRule{ nil,      and_,    .AND },
    TokenType.CLASS         = ParseRule{ nil,      nil,    .NONE },
    TokenType.ELSE          = ParseRule{ nil,      nil,    .NONE },
    TokenType.FALSE         = ParseRule{ literal,  nil,    .NONE },
    TokenType.FOR           = ParseRule{ nil,      nil,    .NONE },
    TokenType.FUN           = ParseRule{ nil,      nil,    .NONE },
    TokenType.IF            = ParseRule{ nil,      nil,    .NONE },
    TokenType.NIL           = ParseRule{ literal,  nil,    .NONE },
    TokenType.OR            = ParseRule{ nil,      or_,    .OR   },
    TokenType.PRINT         = ParseRule{ nil,      nil,    .NONE },
    TokenType.RETURN        = ParseRule{ nil,      nil,    .NONE },
    TokenType.SUPER         = ParseRule{ nil,      nil,    .NONE },
    TokenType.THIS          = ParseRule{ nil,      nil,    .NONE },
    TokenType.TRUE          = ParseRule{ literal,  nil,    .NONE },
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

addUpvalue :: proc(compiler: ^Compiler, index: u8, isLocal: bool) -> int {
    upvalueCount := &compiler.function.upvalueCount

    for i in 0..<upvalueCount^ {
        upvalue := &compiler.upvalues[i]
        if upvalue.index == index && upvalue.isLocal == isLocal {
            return i
        }
    }

    if upvalueCount^ == U8_MAX {
        error("Too many closure variables in function.")
        return 0
    }

    compiler.upvalues[upvalueCount^].isLocal = isLocal
    compiler.upvalues[upvalueCount^].index = index
    upvalueCount^ += 1
    return upvalueCount^
}

resolveUpvalue :: proc(compiler: ^Compiler, name: ^Token) -> int {
    if compiler.enclosing == nil { return -1 }

    local := resolveLocal(compiler.enclosing, name)
    if local != -1 {
        compiler.enclosing.locals[local].isCaptured = true
        return addUpvalue(compiler, u8(local), true)
    }

    upvalue := resolveUpvalue(compiler.enclosing, name)
    if upvalue != -1 {
        return addUpvalue(compiler, u8(upvalue), false)
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
    if current.scopeDepth == 0 { return }
    current.locals[current.localCount-1].depth = current.scopeDepth
}

defineVariable :: proc(global: u8) {
    if current.scopeDepth > 0 {
        markInitialized()
        return
    }

    emitBytes(OpCode.DEFINE_GLOBAL, global)
}

argumentList :: proc() -> u8 {
    argCount: u8 = 0
    if !check(.RIGHT_PAREN) {
        for {
            expression()
            if argCount == 255 {
                error("Can't have more than 255 arguments.")
            }
            argCount += 1
            if !match(.COMMA) { break }
        }
    }
    consume(.RIGHT_PAREN, "Expect ')' after arguments.")
    return argCount
}

and_ :: proc(canAssign: bool) {
    endJump := emitJump(.JUMP_IF_FALSE)

    emitByte(OpCode.POP)
    parsePrecedence(.AND)

    patchJump(endJump)
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