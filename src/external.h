#ifndef THERMIT_H
#define THERMIT_H

#include <stdint.h>

#define Terminal void*

enum { Key, Resize, None, Error } EventType;

#define KeyEvent uint16_t
// pub const KeyEvent = inner.KeyEvent;

struct {
    // enum EventType event_type;
    /// Data only Valid if EventType is Key
    // KeyEvent key;
} Event;


// __attribute__((__nonnull__))
// void terminalRead(Terminal terminal, int32_t timeout, Event *ev);


// pub const ThermitError = enum(u8) {
//     None = 0,
//     Generic = 1,
// };
// pub export const ThermitErrorNone: u8 = 0;
// pub export const ThermitErrorGeneric: u8 = 1;

#endif /* THERMIT_H */
