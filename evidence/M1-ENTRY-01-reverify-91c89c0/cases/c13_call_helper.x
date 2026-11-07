static Int main(Int x) { return x + 1 }
static Int helper() { return main(41) }
static Int main() {
    print(helper())
    return 0
}
