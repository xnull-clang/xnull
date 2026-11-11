// lib-core：库模块（B4b-03b-1 只验证"能独立编成对象并被 app 链接"）。
static Int coreAdd(Int a, Int b) {
    return a + b
}

static Int main() {
    return coreAdd(40, 2)
}
