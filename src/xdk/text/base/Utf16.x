// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// Utf16：UTF-16 码元序列包装（避开产品编译器 Result<List<...>> 类型名折叠）。
package xdk.text
import xdk.errors

class Utf16 {
    List<UInt16> units

    Utf16(List<UInt16> units) {
        self.units = units
    }

    Int length() {
        return self.units.length()
    }

    UInt16 get(Int index) {
        return self.units.get(index)
    }

    Bool isEmpty() {
        return self.units.length() == 0
    }

    List<UInt16> toList() {
        return self.units
    }
}
