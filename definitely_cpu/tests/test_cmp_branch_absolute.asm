; If the RI bit is honoured, JGT jumps to absolute instruction address 5.
LI   r8, #9
LI   r9, #7
CMP  r5, r8, r9
JGT  #5
LI   r16, #99
LI   r16, #1
HALT
