#ifndef THERMIT_H
#define THERMIT_H

#include <stdint.h>

#define Event uint64_t
#define Terminal void*

// __attribute__((__nonnull__))
void terminalRead(Terminal terminal, int32_t timeout, Event *ev);

#endif /* THERMIT_H */
