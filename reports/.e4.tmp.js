   {t:"xdk.util（常用工具 · 对标 Python uuid/hashlib/argparse/logging + Go log）",s:"todo",c:[
     {t:"UUID",s:"todo",c:[
       {t:"uuid4()→String/uuid7()/uuidParse(s)→Result<UUID,Error>",s:"todo"},
       {t:"UUID.str()/UUID.bytes()/isNil()",s:"todo"}
     ]},
     {t:"哈希与校验",s:"todo",c:[
       {t:"md5(b)/sha1(b)/sha256(b)/sha512(b)→Bytes",s:"todo"},
       {t:"crc32(b)/hmacSha256(key,b)/constantTimeEquals(a,b)",s:"todo"}
     ]},
     {t:"压缩",s:"todo",c:[
       {t:"gzipCompress(b)/gzipDecompress(b)",s:"todo"},
       {t:"zipCreate(entries)/zipExtract(b,dir)",s:"todo"}
     ]},
     {t:"日志 Logger",s:"todo",c:[
       {t:"log.debug/info/warn/error(msg)",s:"todo"},
       {t:"Logger.withField(k,v)/setLevel(level)/setOutput(w)",s:"todo"}
     ]},
     {t:"断言与测试",s:"todo",c:[
       {t:"assertTrue(cond,msg)/assertEq(a,b)/assertNotNull(v)",s:"todo"},
       {t:"fail(msg)/assertThrows(f)/approxEq(a,b,eps)",s:"todo"}
     ]},
     {t:"命令行参数解析 ArgsParser",s:"todo",c:[
       {t:"flag(name,default)/option(name,default)/positional(name)",s:"todo"},
       {t:"parse(args)→Result<Args,Error>/help()→String",s:"todo"}
     ]}
   ]},
   {t:"xdk.net 扩展（对标 Go net/http + Python requests/socket）",s:"todo",c:[
     {t:"HTTP 完整面",s:"todo",c:[
       {t:"get/post/put/delete/head/patch(url,…)→Result<Response,Error>",s:"todo"},
       {t:"Request.withHeader/withTimeout/withBody/withQuery",s:"todo"},
       {t:"Response.text()/json()/bytes()/status()/header(name)",s:"todo"},
       {t:"重定向策略/cookie jar/连接池",s:"todo"}
     ]},
     {t:"HTTP 服务端",s:"todo",c:[
       {t:"listenAndServe(addr,router)/Router.get/post(path,handler)",s:"todo"},
       {t:"Request.param/query/formValue/Context 取消传播",s:"todo"}
     ]},
     {t:"UDP / DNS / URL",s:"todo",c:[
       {t:"UdpSocket.bind/sendTo/recvFrom",s:"todo"},
       {t:"resolve(host)→Result<List<IpAddr>,Error>/lookupIP",s:"todo"},
       {t:"URL.parse(url)→URL/host/path/query/fragment",s:"todo"}
     ]},
     {t:"WebSocket / TLS",s:"todo",c:[
       {t:"wsConnect(url)/send/recv/close",s:"todo"},
       {t:"tlsConfig(cert,key)/httpsServer/tlsDial",s:"todo"}
     ]}
   ]},
