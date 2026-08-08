; Verify that a forward JMP skips the instruction in between.
LI   r8, #1
JMP  skip
LI   r8, #99

skip:
LI   r9, #7
HALT
