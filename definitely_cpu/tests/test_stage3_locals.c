__attribute__((noinline))
static int double_local(int value) {
    return value + value;
}

__attribute__((noinline))
int stage3_locals(int value) {
    volatile int local = value + 1;
    return double_local(local);
}
