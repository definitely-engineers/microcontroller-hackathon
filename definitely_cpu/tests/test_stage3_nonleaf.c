__attribute__((noinline))
static int add_pair(int left, int right) {
    return left + right;
}

__attribute__((noinline))
int stage3_nonleaf(int value) {
    return add_pair(value, 22);
}
