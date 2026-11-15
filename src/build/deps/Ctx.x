// `tree` / `why`（输出与 Go `xnull tree|why` 对齐）。
//
// 用法（TSV 由 xnull-build.sh 用 xpd 预处理）：
//   deps tree <root.tsv> [<module.tsv> …]
//   deps why <coord> <root.tsv> [<module.tsv> …]
//
// 图模型：把「根工程的直接依赖」与「各模块自身的依赖」展平成边表，
// 从根做 BFS（最近优先、同深度先到先得，等价 Go ResolveGraph 的 nearest-wins），
// 记录版本/父节点/深度；tree 子节点与 why 路径按坐标字节序输出。
package xdk.build.deps
import xdk.sys

class Ctx {
    // 边表（from 为空表示根工程）
    List<String> froms = []
    List<String> tos = []
    List<String> vers = []
    // 根工程的 dependencyManagement（版本兜底）
    List<String> managedCoords = []
    List<String> managedVers = []
    // BFS 结果
    List<String> coords = []
    List<String> selected = []
    List<String> parents = []
    List<Int> depths = []

    Int find(String coord) {
        Int i = 0
        while i < coords.length() {
            if coords.get(i) == coord { return i }
            i = i + 1
        }
        return -1
    }

    String verFor(String coord, String ver) {
        if ver != "" { return ver }
        Int i = 0
        while i < managedCoords.length() {
            if managedCoords.get(i) == coord { return managedVers.get(i) }
            i = i + 1
        }
        return "?"
    }

    void addNode(String coord, String ver, String parent, Int depth) {
        if coord == "" { return }
        if find(coord) >= 0 { return }
        coords.push(coord)
        selected.push(ver)
        parents.push(parent)
        depths.push(depth)
    }

    void resolve() {
        // 根的直接依赖
        Int i = 0
        while i < froms.length() {
            if froms.get(i) == "" {
                addNode(tos.get(i), verFor(tos.get(i), vers.get(i)), "", 1)
            }
            i = i + 1
        }
        // BFS：按已选节点顺序展开其出边
        i = 0
        while i < coords.length() {
            String c = coords.get(i)
            Int d = depths.get(i)
            Int k = 0
            while k < froms.length() {
                if froms.get(k) == c {
                    addNode(tos.get(k), verFor(tos.get(k), vers.get(k)), c, d + 1)
                }
                k = k + 1
            }
            i = i + 1
        }
    }
}
