// Force a fixed local stack frame so the compiler must allocate stack space,
// address frame-indexed objects, and restore SP before returning.
unsigned stack_roundtrip(unsigned left, unsigned right) {
    volatile unsigned slots[2];
    slots[0] = left;
    slots[1] = right;
    return slots[0] + slots[1];
}
