package app.websocket
import xdk.net.websocket
import xdk.net
import xdk.net.uri
import xdk.errors
import xdk.time

class EchoHandler implements WebSocketHandler {
    Result<Unit, Error> handle(Context context, WebSocket socket) {
        while socket.isOpen() {
            Result<WebSocketMessage?, Error> received = socket.receive(context)
            if received.isErr() { return Err(received.error()) }
            WebSocketMessage? maybe = received.value()
            if maybe == null { return Ok() }
            WebSocketMessage message = maybe as WebSocketMessage
            if message.isText() {
                Result<Unit, Error> sent = socket.sendText(context, message.text() as String)
                if sent.isErr() { return Err(sent.error()) }
            } else if message.isBinary() {
                Result<Unit, Error> sent = socket.sendBinary(context, message.binary() as Bytes)
                if sent.isErr() { return Err(sent.error()) }
            } else if message.isClose() {
                return Ok()
            }
        }
        return Ok()
    }
}


static Bytes readExactStream(Context context, TcpStream stream, Int count) {
    Bytes result = Bytes.alloc(count)
    Int offset = 0
    while offset < count {
        Bytes slice = result.slice(offset, count)
        Result<Int, Error> read = stream.read(context, slice)
        if read.isErr() || read.value() <= 0 { return Bytes.fromString("") }
        Int index = 0
        while index < read.value() {
            result.set(offset + index, slice.get(index))
            index = index + 1
        }
        offset = offset + read.value()
    }
    return result
}

static Bytes maskedFrame(Int opcode, Bool fin, Bytes payload) {
    Bytes frame = Bytes.fromString("")
    Int first = opcode
    if fin { first = first | 128 }
    frame.push(first)
    Int length = payload.length()
    if length < 126 {
        frame.push(128 | length)
    } else if length <= 65535 {
        frame.push(128 | 126)
        frame.push((length >> 8) & 255)
        frame.push(length & 255)
    } else {
        frame.push(128 | 127)
        Int shift = 56
        while shift >= 0 {
            frame.push((length >> shift) & 255)
            shift = shift - 8
        }
    }
    Int mask0 = 1
    Int mask1 = 2
    Int mask2 = 3
    Int mask3 = 4
    frame.push(mask0)
    frame.push(mask1)
    frame.push(mask2)
    frame.push(mask3)
    Int index = 0
    while index < payload.length() {
        Int key = mask0
        if index % 4 == 1 { key = mask1 }
        if index % 4 == 2 { key = mask2 }
        if index % 4 == 3 { key = mask3 }
        frame.push(payload.get(index) ^ key)
        index = index + 1
    }
    return frame
}

static String readServerText(Context context, TcpStream stream) {
    Bytes head = readExactStream(context, stream, 2)
    if head.length() != 2 { return "" }
    Int second = head.get(1)
    Int length = second & 127
    if length == 126 {
        Bytes ext = readExactStream(context, stream, 2)
        length = ext.get(0) * 256 + ext.get(1)
    } else if length == 127 {
        Bytes ext = readExactStream(context, stream, 8)
        length = 0
        Int index = 0
        while index < 8 { length = length * 256 + ext.get(index); index = index + 1 }
    }
    Bytes payload = readExactStream(context, stream, length)
    return payload.toString()
}

static Bool fragmentation(Context context, SocketAddress address) {
    Result<TcpStream, Error> connected = TcpStream.connect(context, address)
    if connected.isErr() { return false }
    TcpStream stream = connected.value()
    String request = "GET /frag HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n" +
        "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" +
        "Sec-WebSocket-Version: 13\r\n\r\n"
    stream.writeAll(context, Bytes.fromString(request))
    Bytes buffer = Bytes.alloc(2048)
    Result<Int, Error> headRead = stream.read(context, buffer)
    if headRead.isErr() || headRead.value() <= 0 { return false }
    Bytes first = maskedFrame(1, false, Bytes.fromString("hel"))
    Bytes second = maskedFrame(0, true, Bytes.fromString("lo"))
    stream.writeAll(context, first)
    stream.writeAll(context, second)
    String reply = readServerText(context, stream)
    stream.close()
    return reply == "hello"
}

static Int main() {
    WebSocketOptions options = new WebSocketOptions()
    options.maxMessageBytes(1048576)
    SocketAddress address = SocketAddress.parse("127.0.0.1:19201").value()
    Context context = Context.background()
    WebSocketServer server = WebSocketServer.bind(context, address, options).value()
    TaskGroup group = TaskGroup.create(Context.withCancel(context))
    Task<Int> serveTask = group.spawn((Context taskContext) -> {
        Result<Unit, Error> served = server.serve(taskContext, new EchoHandler())
        if served.isErr() { return Ok(1) }
        return Ok(0)
    })
    sleepMs(50)
    Uri uri = Uri.parse("ws://127.0.0.1:19201/echo").value()
    WebSocket socket = WebSocket.connect(context, uri, new WebSocketOptions()).value()
    print("handshake=" + webSocketStateName(socket.state()) + "," + str(socket.isOpen()) + "," +
        str(socket.options().getMaxMessageBytes()))

    Result<Unit, Error> sent = socket.sendText(context, "hello websocket")
    Result<WebSocketMessage?, Error> reply = socket.receive(context)
    WebSocketMessage textMessage = reply.value() as WebSocketMessage
    print("text=" + str(sent.isOk()) + "," + str(textMessage.isText()) + "," +
        (textMessage.text() as String))

    socket.sendBinary(context, fromHex("000102ff"))
    Result<WebSocketMessage?, Error> binaryReply = socket.receive(context)
    WebSocketMessage binaryMessage = binaryReply.value() as WebSocketMessage
    print("binary=" + str(binaryMessage.isBinary()) + "," + toHex(binaryMessage.binary() as Bytes))

    socket.sendPing(context, Bytes.fromString("p"))
    Result<WebSocketMessage?, Error> pongReply = socket.receive(context)
    WebSocketMessage pongMessage = pongReply.value() as WebSocketMessage
    print("ping=" + str(pongMessage.isPong()) + "," + str(socket.stats().pongsReceived()))

    String longText = ""
    Int index = 0
    while index < 130 {
        longText = longText + "a"
        index = index + 1
    }
    socket.sendText(context, longText)
    Result<WebSocketMessage?, Error> longReplyResult = socket.receive(context)
    WebSocketMessage longReply = longReplyResult.value() as WebSocketMessage
    String longReplyText = longReply.text() as String
    print("len126=" + str(longReplyText.length()))

    Bytes large = Bytes.alloc(70000)
    index = 0
    while index < large.length() {
        large.set(index, index % 251)
        index = index + 1
    }
    socket.sendBinary(context, large)
    Result<WebSocketMessage?, Error> largeReplyResult = socket.receive(context)
    WebSocketMessage largeReply = largeReplyResult.value() as WebSocketMessage
    Bytes largeContent = largeReply.binary() as Bytes
    print("len127=" + str(largeContent.length()) + "," + str(largeContent.get(1)))

    Result<Unit, Error> readDeadline = socket.setReadDeadline(nowMono() + 10)
    print("deadline=" + errorKindName(readDeadline.error().kind()))
    print("stats=" + str(socket.stats().messagesSent() > 0) + "," +
        str(socket.stats().messagesReceived() > 0) + "," +
        str(socket.stats().bytesSent() > 0) + "," + str(socket.stats().bytesReceived() > 0))

    socket.close(context, WebSocketCloseCode.Normal, "done")
    socket.close(context, WebSocketCloseCode.Normal, "again")
    print("closed=" + webSocketStateName(socket.state()) + "," + str(socket.isOpen()) + "," +
        errorKindName(socket.sendText(context, "late").error().kind()) + "," +
        errorKindName(socket.receive(context).error().kind()))
    server.close()
    serveTask.join()
    group.close()

    WebSocketOptions smallOptions = new WebSocketOptions()
    smallOptions.maxMessageBytes(8)
    SocketAddress smallAddress = SocketAddress.parse("127.0.0.1:19202").value()
    WebSocketServer smallServer = WebSocketServer.bind(context, smallAddress, smallOptions).value()
    TaskGroup smallGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> smallServe = smallGroup.spawn((Context taskContext) -> {
        smallServer.serve(taskContext, new EchoHandler())
        return Ok(0)
    })
    sleepMs(50)
    WebSocket smallSocket = WebSocket.connect(context,
        Uri.parse("ws://127.0.0.1:19202/").value(), new WebSocketOptions()).value()
    smallSocket.sendText(context, "this message is too large")
    Result<WebSocketMessage?, Error> closeReply = smallSocket.receive(context)
    WebSocketMessage closeMessage = closeReply.value() as WebSocketMessage
    print("too-big=" + str(closeMessage.isClose()) + "," +
        str(closeMessage.closeCode() == WebSocketCloseCode.MessageTooBig) + "," +
        str(webSocketCloseCodeValue(closeMessage.closeCode())) + "," +
        webSocketMessageKindName(closeMessage.kind()))
    smallServer.close()
    smallServe.join()
    smallGroup.close()

    SocketAddress fakeAddress = SocketAddress.parse("127.0.0.1:19203").value()
    TcpListener fakeListener = TcpListener.bind(context, fakeAddress).value()
    TaskGroup fakeGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> fakeTask = fakeGroup.spawn((Context taskContext) -> {
        TcpStream stream = fakeListener.accept(taskContext).value()
        Bytes buffer = Bytes.alloc(2048)
        stream.read(taskContext, buffer)
        stream.writeAll(taskContext, Bytes.fromString(
            "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: wrong\r\n\r\n"))
        stream.close()
        return Ok(0)
    })
    sleepMs(50)
    Result<WebSocket, Error> badHandshake = WebSocket.connect(context,
        Uri.parse("ws://127.0.0.1:19203/").value(), new WebSocketOptions())
    print("bad-handshake=" + errorKindName(badHandshake.error().kind()))
    fakeTask.join()
    fakeListener.close()
    fakeGroup.close()

    Result<WebSocket, Error> secure = WebSocket.connect(context,
        Uri.parse("wss://127.0.0.1:19204/").value(), new WebSocketOptions())
    print("wss=" + errorKindName(secure.error().kind()))

    WebSocketOptions chain = new WebSocketOptions()
    chain.maxFrameBytes(2048)
    chain.maxSendQueueBytes(4096)
    chain.pingIntervalMillis(100 as Long)
    chain.pongTimeoutMillis(50 as Long)
    chain.origin("http://example.test")
    List<String> protocols = ["chat"]
    chain.subprotocols(protocols)
    WebSocketOptions copy = chain.copy()
    print("options=" + str(copy.getMaxFrameBytes()) + "," + str(copy.getMaxSendQueueBytes()) + "," +
        str(copy.getPingIntervalMillis()) + "," + str(copy.getPongTimeoutMillis()) + "," +
        (copy.getOrigin() as String) + "," + copy.getSubprotocols().get(0))
    print("close-code=" + str(webSocketCloseCodeValue(WebSocketCloseCode.MessageTooBig)) + "," +
        str(parseWebSocketCloseCode(1009).isOk()) + "," +
        errorKindName(parseWebSocketCloseCode(9999).error().kind()))

    ReconnectPolicy policy = new ReconnectPolicy()
    print("policy=" + str(policy.delayMillis(0)) + "," + str(policy.delayMillis(1)) + "," +
        str(policy.delayMillis(2)) + "," + str(policy.delayMillis(5)) + "," +
        str(policy.delayMillis(10)) + "," + str(policy.shouldRetry(0)) + "," +
        str(policy.shouldRetry(4)) + "," + str(policy.shouldRetry(5)))
    ReconnectPolicy noRetry = new ReconnectPolicy()
    noRetry.maxAttempts(0)
    ReconnectPolicy jitterPolicy = new ReconnectPolicy()
    jitterPolicy.initialDelayMillis(100 as Long)
    jitterPolicy.maxDelayMillis(1000 as Long)
    jitterPolicy.jitter(true)
    Long jitterOne = jitterPolicy.delayMillis(0)
    Long jitterTwo = jitterPolicy.delayMillis(0)
    print("policy-jitter=" + str(jitterOne >= 80 as Long && jitterOne <= 120 as Long) + "," +
        str(jitterOne == jitterTwo) + "," + str(noRetry.shouldRetry(0)))
    ReconnectPolicy copiedPolicy = policy.copy()
    print("policy-copy=" + str(copiedPolicy.getInitialDelayMillis()) + "," +
        str(copiedPolicy.getMaxAttempts()) + "," + str(copiedPolicy.getMultiplier()))

    SocketAddress clientAddress = SocketAddress.parse("127.0.0.1:19301").value()
    WebSocketServer clientServer = WebSocketServer.bind(context, clientAddress, new WebSocketOptions()).value()
    TaskGroup clientGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> clientServe = clientGroup.spawn((Context taskContext) -> {
        clientServer.serve(taskContext, new EchoHandler())
        return Ok(0)
    })
    sleepMs(50)
    WebSocketClient client = new WebSocketClient(new WebSocketOptions(), policy)
    Result<WebSocket, Error> clientConnected = client.connect(context,
        Uri.parse("ws://127.0.0.1:19301/client").value())
    print("client-connect=" + str(clientConnected.isOk()) + "," +
        webSocketClientStateName(client.state()) + "," + str(client.socket() != null))
    WebSocket clientSocket = client.socket() as WebSocket
    clientSocket.sendText(context, "client msg")
    WebSocketMessage clientReply = clientSocket.receive(context).value() as WebSocketMessage
    print("client-echo=" + (clientReply.text() as String) + "," +
        str(client.stats().messagesSent() > 0) + "," + str(client.stats().messagesReceived() > 0))
    Result<Unit, Error> clientClose = client.close()
    print("client-close=" + str(clientClose.isOk()) + "," +
        webSocketClientStateName(client.state()) + "," + str(client.stats().messagesSent()))
    Result<WebSocket, Error> connectClosed = client.connect(context,
        Uri.parse("ws://127.0.0.1:19301/").value())
    Result<WebSocket, Error> reconnectClosed = client.reconnect(context)
    print("client-closed=" + errorKindName(connectClosed.error().kind()) + "," +
        errorKindName(reconnectClosed.error().kind()))
    clientServer.close()
    clientServe.join()
    clientGroup.close()

    SocketAddress lateAddress = SocketAddress.parse("127.0.0.1:19302").value()
    ReconnectPolicy shortPolicy = new ReconnectPolicy()
    shortPolicy.initialDelayMillis(10 as Long)
    shortPolicy.maxDelayMillis(40 as Long)
    shortPolicy.maxAttempts(3)
    WebSocketClient lateClient = new WebSocketClient(new WebSocketOptions(), shortPolicy)
    Result<WebSocket, Error> lateFirst = lateClient.connect(context,
        Uri.parse("ws://127.0.0.1:19302/late").value())
    print("client-fail=" + errorKindName(lateFirst.error().kind()) + "," +
        webSocketClientStateName(lateClient.state()))
    WebSocketServer lateServer = WebSocketServer.bind(context, lateAddress, new WebSocketOptions()).value()
    TaskGroup lateGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> lateServe = lateGroup.spawn((Context taskContext) -> {
        lateServer.serve(taskContext, new EchoHandler())
        return Ok(0)
    })
    sleepMs(50)
    Result<WebSocket, Error> lateReconnect = lateClient.reconnect(context)
    print("client-reconnect=" + str(lateReconnect.isOk()) + "," +
        webSocketClientStateName(lateClient.state()))
    lateClient.close()
    lateServer.close()
    lateServe.join()
    lateGroup.close()

    ReconnectPolicy exhaustedPolicy = new ReconnectPolicy()
    exhaustedPolicy.initialDelayMillis(5 as Long)
    exhaustedPolicy.maxDelayMillis(10 as Long)
    exhaustedPolicy.maxAttempts(2)
    WebSocketClient exhausted = new WebSocketClient(new WebSocketOptions(), exhaustedPolicy)
    Result<WebSocket, Error> exhaustedFirst = exhausted.connect(context,
        Uri.parse("ws://127.0.0.1:19303/none").value())
    Result<WebSocket, Error> exhaustedReconnect = exhausted.reconnect(context)
    print("client-exhausted=" + errorKindName(exhaustedFirst.error().kind()) + "," +
        errorKindName(exhaustedReconnect.error().kind()) + "," +
        webSocketClientStateName(exhausted.state()))

    SocketAddress fragmentAddress = SocketAddress.parse("127.0.0.1:19205").value()
    WebSocketServer fragmentServer = WebSocketServer.bind(context, fragmentAddress, new WebSocketOptions()).value()
    TaskGroup fragmentGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> fragmentServe = fragmentGroup.spawn((Context taskContext) -> {
        fragmentServer.serve(taskContext, new EchoHandler())
        return Ok(0)
    })
    sleepMs(50)
    print("fragment=" + str(fragmentation(context, fragmentAddress)))
    fragmentServer.close()
    fragmentServe.join()
    fragmentGroup.close()
    return 0
}
