class N { Int x = 0; }
static Int main() {
    N a = new N()
    N b = a
    a.x = 5
    print(b.x)
    return 0
}
