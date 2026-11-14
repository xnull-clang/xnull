// XDK 源码层：net HTTP（本地 http.server）
import xdk.net

static Int main(String[] args) {
    if args.length() != 1 { return 2 }
    Result<Response, Error> r = httpGet("http://127.0.0.1:" + args.get(0) + "/")
    if r.isErr() {
        return 2
    }
    print(r.value().status())
    print(r.value().body().length() > 0)
    Result<Response, Error> bad = httpGet("ftp://x")
    print(bad.isErr())
    return 0
}
