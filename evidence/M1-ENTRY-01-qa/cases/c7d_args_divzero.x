Int d = nargs()
Int a = 10 / d
static Int nargs() {
    return 0
}
static Int main(final String[] args) {
    print("MAIN-SHOULD-NOT-RUN a=" + str(a))
    return 0
}
