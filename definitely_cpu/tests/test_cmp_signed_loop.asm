; Workbook Stage 2 signed loop: 10 -> 7 -> 4 -> 1 -> -2.
LI   r8, #10

loop:
SUB  r8, r8, #3
CMP  r5, r8, r0
JGT  loop

HALT
