static Int main() {
    String ok = "abc"
    if (utf8Valid(ok) != 0) {
        return 3
    }
    String badPath = "/tmp/utf8probe/bad.bin"
    String bad = readFileText(badPath)
    if (utf8Valid(bad) == 0) {
        return 2
    }
    String okPath = "/tmp/utf8probe/ok.txt"
    String okFile = readFileText(okPath)
    if (utf8Valid(okFile) != 0) {
        return 4
    }
    return 0
}
