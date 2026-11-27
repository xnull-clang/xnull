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

    @Override
    Int remaining() {
        if self._closed {
            return 0
        }
        return self.data.length() - self.position
    }

    @Override
    Bool hasRemaining() {
        return self.remaining() > 0
    }

    @Override
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

    @Override
    Result<Int, Error> tryReadU8() {
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "tryReadU8: closed"))
        }
        if self.position >= self.data.length() {
            return Err(ioError(ErrorKind.DataCorrupted, "tryReadU8: end of input"))
        }
        return Ok(self.readU8())
    }

    @Override
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

    @Override
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

    @Override
    Bool isClosed() {
        return self._closed
    }

    @Override
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

    @Override
    Int length() {
        return self.data.length()
    }

    Bytes toBytes() {
        return copy(self.data)
    }

    @Override
    Void writeU8(Int value) {
        if self._closed {
            throw "writeU8: closed"
        }
        self.data.push(value % 256)
    }

    @Override
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

    @Override
    Result<Unit, Error> flush() {
        return Ok()
    }

    @Override
    Bool isClosed() {
        return self._closed
    }

    @Override
    Result<Unit, Error> close() {
        self._closed = true
        return Ok()
    }
}

// ---------- 进程 stdio 适配（B2） ----------
//
// 真实走 fd 0/1/2，不是内存流。Reader 在内部按需拉取，EOF 由空块表示；
// remaining() 只报告已缓冲且未消费的字节，hasRemaining() 在 EOF 前保持 true。
class StdioReader implements Readable {
    Bytes _buffer
    Int _position
    Bool _closed
    Bool _eof

    StdioReader() {
        self._buffer = Bytes.fromString("")
        self._position = 0
        self._closed = false
        self._eof = false
    }

    Void compact() {
        if self._position > 0 {
            self._buffer = slice(self._buffer, self._position, self._buffer.length())
            self._position = 0
        }
    }

    Void ensureBuffered(Int count) {
        if self._closed || count <= 0 {
            return
        }
        while !self._eof && self._buffer.length() - self._position < count {
            self.compact()
            Bytes more = fromHex(stdioReadHexRaw(count - self._buffer.length()))
            if more.length() == 0 {
                self._eof = true
                break
            }
            self._buffer = concatBytes(self._buffer, more)
        }
    }

    @Override
    Int remaining() {
        if self._closed {
            return 0
        }
        return self._buffer.length() - self._position
    }

    @Override
    Bool hasRemaining() {
        if self._closed {
            return false
        }
        return self.remaining() > 0 || !self._eof
    }

    @Override
    Int readU8() {
        if self._closed {
            throw "readU8: closed"
        }
        self.ensureBuffered(1)
        if self.remaining() <= 0 {
            throw "readU8: end of input"
        }
        Int value = self._buffer.get(self._position)
        self._position = self._position + 1
        return value
    }

    @Override
    Result<Int, Error> tryReadU8() {
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "tryReadU8: closed"))
        }
        self.ensureBuffered(1)
        if self.remaining() <= 0 {
            return Err(ioError(ErrorKind.DataCorrupted, "tryReadU8: end of input"))
        }
        return Ok(self.readU8())
    }

    @Override
    Bytes readBytes(Int count) {
        if count < 0 {
            throw "readBytes: negative count"
        }
        if self._closed {
            throw "readBytes: closed"
        }
        self.ensureBuffered(count)
        Int available = self.remaining()
        Int take = count
        if take > available {
            take = available
        }
        Bytes value = slice(self._buffer, self._position, self._position + take)
        self._position = self._position + take
        return value
    }

    @Override
    Result<Bytes, Error> readExact(Int count) {
        if count < 0 {
            throw "readExact: negative count"
        }
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "readExact: closed"))
        }
        self.ensureBuffered(count)
        if self.remaining() < count {
            return Err(ioError(ErrorKind.DataCorrupted, "readExact: end of input"))
        }
        return Ok(self.readBytes(count))
    }

    @Override
    Bool isClosed() {
        return self._closed
    }

    @Override
    Result<Unit, Error> close() {
        self._closed = true
        self._buffer = Bytes.fromString("")
        self._position = 0
        return Ok()
    }
}

class StdioWriter implements Writable {
    Int _descriptor
    Int _length
    Bool _closed

    StdioWriter(Int descriptor) {
        if descriptor != 1 && descriptor != 2 {
            throw "StdioWriter: descriptor must be 1 or 2"
        }
        self._descriptor = descriptor
        self._length = 0
        self._closed = false
    }

    Int descriptor() {
        return self._descriptor
    }

    @Override
    Int length() {
        return self._length
    }

    Void writeHex(String hex) {
        if self._closed {
            throw "writeHex: closed"
        }
        Int written = stdioWriteHexRaw(self._descriptor, hex)
        if written < 0 {
            throw "write: stdio failed"
        }
        self._length = self._length + written
    }

    @Override
    Void writeU8(Int value) {
        if self._closed {
            throw "writeU8: closed"
        }
        String digits = "0123456789abcdef"
        Int byte = value % 256
        self.writeHex(digits.substring(byte / 16, 1) + digits.substring(byte % 16, 1))
    }

    @Override
    Void writeBytes(Bytes source) {
        if self._closed {
            throw "writeBytes: closed"
        }
        if source.length() > 0 {
            self.writeHex(toHex(source))
        }
    }

    @Override
    Result<Unit, Error> flush() {
        if self._closed {
            return Ok()
        }
        if stdioFlushRaw(self._descriptor) != 0 {
            return Err(ioError(ErrorKind.Io, "flush: stdio failed"))
        }
        return Ok()
    }

    @Override
    Bool isClosed() {
        return self._closed
    }

    // 进程 stdout/stderr 由运行时持有；close 只 flush 并标记关闭，不关闭底层描述符。
    @Override
    Result<Unit, Error> close() {
        if self._closed {
            return Ok()
        }
        Result<Unit, Error> flushed = self.flush()
        if flushed.isErr() {
            return Err(flushed.error())
        }
        self._closed = true
        return Ok()
    }
}

StdioReader stdinReader() {
    return new StdioReader()
}

StdioWriter stdoutWriter() {
    return new StdioWriter(1)
}

StdioWriter stderrWriter() {
    return new StdioWriter(2)
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

    @Override
    Int remaining() {
        if self._closed {
            return 0
        }
        return self._buffer.length() - self._bufferPosition + self._source.remaining()
    }

    @Override
    Bool hasRemaining() {
        return self.remaining() > 0 || self._source.hasRemaining()
    }

    @Override
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

    @Override
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

    @Override
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

    @Override
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

    @Override
    Bool isClosed() {
        return self._closed
    }

    @Override
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

    @Override
    Int length() {
        return self._length
    }

    Int bufferedLength() {
        return self._buffer.length()
    }

    Bytes pendingBytes() {
        return copy(self._buffer)
    }

    @Override
    Void writeU8(Int value) {
        if self._closed {
            throw "writeU8: closed"
        }
        self._buffer.push(value % 256)
        self._length = self._length + 1
    }

    @Override
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

    @Override
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

    @Override
    Bool isClosed() {
        return self._closed
    }

    @Override
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

    @Override
    Int remaining() {
        if self._closed {
            return 0
        }
        return self._first.remaining() + self._second.remaining()
    }

    @Override
    Bool hasRemaining() {
        return self.remaining() > 0
    }

    @Override
    Int readU8() {
        if self._closed {
            throw "readU8: closed"
        }
        if self._first.hasRemaining() {
            return self._first.readU8()
        }
        return self._second.readU8()
    }

    @Override
    Result<Int, Error> tryReadU8() {
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "tryReadU8: closed"))
        }
        if self._first.hasRemaining() {
            return self._first.tryReadU8()
        }
        return self._second.tryReadU8()
    }

    @Override
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

    @Override
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

    @Override
    Bool isClosed() {
        return self._closed
    }

    @Override
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

    @Override
    Int remaining() {
        if self._closed {
            return 0
        }
        return self._source.remaining()
    }

    @Override
    Bool hasRemaining() {
        return self.remaining() > 0
    }

    @Override
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

    @Override
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

    @Override
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

    @Override
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

    @Override
    Bool isClosed() {
        return self._closed
    }

    // Tee 只关闭源；sink 由调用方持有，便于继续 flush/close。
    @Override
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

    @Override
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

    @Override
    Bool hasRemaining() {
        return self.remaining() > 0
    }

    @Override
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

    @Override
    Result<Int, Error> tryReadU8() {
        if self._closed {
            return Err(ioError(ErrorKind.Unavailable, "tryReadU8: closed"))
        }
        if self.remaining() <= 0 {
            return Err(ioError(ErrorKind.DataCorrupted, "tryReadU8: end of input"))
        }
        return Ok(self.readU8())
    }

    @Override
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

    @Override
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

    @Override
    Bool isClosed() {
        return self._closed
    }

    @Override
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

// ---------- 2.x protocols / SeekOrigin ----------
enum SeekOrigin {
    Unknown,
    Start,
    Current,
    End,
}

String seekOriginName(SeekOrigin origin) {
    if origin == SeekOrigin.Start { return "start" }
    if origin == SeekOrigin.Current { return "current" }
    if origin == SeekOrigin.End { return "end" }
    return "unknown"
}

protocol Closer {
    Result<Unit, Error> close();
    Bool isOpen();
}

protocol Seekable {
    Result<Long, Error> seek(Long offset, SeekOrigin origin);
    Long position();
    Result<Long, Error> size();
}

// ---------- ByteArrayReader ----------
class ByteArrayReader implements Seekable, Closer {
    final Bytes _data
    Long _position
    Bool _open

    ByteArrayReader(Bytes data) {
        if data == null { throw "ByteArrayReader: null data" }
        self._data = copy(data)
        self._position = 0 as Long
        self._open = true
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if context == null || buffer == null { throw "ByteArrayReader.read: null argument" }
        if !self._open { return Err(ioError(ErrorKind.Unavailable, "reader closed")) }
        if buffer.length() == 0 {
            return Err(ioError(ErrorKind.InvalidArgument, "reader empty buffer"))
        }
        if context.isCancelled() {
            return Err(ioError(ErrorKind.Cancelled, "reader cancelled"))
        }
        Int available = self._data.length() - (self._position as Int)
        if available <= 0 { return Ok(0) }
        Int count = buffer.length()
        if count > available { count = available }
        Int index = 0
        while index < count {
            buffer.set(index, self._data.get((self._position as Int) + index))
            index = index + 1
        }
        self._position = self._position + count as Long
        return Ok(count)
    }

    Result<Long, Error> seek(Long offset, SeekOrigin origin) {
        if !self._open { return Err(ioError(ErrorKind.Unavailable, "reader closed")) }
        Long target = offset
        if origin == SeekOrigin.Current { target = self._position + offset }
        else if origin == SeekOrigin.End { target = self._data.length() as Long + offset }
        if target < 0 as Long || target > self._data.length() as Long {
            return Err(ioError(ErrorKind.InvalidArgument, "reader seek out of range"))
        }
        self._position = target
        return Ok(target)
    }

    Long position() { return self._position }
    Result<Long, Error> size() { return Ok(self._data.length() as Long) }
    Result<Unit, Error> close() { self._open = false; return Ok() }
    Bool isOpen() { return self._open }
}

// ---------- ByteArrayWriter ----------
class ByteArrayWriter implements Closer {
    Bytes _data
    Bool _open

    ByteArrayWriter() {
        self._data = Bytes.alloc(0)
        self._open = true
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if context == null || data == null { throw "ByteArrayWriter.write: null argument" }
        if !self._open { return Err(ioError(ErrorKind.Unavailable, "writer closed")) }
        if context.isCancelled() {
            return Err(ioError(ErrorKind.Cancelled, "writer cancelled"))
        }
        Bytes next = Bytes.alloc(self._data.length() + data.length())
        Int index = 0
        while index < self._data.length() {
            next.set(index, self._data.get(index))
            index = index + 1
        }
        Int offset = self._data.length()
        index = 0
        while index < data.length() {
            next.set(offset + index, data.get(index))
            index = index + 1
        }
        self._data = next
        return Ok(data.length())
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Result<Int, Error> written = self.write(context, data)
        if written.isErr() { return Err(written.error()) }
        return Ok()
    }

    Result<Unit, Error> flush() { return Ok() }
    Bytes toBytes() { return copy(self._data) }
    Bytes takeBytes() {
        Bytes value = self._data
        self._data = Bytes.alloc(0)
        return value
    }
    Int length() { return self._data.length() }
    Void clear() { self._data = Bytes.alloc(0) }
    Result<Unit, Error> close() { self._open = false; return Ok() }
    Bool isOpen() { return self._open }
}

// ---------- StringReader ----------
class StringReader implements Seekable, Closer {
    final ByteArrayReader _reader
    StringReader(String text) {
        if text == null { throw "StringReader: null text" }
        self._reader = new ByteArrayReader(Bytes.fromString(text))
    }
    Result<Int, Error> read(Context context, Bytes buffer) { return self._reader.read(context, buffer) }
    Result<Long, Error> seek(Long offset, SeekOrigin origin) { return self._reader.seek(offset, origin) }
    Long position() { return self._reader.position() }
    Result<Long, Error> size() { return self._reader.size() }
    String readAllText() {
        Long remaining = (self._reader.size().value() - self._reader.position()) as Long
        if remaining <= 0 as Long { return "" }
        Bytes buffer = Bytes.alloc(remaining as Int)
        Result<Int, Error> read = self._reader.read(Context.background(), buffer)
        if read.isErr() { return "" }
        return buffer.slice(0, read.value()).toString()
    }
    Result<Unit, Error> close() { return self._reader.close() }
    Bool isOpen() { return self._reader.isOpen() }
}

// ---------- StringWriter ----------
class StringWriter implements Closer {
    String _text
    Bool _open
    StringWriter() { self._text = ""; self._open = true }
    Result<Int, Error> write(Context context, Bytes data) {
        if context == null || data == null { throw "StringWriter.write: null argument" }
        if !self._open { return Err(ioError(ErrorKind.Unavailable, "writer closed")) }
        if context.isCancelled() {
            return Err(ioError(ErrorKind.Cancelled, "writer cancelled"))
        }
        String current = self._text
        String dataText = data.toString()
        self._text = current + dataText
        return Ok(data.length())
    }
    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Result<Int, Error> written = self.write(context, data)
        if written.isErr() { return Err(written.error()) }
        return Ok()
    }
    Void writeText(String text) {
        if text == null { throw "StringWriter.writeText: null text" }
        String current = self._text
        self._text = current + text
    }
    Result<Unit, Error> flush() { return Ok() }
    String toString() { return self._text }
    Int length() { return self._text.length() }
    Void clear() { self._text = "" }
    Result<Unit, Error> close() { self._open = false; return Ok() }
    Bool isOpen() { return self._open }
}
