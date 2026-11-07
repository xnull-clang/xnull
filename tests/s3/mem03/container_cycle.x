class N { List<N> kids = []; Int x = 1; }
static Int main() {
    N a = new N()
    N b = new N()
    a.kids.push(b)
    b.kids.push(a)
    print(a.kids.get(0).x)
    return 0
}
