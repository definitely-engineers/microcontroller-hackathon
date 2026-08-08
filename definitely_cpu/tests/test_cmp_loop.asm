; Workbook Stage 2 loop: count from 0 to 5 with a backward JNZ.
LI   r8, #0
LI   r9, #5

loop:
ADD  r8, r8, #1
CMP  r5, r8, r9
JNZ  loop

HALT
