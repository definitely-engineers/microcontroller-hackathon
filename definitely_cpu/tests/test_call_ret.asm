; Exercise relative CALL, absolute CALL, link-register writes, and RET.
LI    r8, #1
CALL  relative_func
MOV   r10, lr
CALL  #9
MOV   r12, lr
LI    r9, #7
HALT

relative_func:
LI    r8, #42
RET

absolute_func:
LI    r11, #17
RET
