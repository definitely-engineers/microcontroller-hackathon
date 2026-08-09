__attribute__((noinline))
int stage3_fib(int value) {
    if (value <= 1)
        return value;
    return stage3_fib(value - 1) + stage3_fib(value - 2);
}
