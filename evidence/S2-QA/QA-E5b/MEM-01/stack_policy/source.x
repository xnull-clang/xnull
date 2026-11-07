class ValueOnly { Int x = 1; }
class NeedsArc {
    Int x = 0;
    void deinit() { x = 1 }
}
static Int main() { return 0 }
