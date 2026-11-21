// Tier: T0；依赖：xdk.bytes、xdk.errors；稳定性：preview。
// xdk.io —— 内存 Reader/Writer 与可组合流。
//
// 读取失败的通道固定为两种：
//   - 无 Result 的 readU8/readBytes：违反前置或 EOF 是合同错误（panic）；
//   - tryReadU8/readExact：可恢复失败返回 Result，且失败时位置不变。
// 写入器提供 flush/close；close 幂等。内存流不持有 OS 资源。
package xdk.io
import xdk.bytes
import xdk.errors

static Error ioError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

protocol Readable {
    Int remaining();
    Bool hasRemaining();
    Int readU8();
    Result<Int, Error> tryReadU8();
    Bytes readBytes(Int count);
    Result<Bytes, Error> readExact(Int count);
    Bool isClosed();
    Result<Unit, Error> close();
}

protocol Writable {
    Int length();
    Void writeU8(Int value);
    Void writeBytes(Bytes source);
    Result<Unit, Error> flush();
    Result<Unit, Error> close();
    Bool isClosed();
}

class Reader implements Readable {
    Bytes data
    Int position
    Bool _closed

    Reader(Bytes source) {
        self.data = source
        self.position = 0
        self._closed = false
    }

    Int remaining() {
        if self._closed {
            return 0
        }
        return self.data.length() - self.position
    }

    Bool hasRemaining() {
        return self.remaining() > 0
    }

    Int readU8() {
        if self._closed {
            throw "readU8: closed"
        }
        if self.position >= self.data.length() {
            throw "readU8: end of input"
        }
        Int value = self.data.get(self.position)
        self.position = self.position + 1
        return value
    }

    Result<Int, Error> tryReadU8() {
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "tryReadU8: closed"))
        }
        if self.position >= self.data.length() {
            return Err(ioError(ErrorKind.DataCorrupted, "tryReadU8: end of input"))
        }
        return Ok(self.readU8())
    }

    Bytes readBytes(Int count) {
        if count < 0 {
            throw "readBytes: negative count"
        }
        if self._closed {
            throw "readBytes: closed"
        }
        Int end = self.position + count
        if end > self.data.length() {
            end = self.data.length()
        }
        Bytes value = Bytes.fromString("")
        Int index = self.position
        while index < end {
            value.push(self.data.get(index))
            index = index + 1
        }
        self.position = end
        return value
    }

    Result<Bytes, Error> readExact(Int count) {
        if count < 0 {
            throw "readExact: negative count"
        }
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "readExact: closed"))
        }
        if self.remaining() < count {
            return Err(ioError(ErrorKind.DataCorrupted, "readExact: end of input"))
        }
        return Ok(self.readBytes(count))
    }

    Bool isClosed() {
        return self._closed
    }

    Result<Unit, Error> close() {
        self._closed = true
        return Ok()
    }
}

class Writer implements Writable {
    Bytes data
    Bool _closed

    Writer() {
        self.data = Bytes.fromString("")
        self._closed = false
    }

    Int length() {
        return self.data.length()
    }

    Bytes toBytes() {
        return copy(self.data)
    }

    Void writeU8(Int value) {
        if self._closed {
            throw "writeU8: closed"
        }
        self.data.push(value % 256)
    }

    Void writeBytes(Bytes source) {
        if self._closed {
            throw "writeBytes: closed"
        }
        Int index = 0
        while index < source.length() {
            self.data.push(source.get(index))
            index = index + 1
        }
    }

    Result<Unit, Error> flush() {
        return Ok()
    }

    Bool isClosed() {
        return self._closed
    }

    Result<Unit, Error> close() {
        self._closed = true
        return Ok()
    }
}

class BufferedReader implements Readable {
    Readable _source
    Bytes _buffer
    Int _bufferPosition
    Int _capacity
    Bool _closed

    BufferedReader(Readable source, Int capacity) {
        if capacity < 1 {
            throw "BufferedReader: capacity must be positive"
        }
        self._source = source
        self._buffer = Bytes.fromString("")
        self._bufferPosition = 0
        self._capacity = capacity
        self._closed = false
    }

    Void fill() {
        if self._closed {
            self._buffer = Bytes.fromString("")
            self._bufferPosition = 0
            return
        }
        self._buffer = self._source.readBytes(self._capacity)
        self._bufferPosition = 0
    }

    Int remaining() {
        if self._closed {
            return 0
        }
        return self._buffer.length() - self._bufferPosition + self._source.remaining()
    }

    Bool hasRemaining() {
        return self.remaining() > 0
    }

    Int readU8() {
        if self._closed {
            throw "readU8: closed"
        }
        if self._bufferPosition >= self._buffer.length() {
            self.fill()
        }
        if self._bufferPosition >= self._buffer.length() {
            throw "readU8: end of input"
        }
        Int value = self._buffer.get(self._bufferPosition)
        self._bufferPosition = self._bufferPosition + 1
        return value
    }

    Result<Int, Error> tryReadU8() {
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "tryReadU8: closed"))
        }
        if self._bufferPosition >= self._buffer.length() {
            self.fill()
        }
        if self._bufferPosition >= self._buffer.length() {
            return Err(ioError(ErrorKind.DataCorrupted, "tryReadU8: end of input"))
        }
        return Ok(self.readU8())
    }

    Bytes readBytes(Int count) {
        if count < 0 {
            throw "readBytes: negative count"
        }
        if self._closed {
            throw "readBytes: closed"
        }
        Bytes value = Bytes.fromString("")
        Int need = count
        while need > 0 {
            if self._bufferPosition >= self._buffer.length() {
                self.fill()
            }
            if self._bufferPosition >= self._buffer.length() {
                break
            }
            Int available = self._buffer.length() - self._bufferPosition
            Int take = need
            if take > available {
                take = available
            }
            Int index = 0
            while index < take {
                value.push(self._buffer.get(self._bufferPosition + index))
                index = index + 1
            }
            self._bufferPosition = self._bufferPosition + take
            need = need - take
        }
        return value
    }

    Result<Bytes, Error> readExact(Int count) {
        if count < 0 {
            throw "readExact: negative count"
        }
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "readExact: closed"))
        }
        if self.remaining() < count {
            return Err(ioError(ErrorKind.DataCorrupted, "readExact: end of input"))
        }
        return Ok(self.readBytes(count))
    }

    Bool isClosed() {
        return self._closed
    }

    Result<Unit, Error> close() {
        if self._closed {
            return Ok()
        }
        self._closed = true
        self._buffer = Bytes.fromString("")
        self._bufferPosition = 0
        return self._source.close()
    }
}

class BufferedWriter implements Writable {
    Writable _sink
    Bytes _buffer
    Int _length
    Bool _closed

    BufferedWriter(Writable sink) {
        self._sink = sink
        self._buffer = Bytes.fromString("")
        self._length = 0
        self._closed = false
    }

    Int length() {
        return self._length
    }

    Int bufferedLength() {
        return self._buffer.length()
    }

    Bytes pendingBytes() {
        return copy(self._buffer)
    }

    Void writeU8(Int value) {
        if self._closed {
            throw "writeU8: closed"
        }
        self._buffer.push(value % 256)
        self._length = self._length + 1
    }

    Void writeBytes(Bytes source) {
        if self._closed {
            throw "writeBytes: closed"
        }
        Int index = 0
        while index < source.length() {
            self._buffer.push(source.get(index))
            index = index + 1
        }
        self._length = self._length + source.length()
    }

    Result<Unit, Error> flush() {
        if self._closed {
            return Ok()
        }
        if self._sink.isClosed() {
            return Err(ioError(ErrorKind.Unavailable, "flush: sink closed"))
        }
        if self._buffer.length() == 0 {
            return Ok()
        }
        self._sink.writeBytes(self._buffer)
        self._buffer = Bytes.fromString("")
        return Ok()
    }

    Bool isClosed() {
        return self._closed
    }

    Result<Unit, Error> close() {
        if self._closed {
            return Ok()
        }
        Result<Unit, Error> flushed = self.flush()
        if flushed.isErr() {
            return Err(flushed.error())
        }
        self._closed = true
        return self._sink.close()
    }
}

class ChainReader implements Readable {
    Readable _first
    Readable _second
    Bool _closed

    ChainReader(Readable first, Readable second) {
        self._first = first
        self._second = second
        self._closed = false
    }

    Int remaining() {
        if self._closed {
            return 0
        }
        return self._first.remaining() + self._second.remaining()
    }

    Bool hasRemaining() {
        return self.remaining() > 0
    }

    Int readU8() {
        if self._closed {
            throw "readU8: closed"
        }
        if self._first.hasRemaining() {
            return self._first.readU8()
        }
        return self._second.readU8()
    }

    Result<Int, Error> tryReadU8() {
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "tryReadU8: closed"))
        }
        if self._first.hasRemaining() {
            return self._first.tryReadU8()
        }
        return self._second.tryReadU8()
    }

    Bytes readBytes(Int count) {
        if count < 0 {
            throw "readBytes: negative count"
        }
        if self._closed {
            throw "readBytes: closed"
        }
        Bytes value = Bytes.fromString("")
        Int need = count
        if need > 0 && self._first.hasRemaining() {
            Bytes head = self._first.readBytes(need)
            Int index = 0
            while index < head.length() {
                value.push(head.get(index))
                index = index + 1
            }
            need = need - head.length()
        }
        if need > 0 && self._second.hasRemaining() {
            Bytes tail = self._second.readBytes(need)
            Int index = 0
            while index < tail.length() {
                value.push(tail.get(index))
                index = index + 1
            }
        }
        return value
    }

    Result<Bytes, Error> readExact(Int count) {
        if count < 0 {
            throw "readExact: negative count"
        }
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "readExact: closed"))
        }
        if self.remaining() < count {
            return Err(ioError(ErrorKind.DataCorrupted, "readExact: end of input"))
        }
        return Ok(self.readBytes(count))
    }

    Bool isClosed() {
        return self._closed
    }

    Result<Unit, Error> close() {
        if self._closed {
            return Ok()
        }
        self._closed = true
        Result<Unit, Error> firstClosed = self._first.close()
        Result<Unit, Error> secondClosed = self._second.close()
        if firstClosed.isErr() {
            return Err(firstClosed.error())
        }
        return secondClosed
    }
}

class TeeReader implements Readable {
    Readable _source
    Writable _sink
    Bool _closed

    TeeReader(Readable source, Writable sink) {
        self._source = source
        self._sink = sink
        self._closed = false
    }

    Int remaining() {
        if self._closed {
            return 0
        }
        return self._source.remaining()
    }

    Bool hasRemaining() {
        return self.remaining() > 0
    }

    Int readU8() {
        if self._closed {
            throw "readU8: closed"
        }
        if self._sink.isClosed() {
            throw "readU8: sink closed"
        }
        Int value = self._source.readU8()
        self._sink.writeU8(value)
        return value
    }

    Result<Int, Error> tryReadU8() {
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "tryReadU8: closed"))
        }
        if self._sink.isClosed() {
            return Err(ioError(ErrorKind.Unavailable, "tryReadU8: sink closed"))
        }
        Result<Int, Error> next = self._source.tryReadU8()
        if next.isErr() {
            return Err(next.error())
        }
        self._sink.writeU8(next.value())
        return next
    }

    Bytes readBytes(Int count) {
        if count < 0 {
            throw "readBytes: negative count"
        }
        if self._closed {
            throw "readBytes: closed"
        }
        if self._sink.isClosed() {
            throw "readBytes: sink closed"
        }
        Bytes value = self._source.readBytes(count)
        if value.length() > 0 {
            self._sink.writeBytes(value)
        }
        return value
    }

    Result<Bytes, Error> readExact(Int count) {
        if count < 0 {
            throw "readExact: negative count"
        }
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "readExact: closed"))
        }
        if self._sink.isClosed() {
            return Err(ioError(ErrorKind.Unavailable, "readExact: sink closed"))
        }
        Result<Bytes, Error> next = self._source.readExact(count)
        if next.isErr() {
            return Err(next.error())
        }
        self._sink.writeBytes(next.value())
        return next
    }

    Bool isClosed() {
        return self._closed
    }

    // Tee 只关闭源；sink 由调用方持有，便于继续 flush/close。
    Result<Unit, Error> close() {
        if self._closed {
            return Ok()
        }
        self._closed = true
        return self._source.close()
    }
}

class LimitReader implements Readable {
    Readable _source
    Int _maximumBytes
    Int _consumed
    Bool _closed

    LimitReader(Readable source, Int maximumBytes) {
        if maximumBytes < 0 {
            throw "LimitReader: negative limit"
        }
        self._source = source
        self._maximumBytes = maximumBytes
        self._consumed = 0
        self._closed = false
    }

    Int remaining() {
        if self._closed {
            return 0
        }
        Int limitRemaining = self._maximumBytes - self._consumed
        Int sourceRemaining = self._source.remaining()
        if limitRemaining < sourceRemaining {
            return limitRemaining
        }
        return sourceRemaining
    }

    Bool hasRemaining() {
        return self.remaining() > 0
    }

    Int readU8() {
        if self._closed {
            throw "readU8: closed"
        }
        if self.remaining() <= 0 {
            throw "readU8: end of input"
        }
        Int value = self._source.readU8()
        self._consumed = self._consumed + 1
        return value
    }

    Result<Int, Error> tryReadU8() {
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "tryReadU8: closed"))
        }
        if self.remaining() <= 0 {
            return Err(ioError(ErrorKind.DataCorrupted, "tryReadU8: end of input"))
        }
        return Ok(self.readU8())
    }

    Bytes readBytes(Int count) {
        if count < 0 {
            throw "readBytes: negative count"
        }
        if self._closed {
            throw "readBytes: closed"
        }
        Int allowed = self.remaining()
        if count > allowed {
            count = allowed
        }
        Bytes value = self._source.readBytes(count)
        self._consumed = self._consumed + value.length()
        return value
    }

    Result<Bytes, Error> readExact(Int count) {
        if count < 0 {
            throw "readExact: negative count"
        }
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "readExact: closed"))
        }
        if self.remaining() < count {
            return Err(ioError(ErrorKind.DataCorrupted, "readExact: end of input"))
        }
        return Ok(self.readBytes(count))
    }

    Bool isClosed() {
        return self._closed
    }

    Result<Unit, Error> close() {
        if self._closed {
            return Ok()
        }
        self._closed = true
        return self._source.close()
    }
}

class LineReader {
    Readable _source
    Bool _closed

    LineReader(Readable source) {
        self._source = source
        self._closed = false
    }

    // 返回一行（不含行尾 LF；CRLF 去掉 CR）；EOF 返回 Ok(null)。
    Result<String?, Error> readLine() {
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "readLine: closed"))
        }
        Bytes line = Bytes.fromString("")
        while true {
            Result<Int, Error> next = self._source.tryReadU8()
            if next.isErr() {
                if next.error().kind() == ErrorKind.DataCorrupted {
                    if line.length() == 0 {
                        return Ok(null)
                    }
                    return Ok(line.toString())
                }
                return Err(next.error())
            }
            Int value = next.value()
            if value == 10 {
                String text = line.toString()
                if text.length() > 0 && text.substring(text.length() - 1, 1) == "\r" {
                    text = text.substring(0, text.length() - 1)
                }
                return Ok(text)
            }
            line.push(value)
        }
        return Ok(null)
    }

    Bool isClosed() {
        return self._closed
    }

    Result<Unit, Error> close() {
        if self._closed {
            return Ok()
        }
        self._closed = true
        return self._source.close()
    }
}

Result<Bytes, Error> readAll(Readable source) {
    if source.isClosed() {
        return Err(ioError(ErrorKind.Unavailable, "readAll: source closed"))
    }
    Bytes result = Bytes.fromString("")
    while source.hasRemaining() {
        Bytes chunk = source.readBytes(4096)
        if chunk.length() == 0 {
            break
        }
        Int index = 0
        while index < chunk.length() {
            result.push(chunk.get(index))
            index = index + 1
        }
    }
    return Ok(result)
}

Result<Int, Error> copyTo(Readable source, Writable sink) {
    if source.isClosed() {
        return Err(ioError(ErrorKind.Unavailable, "copyTo: source closed"))
    }
    if sink.isClosed() {
        return Err(ioError(ErrorKind.Unavailable, "copyTo: sink closed"))
    }
    Int total = 0
    while source.hasRemaining() {
        Bytes chunk = source.readBytes(4096)
        if chunk.length() == 0 {
            break
        }
        if sink.isClosed() {
            return Err(ioError(ErrorKind.Unavailable, "copyTo: sink closed"))
        }
        sink.writeBytes(chunk)
        total = total + chunk.length()
    }
    return Ok(total)
}
