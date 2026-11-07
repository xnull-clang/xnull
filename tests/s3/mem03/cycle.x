class N { N? next; Int x = 1; }
static Int main() {
    N a = new N()
    N b = new N()
    a.next = b
    b.next = a
    a.x = 7
    print(a.next.next.x)
    return 0
}
