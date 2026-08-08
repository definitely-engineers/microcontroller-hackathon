; CMP writes -1, 0, or 1 to r5. Conditional branches always read r5.
LI   r8, #7
LI   r9, #7
CMP  r5, r8, r9
JNZ  unexpected
JZ   equal_taken
LI   r10, #99
equal_taken:
LI   r10, #1

LI   r8, #9
CMP  r5, r8, r9
JLT  unexpected
JNZ  nonzero_taken
LI   r11, #99
nonzero_taken:
LI   r11, #1
JGT  greater_taken
LI   r12, #99
greater_taken:
LI   r12, #1

LI   r8, #3
CMP  r5, r8, r9
JLT  less_taken
LI   r13, #99
less_taken:
LI   r13, #1

; With r5=-1, neither JZ nor JGT should branch.
JZ   unexpected
LI   r14, #1
JGT  unexpected
LI   r15, #1
JMP  done

unexpected:
LI   r14, #99
LI   r15, #99

done:
HALT
