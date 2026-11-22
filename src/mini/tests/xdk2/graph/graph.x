import xdk.graph
static Int main() {
    Graph g = new Graph()
    g.addNode("a")
    g.addNode("b")
    GraphEdge e = new GraphEdge("a", "b", 1.0)
    g.addEdge(e)
    print(g.nodeCount())
    print(g.edgeCount())
    print(g.hasEdge("a", "b"))
    print(g.neighbors("a").get(0))
    print(g.bfs("a").length())
    print(g.hasCycle())
    Result<List<String>, Error> sorted = g.topologicalSort()
    print(sorted.isOk())
    print(sorted.value().get(0))
    Result<List<String>, Error> path = g.shortestPath("a", "b")
    print(path.isOk())
    print(path.value().get(1))
    return 0
}
