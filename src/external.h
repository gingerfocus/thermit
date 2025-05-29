#ifndef THERMIT_H
#define THERMIT_H

#include <stdint.h>

typedef enum {
    EventTypeKey,
    EventTypeResize,
    EventTypeNone,
    EventTypeTimeout,
    // EventTypeError 
} EventType;

typedef uint16_t KeyEvent;

typedef struct __Terminal Terminal;

typedef struct {
    EventType event_type;
    /// Data only Valid if EventType is Key
    KeyEvent key;
} Event;

typedef enum {
    ThermitErrorNone,
    ThermitErrorGeneric
} ThermitError;

// __attribute__((__nonnull__)) 
ThermitError
terminalRead(Terminal *terminal, int32_t timeout, Event *ev);


#endif /* THERMIT_H */
