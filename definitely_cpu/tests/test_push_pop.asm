; Verify pre-decrement PUSH, post-increment POP, and LIFO ordering.
LI    sp, #0x7C00
LI    r8, #0x1111
LI    r9, #0x2222
PUSH  r8
PUSH  r9
LI    r8, #0
LI    r9, #0
POP   r10
POP   r11
HALT
