protocol Ready {
    Bool ready();
}
class C implements Ready {
    Int ready() { return 1 }
}
static Int main() { return 0 }
