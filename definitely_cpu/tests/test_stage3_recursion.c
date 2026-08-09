__attribute__((noinline))
int stage3_recursive_sum(int value) {
    if (value <= 0)
        return 0;
    return value + stage3_recursive_sum(value - 1);
}
