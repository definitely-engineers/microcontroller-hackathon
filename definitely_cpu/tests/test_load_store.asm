; Exercise word and byte memory operations in both addressing modes.
; LOADB is zero-extending and word accesses are little-endian.

; Absolute word store/load and byte reads from the stored word.
LI      r8, #0x1234
STORE   r8, [0x0100]
LOAD    r9, [0x0100]
LOADB   r10, [0x0100]
LOADB   r11, [0x0101]

; Register-indirect word access with a positive signed offset.
LI      r12, #0x0108
LI      r13, #0xABCD
STORE   r13, [r12 + 4]
LOAD    r14, [r12 + 4]

; Register-indirect byte access with a negative signed offset.
LI      r15, #0x55
STOREB  r15, [r12 - 4]
LOADB   r16, [r12 - 4]

; A byte store changes only one byte of an existing word.
LI      r17, #0x1122
STORE   r17, [0x0110]
LI      r18, #0xAA
STOREB  r18, [0x0111]
LOAD    r19, [0x0110]

HALT
