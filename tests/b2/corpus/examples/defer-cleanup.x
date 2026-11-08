// defer-cleanup.x —— defer/errdefer 清理语义（S1 §10.3）
// 预期输出：
//   A
//   B
//   C
//   inner cleanup
//   D
//   cleanup 2
//   cleanup 1
//   ---
//   ok path: 5
//   defer: run exits
//   ---
//   errdefer: error path
//   defer: run exits
//   recovered: neg

static Int work() {
    print("A")
    defer print("cleanup 1")
    defer print("cleanup 2")
    if true {
        print("B")
        defer print("inner cleanup")   // 块退出即执行
        print("C")
    }
    print("D")                          // 此处 inner cleanup 已执行
    return 0                            // 函数退出时 cleanup 2 → cleanup 1（LIFO）
}

static Result<Int, String> maybe(Int n) {
    if n < 0 {
        return Err("neg")
    }
    return Ok(n)
}

static Result<Int, String> run(Int n) {
    defer print("defer: run exits")
    errdefer print("errdefer: error path")   // 仅错误路径执行（§10.3）
    Int v = try maybe(n)
    print("ok path: " + str(v))
    return Ok(v)
}

static Int main() {
    work()
    print("---")
    Result<Int, String> a = run(5)
    print("---")
    Result<Int, String> b = run(-7)
    print("recovered: " + b.error())
    return 0
}
