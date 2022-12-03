package main

import "core:mem"
import "core:strings"

TABLE_MAX_LOAD :: 0.75

Entry :: struct {
    key: ^ObjString,
    value: Value,
}

Table :: struct {
    count: int,
    capacity: int,
    entries: []Entry,
}

freeTable :: proc(table: ^Table) {
    delete(table.entries)
}

tableSet :: proc(table: ^Table, key: ^ObjString, value: Value) -> bool {
    if f32(table.count + 1) > f32(table.capacity) * TABLE_MAX_LOAD {
        capacity := growCapacity(table.capacity)
        adjustCapacity(table, capacity)
    }

    entry := findEntry(table.entries, table.capacity, key)
    isNewKey := entry.key == nil
    if isNewKey && entry.value.type == .NIL { table.count += 1 }

    entry.key = key
    entry.value = value
    return isNewKey
}

tableDelete :: proc(table: ^Table, key: ^ObjString) -> bool {
    if table.count == 0 { return false }

    entry := findEntry(table.entries, table.capacity, key)
    if entry.key == nil { return false }

    entry.key = nil
    entry.value = Value{.BOOL, true}
    return true
}

tableAddAll :: proc(from, to: ^Table) {
    for i in 0..<from.capacity {
        entry := &from.entries[i]
        if entry.key != nil {
            tableSet(to, entry.key, entry.value)
        }
    }
}

tableFindString :: proc(table: ^Table, str: string, hash: u32) -> ^ObjString {
    if table.count == 0 { return nil }

    index := hash % u32(table.capacity)
    for {
        entry := &table.entries[index]
        if entry.key == nil {
            // Stop if we find an empty non-tombstone entry.
            if entry.value.type == .NIL { return nil }
        } else if len(entry.key.str) == len(str) && entry.key.hash == hash && strings.compare(entry.key.str, str) == 0 {
            // We found it.
            return entry.key
        }

        index = (index + 1) % u32(table.capacity)
    }
}

tableRemoveWhite :: proc(table: ^Table) {
    for entry in table.entries {
        if entry.key != nil && !entry.key.obj.isMarked {
            tableDelete(table, entry.key)
        }
    }
}

markTable :: proc(table: ^Table) {
    for i in 0..<table.capacity {
        entry := &table.entries[i]
        markObject(entry.key)
        markValue(entry.value)
    }
}

findEntry :: proc(entries: []Entry, capacity: int, key: ^ObjString) -> ^Entry {
    index := key.hash % u32(capacity)
    tombstone: ^Entry = nil
    for {
        entry := &entries[index]
        if entry.key == nil {
            if entry.value.type == .NIL {
                // Empty entry.
                return tombstone if tombstone != nil else entry
            } else {
                // We found a tombstone
                if tombstone == nil { tombstone = entry }
            }
        } if entry.key == key {
            // We found the key.
            return entry
        }

        index = (index + 1) % u32(capacity)
    }
}

tableGet :: proc(table: ^Table, key: ^ObjString) -> (Value, bool) {
    if table.count == 0 { return {}, false }

    entry := findEntry(table.entries, table.capacity, key)
    if entry.key == nil { return {}, false }

    return entry.value, true
}

adjustCapacity :: proc(table: ^Table, capacity: int) {
    entries := make([]Entry, capacity)
    for i in 0..<capacity {
        entries[i].key = nil
        entries[i].value = Value{.NIL, nil}
    }

    table.count = 0
    for i in 0..<table.capacity {
        entry := &table.entries[i]
        if entry.key == nil { continue }

        dest := findEntry(entries, capacity, entry.key)
        dest.key = entry.key
        dest.value = entry.value
        table.count += 1
    }

    delete(table.entries)
    table.entries = entries
    table.capacity = capacity
}

growCapacity :: proc(capacity: int) -> int {
    return 8 if capacity < 8 else capacity * 2
}
