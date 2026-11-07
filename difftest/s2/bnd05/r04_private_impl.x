protocol Ready {
    Bool ready();
}
class C implements Ready {
    private Bool ready() { return true }
}
static Int main() { return 0 }
