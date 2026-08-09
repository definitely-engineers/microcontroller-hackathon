; A non-leaf function must preserve the caller's link register on the stack.
LI    sp, #0x7C00
LI    r8, #0
CALL  add_two
HALT

add_two:
PUSH  lr
CALL  add_one
CALL  add_one
POP   lr
RET

add_one:
ADD   r8, r8, #1
RET
