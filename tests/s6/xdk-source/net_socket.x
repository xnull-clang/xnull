// XDK 源码层：net Socket 二进制收发（本地 echo 服务）
import xdk.net

static Int main() {
    Result<Socket, Error> c = connectSocket("127.0.0.1", 18082)
    if c.isErr() {
        return 2
    }
    Socket s = c.value()
    Bytes b = Bytes.fromString("")
    b.push(65)
    b.push(0)
    b.push(255)
    print(s.sendBytes(b).value())
    Result<Bytes, Error> r = s.recvBytes(3)
    print(r.value().length())
    print(r.value().get(0))
    print(r.value().get(1))
    print(r.value().get(2))
    s.close()
    print(s.isOpen())
    return 0
}
