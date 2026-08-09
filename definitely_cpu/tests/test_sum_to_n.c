// Workbook Stage 2 acceptance test.  Keep the loop visible at -O0 so the
// backend must lower CMP, <= and the back-edge rather than constant-folding
// the result.
int sum_to_n(int n) {
    int sum = 0;
    int i = 1;

    while (i <= n) {
        sum += i;
        i += 1;
    }

    return sum;
}
