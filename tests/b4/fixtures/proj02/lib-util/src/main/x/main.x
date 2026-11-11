// lib-util：只被 lib-codec 依赖的传递依赖（tree/why 用）。
static Int utilOne() {
    return 1
}

static Int main() {
    return utilOne()
}
