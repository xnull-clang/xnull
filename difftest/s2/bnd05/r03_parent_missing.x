protocol Base {
    Bool base();
}
protocol Ready : Base {
    Bool ready();
}
class C implements Ready {
    Bool ready() { return true }
}
static Int main() { return 0 }
