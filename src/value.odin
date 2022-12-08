package main

import "core:fmt"
import "core:log"
import "core:mem"


NAN_BOXING :: true

when NAN_BOXING {
    Value :: distinct u64

    SIGN_BIT : u64 : 0x8000000000000000
    QNAN     : u64 : 0x7ffc000000000000

    TAG_NIL   :: 1
    TAG_FALSE :: 2
    TAG_TRUE  :: 3

    IS_BOOL   :: proc(value: Value) -> bool { return (u64(value) | 1) == TRUE_VAL }
    IS_NIL    :: proc(value: Value) -> bool { return (value) == NIL_VAL() }
    IS_NUMBER :: proc(value: Value) -> bool { return (u64(value) & QNAN) != QNAN }
    IS_OBJ    :: proc(value: Value) -> bool { return (u64(value) & (QNAN | SIGN_BIT)) == (QNAN | SIGN_BIT)}

    AS_BOOL   :: proc(value: Value) -> bool { return u64(value) == TRUE_VAL }
    AS_NUMBER :: proc(value: Value) -> f64  { return transmute(f64) value }
    AS_OBJ    :: proc(value: Value) -> ^Obj { return cast(^Obj) uintptr(u64(value) & ~(SIGN_BIT | QNAN)) }

    FALSE_VAL  : u64 : QNAN | TAG_FALSE
    TRUE_VAL   : u64 : QNAN | TAG_TRUE
    BOOL_VAL   :: proc(b: bool)  -> Value { return Value(TRUE_VAL) if b else Value(FALSE_VAL) }
    NIL_VAL    :: proc()         -> Value { return Value(QNAN | TAG_NIL) }
    NUMBER_VAL :: proc(num: f64) -> Value { 
        // mem.copy(&value, &num, size_of(f64))
        return transmute(Value) num
    }
    OBJ_VAL    :: proc(obj: ^Obj) -> Value { return Value(SIGN_BIT | QNAN | cast(u64) uintptr(obj))}

} else {
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

    IS_BOOL   :: proc(value: Value) -> bool { return value.type == .BOOL }
    IS_NIL    :: proc(value: Value) -> bool { return value.type == .NIL }
    IS_NUMBER :: proc(value: Value) -> bool { return value.type == .NUMBER }
    IS_OBJ    :: proc(value: Value) -> bool { return value.type == .OBJ }

    AS_OBJ    :: proc(value: Value) -> ^Obj { return value.variant.(^Obj) }
    AS_BOOL   :: proc(value: Value) -> bool { return value.variant.(bool) }
    AS_NUMBER :: proc(value: Value) -> f64  { return value.variant.(f64) }

    BOOL_VAL   :: proc(value: bool) -> Value { return Value{.BOOL, value}}
    NIL_VAL    :: proc()            -> Value { return Value{.NIL, nil}}
    NUMBER_VAL :: proc(value: f64)  -> Value { return Value{.NUMBER, value}}
    OBJ_VAL    :: proc(value: ^Obj) -> Value { return Value{.OBJ, value}}
}

printValue :: proc(value: Value) {
    when NAN_BOXING {
        if (IS_BOOL(value)) {
            fmt.printf("true" if AS_BOOL(value) else "false")
        } else if (IS_NIL(value)) {
            fmt.printf("nil")
        } else if (IS_NUMBER(value)) {
            fmt.printf("%v", AS_NUMBER(value))
        } else if (IS_OBJ(value)) {
            printObject(AS_OBJ(value))
        }
    } else {
        #partial switch value.type {
            case .OBJ: printObject(AS_OBJ(value))
            case: fmt.print(value.variant)
        }
    }
}

valuesEqual :: proc(a, b: Value) -> bool {
    when NAN_BOXING {
        if (IS_NUMBER(a) && IS_NUMBER(b)) {
            return AS_NUMBER(a) == AS_NUMBER(b)
        }
        return a == b
    } else {
        if a.type != b.type { return false }
        switch a.type {
            case .BOOL:   return AS_BOOL(a) == AS_BOOL(b)
            case .NIL:    return true
            case .NUMBER: return AS_NUMBER(a) == AS_NUMBER(b)
            // case .OBJ:    return a.variant == b.variant // Valid because of string interning
            case .OBJ: return AS_OBJ(a) == AS_OBJ(b)
            case: return false // unreachable
        }
    }
}