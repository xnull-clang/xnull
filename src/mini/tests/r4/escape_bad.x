// Negative case: S1 §1.4.3 rejects unknown escapes as lexical errors.
static Int main() {
    String bad = "\q"
    print(bad.length())
    return 0
}
