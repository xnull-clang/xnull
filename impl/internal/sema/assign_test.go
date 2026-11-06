package sema

import "testing"

// ---------- §5.3 确定赋值 ----------

func TestDABasic(t *testing.T) {
	// 读取前已赋值：通过
	expectNone(t, "static Int main() {\n    Int x = 1\n    print(str(x))\n    return 0\n}")
	// 声明后未赋值、未读取：合法（§5.3 末条）
	expectNone(t, "static Int main() {\n    Int x\n    x = 5\n    print(str(x))\n    return 0\n}")
	// 声明后未赋值即读取：DA-101
	expectCode(t, "static Int main() {\n    Int x\n    print(str(x))\n    return 0\n}", DaMaybeUnassigned)
	// 赋值前读取：DA-101
	expectCode(t, "static Int main() {\n    Int x\n    Int y = x + 1\n    return 0\n}", DaMaybeUnassigned)
	// 复合赋值先读后写
	expectCode(t, "static Int main() {\n    Int x\n    x += 1\n    return 0\n}", DaMaybeUnassigned)
	// 自增先读后写
	expectCode(t, "static Int main() {\n    Int x\n    x++\n    return 0\n}", DaMaybeUnassigned)
}

func TestDABranchMerge(t *testing.T) {
	// if/else 都赋值：通过
	expectNone(t, `
static Int f(Bool c) {
    Int x
    if c {
        x = 1
    } else {
        x = 2
    }
    return x
}

static Int main() { return 0 }`)
	// 只有 if 分支赋值：DA-101
	expectCode(t, `
static Int f(Bool c) {
    Int x
    if c {
        x = 1
    }
    return x
}

static Int main() { return 0 }`, DaMaybeUnassigned)
	// 无初始化的 while 体赋值：循环可能零次 → DA-101
	expectCode(t, `
static Int f() {
    Int x
    while false {
        x = 1
    }
    return x
}

static Int main() { return 0 }`, DaMaybeUnassigned)
	// do-while 体至少执行一次：通过
	expectNone(t, `
static Int f() {
    Int x
    do {
        x = 1
    } while false
    return x
}

static Int main() { return 0 }`)
	// return 后不可达：不要求赋值
	expectNone(t, `
static Int f(Bool c) {
    Int x
    if c {
        return 0
    }
    x = 1
    return x
}

static Int main() { return 0 }`)
	// throw 后不可达
	expectNone(t, `
static Int f(Bool c) {
    if c {
        throw "x"
    }
    Int x = 1
    return x
}

static Int main() { return 0 }`)
	// while true 无 break：循环后不可达
	expectNone(t, `
static Int f() {
    while true {
        print("loop")
    }
    return 0
}

static Int main() { return 0 }`)
}

func TestDAFinalConst(t *testing.T) {
	// const 声明处初始化后不得再赋值：DA-102
	expectCode(t, `
static Int main() {
    const Int x = 1
    x = 2
    return x
}`, DaReassign)
	// final 声明处初始化后不得再赋值
	expectCode(t, `
static Int main() {
    final Int x = 1
    x = 2
    return x
}`, DaReassign)
	// 复合赋值也算赋值
	expectCode(t, `
static Int main() {
    final Int x = 1
    x += 1
    return x
}`, DaReassign)
	// var 可重复赋值：通过
	expectNone(t, `
static Int main() {
    var x = 1
    x = 2
    return x
}`)
	// 无初始化的 final 声明后赋值一次：通过
	expectNone(t, `
static Int main() {
    final Int x
    x = 1
    return x
}`)
}

func TestDAReturnPath(t *testing.T) {
	// 非 void 函数所有路径返回：通过
	expectNone(t, "static Int f(Bool c) {\n    if c {\n        return 1\n    }\n    return 2\n}\n\nstatic Int main() { return 0 }")
	// 缺 return：DA-103
	expectCode(t, "static Int f(Bool c) {\n    if c {\n        return 1\n    }\n}\n\nstatic Int main() { return 0 }", DaMissingReturn)
	// 顺流到底缺 return
	expectCode(t, "static Int f() {\n    print(\"x\")\n}\n\nstatic Int main() { return 0 }", DaMissingReturn)
	// void 函数不要求 return
	expectNone(t, "static void f() {\n    print(\"x\")\n}\n\nstatic Int main() { return 0 }")
	// throw 结尾：路径必然退出
	expectNone(t, "static Int f() {\n    throw \"x\"\n}\n\nstatic Int main() { return 0 }")
	// try 传播路径不算正常路径（§5.3：try 的错误返回路径不要求后续赋值）
	expectNone(t, `
static Result<Int, String> g() {
    return Err("e")
}

static Result<Int, String> f() {
    Int v = try g()
    return Ok(v)
}

static Int main() { return 0 }`)
}
