// Tier: T0；依赖：xdk.bytes、xdk.errors；稳定性：preview。
// xdk.io —— 最小内存 Reader/Writer 面。
//
// 当前先提供可运行的字节流读写；文件/网络/终端流按后续 XDK 场景接入。
package xdk.io
import xdk.bytes

class Reader {
    Bytes data
    Int position

    Reader(Bytes source) {
        self.data = source
        self.position = 0
    }

    Int remaining() {
        return self.data.length() - self.position
    }

    Bool hasRemaining() {
        return self.position < self.data.length()
    }

    Int readU8() {
        if self.position >= self.data.length() {
            return 0
        }
        Int value = self.data.get(self.position)
        self.position = self.position + 1
        return value
    }

    Bytes readBytes(Int count) {
        Int end = self.position + count
        if end > self.data.length() {
            end = self.data.length()
        }
        Bytes value = Bytes.fromString("")
        Int i = self.position
        while i < end {
            value.push(self.data.get(i))
            i = i + 1
        }
        self.position = end
        return value
    }
}

class Writer {
    Bytes data

    Writer() {
        self.data = Bytes.fromString("")
    }

    Int length() {
        return self.data.length()
    }

    Bytes toBytes() {
        return self.data
    }

    Void writeU8(Int value) {
        self.data.push(value % 256)
    }

    Void writeBytes(Bytes value) {
        Int i = 0
        while i < value.length() {
            self.data.push(value.get(i))
            i = i + 1
        }
    }
}
