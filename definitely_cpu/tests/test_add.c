// test_add.c — Stage 1 的目标程序
//
// workbook Stage 1 "Test: Compile and Run" 的测试程序。
//
// noinline 是为了防止编译器把函数内联掉——我们要的就是一次真实的函数调用，
// 好验证参数传递和返回值走的是约定好的寄存器（r8/r9 传参，r8 返回）。
//
// 用 args: [21, 21] 调用，期望返回 42。

__attribute__((noinline))
int add(int a, int b) {
    return a + b;
}
