// xdk.graph — single-threaded directed simple graph (String-node baseline).
// Tier: L4；依赖：xdk.errors、xdk.collections、xdk.math；稳定性：preview。
package xdk.graph
import xdk.errors
import xdk.collections
import xdk.math

class GraphEdge {
    final String fromNode
    final String toNode
    final Double weightValue

    GraphEdge(String from, String to, Double weight) {
        if from == null || to == null { throw "GraphEdge: null endpoint" }
        if !isFinite(weight) { throw "GraphEdge: non-finite weight" }
        self.fromNode = from
        self.toNode = to
        self.weightValue = weight
    }

    String from() { return self.fromNode }
    String to() { return self.toNode }
    Double weight() { return self.weightValue }
    Bool isSelfLoop() { return self.fromNode == self.toNode }
    String describe() { return self.fromNode + " -> " + self.toNode + " (weight=" + str(self.weightValue) + ")" }
}

class Graph {
    final List<String> _nodes
    final List<GraphEdge> _edges

    Graph() { self._nodes = []; self._edges = [] }

    Int nodeIndex(String node) {
        Int index = 0
        while index < self._nodes.length() {
            if self._nodes.get(index) == node { return index }
            index = index + 1
        }
        return -1
    }

    Void addNode(String node) {
        if node == null { throw "Graph.addNode: null node" }
        if self.nodeIndex(node) >= 0 { return }
        self._nodes.push(node)
    }
    Bool hasNode(String node) { if node == null { return false } return self.nodeIndex(node) >= 0 }
    Bool hasEdge(String source, String target) {
        if source == null || target == null { return false }
        Int index = 0
        while index < self._edges.length() {
            GraphEdge edge = self._edges.get(index)
            if edge.fromNode == source && edge.toNode == target { return true }
            index = index + 1
        }
        return false
    }
    Void addEdge(GraphEdge edge) {
        if edge == null { throw "Graph.addEdge: null edge" }
        if !self.hasNode(edge.fromNode) || !self.hasNode(edge.toNode) { throw "Graph.addEdge: unknown endpoint" }
        if self.hasEdge(edge.fromNode, edge.toNode) { throw "Graph.addEdge: duplicate ordered pair" }
        self._edges.push(edge)
    }
    Void removeNode(String node) {
        if node == null { throw "Graph.removeNode: null node" }
        Int index = self._edges.length() - 1
        while index >= 0 {
            GraphEdge edge = self._edges.get(index)
            if edge.fromNode == node || edge.toNode == node { self._edges.remove(index) }
            index = index - 1
        }
        Int nodeIndex = self.nodeIndex(node)
        if nodeIndex >= 0 { self._nodes.remove(nodeIndex) }
    }
    Void removeEdge(String source, String target) {
        if source == null || target == null { throw "Graph.removeEdge: null endpoint" }
        Int index = 0
        while index < self._edges.length() {
            GraphEdge edge = self._edges.get(index)
            if edge.fromNode == source && edge.toNode == target { self._edges.remove(index); return }
            index = index + 1
        }
    }
    List<String> nodes() { return self._nodes.copy() }
    Int nodeCount() { return self._nodes.length() }
    Int edgeCount() { return self._edges.length() }
    List<String> neighbors(String node) {
        if node == null || !self.hasNode(node) { throw "Graph.neighbors: unknown node" }
        List<String> result = []
        Int index = 0
        while index < self._edges.length() {
            GraphEdge edge = self._edges.get(index)
            if edge.fromNode == node { result.push(edge.toNode) }
            index = index + 1
        }
        return result
    }
    List<String> bfs(String start) {
        if start == null || !self.hasNode(start) { throw "Graph.bfs: unknown start" }
        List<String> result = []
        List<String> queue = []
        queue.push(start)
        result.push(start)
        Int head = 0
        while head < queue.length() {
            String current = queue.get(head)
            head = head + 1
            List<String> next = self.neighbors(current)
            Int index = 0
            while index < next.length() {
                String candidate = next.get(index)
                Bool seen = false
                Int scan = 0
                while scan < result.length() {
                    if result.get(scan) == candidate { seen = true; break }
                    scan = scan + 1
                }
                if !seen { result.push(candidate); queue.push(candidate) }
                index = index + 1
            }
        }
        return result
    }
    List<String> dfs(String start) {
        if start == null || !self.hasNode(start) { throw "Graph.dfs: unknown start" }
        List<String> result = []
        List<String> stack = []
        stack.push(start)
        while stack.length() > 0 {
            String current = stack.get(stack.length() - 1)
            stack.remove(stack.length() - 1)
            Bool seen = false
            Int scan = 0
            while scan < result.length() {
                if result.get(scan) == current { seen = true; break }
                scan = scan + 1
            }
            if seen { continue }
            result.push(current)
            List<String> next = self.neighbors(current)
            Int index = next.length() - 1
            while index >= 0 { stack.push(next.get(index)); index = index - 1 }
        }
        return result
    }
    Bool hasCycle() {
        List<Int> state = []
        Int index = 0
        while index < self._nodes.length() { state.push(0); index = index + 1 }
        index = 0
        while index < self._nodes.length() {
            if state.get(index) == 0 {
                if self.visitCycle(index, state) { return true }
            }
            index = index + 1
        }
        return false
    }
    Bool visitCycle(Int startIndex, List<Int> state) {
        List<Int> nodeStack = []
        List<Int> edgeStack = []
        nodeStack.push(startIndex)
        edgeStack.push(0)
        state.set(startIndex, 1)
        while nodeStack.length() > 0 {
            Int current = nodeStack.get(nodeStack.length() - 1)
            Int edgeIndex = edgeStack.get(edgeStack.length() - 1)
            if edgeIndex >= self._edges.length() {
                state.set(current, 2)
                nodeStack.remove(nodeStack.length() - 1)
                edgeStack.remove(edgeStack.length() - 1)
                continue
            }
            edgeStack.set(edgeStack.length() - 1, edgeIndex + 1)
            GraphEdge edge = self._edges.get(edgeIndex)
            if edge.fromNode != self._nodes.get(current) { continue }
            Int target = self.nodeIndex(edge.toNode)
            if state.get(target) == 1 { return true }
            if state.get(target) == 0 {
                state.set(target, 1)
                nodeStack.push(target)
                edgeStack.push(0)
            }
        }
        return false
    }
    Result<List<String>, Error> topologicalSort() {
        List<Int> indegree = []
        Int index = 0
        while index < self._nodes.length() { indegree.push(0); index = index + 1 }
        index = 0
        while index < self._edges.length() {
            GraphEdge edge = self._edges.get(index)
            Int target = self.nodeIndex(edge.toNode)
            indegree.set(target, indegree.get(target) + 1)
            index = index + 1
        }
        List<Int> queue = []
        index = 0
        while index < self._nodes.length() {
            if indegree.get(index) == 0 { queue.push(index) }
            index = index + 1
        }
        List<String> result = []
        Int head = 0
        while head < queue.length() {
            Int current = queue.get(head)
            head = head + 1
            result.push(self._nodes.get(current))
            index = 0
            while index < self._edges.length() {
                GraphEdge edge = self._edges.get(index)
                if self.nodeIndex(edge.fromNode) == current {
                    Int target = self.nodeIndex(edge.toNode)
                    Int value = indegree.get(target) - 1
                    indegree.set(target, value)
                    if value == 0 { queue.push(target) }
                }
                index = index + 1
            }
        }
        if result.length() != self._nodes.length() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Graph.topologicalSort: cycle"))
        }
        return Ok(result)
    }
    Result<List<String>, Error> shortestPath(String source, String target) {
        if source == null || target == null { throw "Graph.shortestPath: null endpoint" }
        if !self.hasNode(source) || !self.hasNode(target) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Graph.shortestPath: unknown endpoint"))
        }
        if source == target { List<String> only = []; only.push(source); return Ok(only) }
        List<Int> queue = []
        List<Int> parent = []
        List<Bool> seen = []
        Int index = 0
        while index < self._nodes.length() { parent.push(-1); seen.push(false); index = index + 1 }
        Int sourceIndex = self.nodeIndex(source)
        seen.set(sourceIndex, true)
        queue.push(sourceIndex)
        Int head = 0
        Bool found = false
        while head < queue.length() {
            Int current = queue.get(head)
            head = head + 1
            List<String> next = self.neighbors(self._nodes.get(current))
            Int nextIndex = 0
            while nextIndex < next.length() {
                Int candidate = self.nodeIndex(next.get(nextIndex))
                if !seen.get(candidate) {
                    seen.set(candidate, true)
                    parent.set(candidate, current)
                    if self._nodes.get(candidate) == target { found = true; break }
                    queue.push(candidate)
                }
                nextIndex = nextIndex + 1
            }
            if found { break }
        }
        if !found { return Err(new BasicError(ErrorKind.NotFound, "Graph.shortestPath: no path")) }
        List<String> reversedPath = []
        Int cursor = self.nodeIndex(target)
        while cursor >= 0 { reversedPath.push(self._nodes.get(cursor)); cursor = parent.get(cursor) }
        List<String> path = []
        index = reversedPath.length() - 1
        while index >= 0 { path.push(reversedPath.get(index)); index = index - 1 }
        return Ok(path)
    }
}
