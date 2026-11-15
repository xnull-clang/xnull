// XPD 清单解析（project 子集）→ 规范化 TSV。
//
// 用法：
//   xpd <path/to/xnull.project>      按文件读入
//   xpd --text <源码字符串>           直接传源码（调试/测试用）
//
// 输出（制表符分隔，条目按字节序排序）：
//   # xpd tsv v1
//   field    groupId|artifactId|version|packaging   <值>
//   module   <相对目录>
//   managed  <group:artifact>   <版本>
//   dep      <group:artifact>   <版本，可空>
//
// 支持子集：project 顶层四字段、modules{module …}、dependencies{dependency c { version = v }}、
// dependencyManagement{dependencies{…}}。其余块跳过（不报错）。
package xdk.build.project
import xdk.sys






class Frame {
    String name = ""
    String arg = ""
    String kind = ""
    Bool hasVer = false
}
