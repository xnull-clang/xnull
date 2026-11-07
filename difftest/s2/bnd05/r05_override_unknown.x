protocol Ready {
    Bool ready();
}
class C implements Ready {
    Bool ready() { return true }
    @Override
    Bool nope() { return false }
}
static Int main() { return 0 }
