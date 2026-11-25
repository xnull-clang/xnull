package app.net
import xdk.net
import xdk.errors
import xdk.sync
import xdk.time

static Error handlerFailure() {
    return new BasicError(ErrorKind.Io, "handler failed")
}

class EchoHandler implements TcpHandler {
    TcpServer server
    EchoHandler(TcpServer owner) { self.server = owner }

    Result<Unit, Error> handle(Context context, TcpStream stream) {
        Bytes buffer = Bytes.alloc(128)
        Result<Int, Error> read = stream.read(context, buffer)
        if read.isErr() { return Err(read.error()) }
        if read.value() > 0 {
            Result<Unit, Error> written = stream.writeAll(context, buffer.slice(0, read.value()))
            if written.isErr() { return Err(written.error()) }
        }
        self.server.close()
        return Ok()
    }
}

class FailingHandler implements TcpHandler {
    Result<Unit, Error> handle(Context context, TcpStream stream) {
        return Err(handlerFailure())
    }
}

class CountingHandler implements TcpHandler {
    AtomicInt handled
    CountingHandler(AtomicInt counter) { self.handled = counter }
    Result<Unit, Error> handle(Context context, TcpStream stream) {
        self.handled.store(self.handled.load() + 1)
        return Ok()
    }
}

static Int main() {
    Result<IpAddress, Error> ipv4 = IpAddress.parse("192.0.2.1")
    Result<IpAddress, Error> ipv6 = IpAddress.parse("2001:db8::1")
    IpAddress loopback4 = IpAddress.loopback(IpFamily.V4)
    IpAddress loopback6 = IpAddress.loopback(IpFamily.V6)
    IpAddress any4 = IpAddress.any(IpFamily.V4)
    print("ip=" + ipv4.value().text() + "," + ipFamilyName(ipv4.value().family()) + "," +
        str(ipv4.value().bytes().length()) + "," + str(ipv4.value().isLoopback()) + "," +
        str(ipv4.value().isAny()))
    print("ip6=" + ipv6.value().text() + "," + ipFamilyName(ipv6.value().family()) + "," +
        str(ipv6.value().bytes().length()) + "," + loopback6.text() + "," +
        str(loopback4.text() == "127.0.0.1") + "," + str(any4.text() == "0.0.0.0"))
    print("ip-bad=" + errorKindName(IpAddress.parse("not-an-ip").error().kind()) + "," +
        errorKindName(IpAddress.parse("300.1.1.1").error().kind()))

    IpPrefix prefix = IpPrefix.parse("192.168.1.0/24").value()
    IpAddress network = prefix.network()
    IpAddress broadcast = prefix.broadcast() as IpAddress
    print("prefix=" + prefix.text() + "," + network.text() + "," + broadcast.text() + "," +
        str(prefix.contains(IpAddress.parse("192.168.1.7").value())) + "," +
        str(prefix.contains(IpAddress.parse("192.168.2.7").value())))
    IpPrefix all = IpPrefix.parse("0.0.0.0/0").value()
    IpPrefix host = IpPrefix.parse("10.1.2.3/32").value()
    IpPrefix six = IpPrefix.parse("2001:db8::/32").value()
    IpAddress hostBroadcast = host.broadcast() as IpAddress
    print("prefix-edge=" + all.text() + "," + host.network().text() + "," +
        hostBroadcast.text() + "," + six.text() + "," +
        str(six.contains(IpAddress.parse("2001:db8::1").value())) + "," +
        str(six.broadcast() == null))
    print("prefix-bad=" + errorKindName(IpPrefix.parse("10.0.0.0/33").error().kind()) + "," +
        errorKindName(IpPrefix.parse("10.0.0.0").error().kind()))

    SocketAddress v4Address = SocketAddress.parse("127.0.0.1:19011").value()
    SocketAddress v6Address = SocketAddress.parse("[::1]:19012").value()
    print("addr=" + v4Address.text() + "," + str(v4Address.port()) + "," + v6Address.text() + "," +
        errorKindName(SocketAddress.parse("bad").error().kind()) + "," +
        errorKindName(SocketAddress.parse("127.0.0.1:70000").error().kind()))

    Context context = Context.background()
    TcpListener listener = TcpListener.bind(context, v4Address).value()
    print("listen=" + str(listener.isOpen()) + "," + listener.localAddress().text())
    Context groupContext = Context.withCancel(context)
    TaskGroup group = TaskGroup.create(groupContext)
    Task<Int> echoTask = group.spawn((Context taskContext) -> {
        Result<TcpStream, Error> accepted = listener.accept(taskContext)
        if accepted.isErr() { return Ok(1) }
        TcpStream stream = accepted.value()
        Bytes buffer = Bytes.alloc(128)
        Result<Int, Error> read = stream.read(taskContext, buffer)
        if read.isErr() { return Ok(2) }
        stream.writeAll(taskContext, buffer.slice(0, read.value()))
        print("state=" + socketStateName(stream.state()) + "," +
            str(stream.localAddress().port() == 19011) + "," +
            str(stream.remoteAddress().port() > 0))
        stream.close()
        print("stream-closed=" + str(stream.isOpen()) + "," + socketStateName(stream.state()) + "," +
            errorKindName(stream.read(taskContext, buffer).error().kind()))
        return Ok(0)
    })
    TcpStream client = TcpStream.connect(context, v4Address).value()
    print("connect=" + str(client.isOpen()) + "," +
        str(client.localAddress().port() > 0) + "," +
        str(client.remoteAddress().port() == 19011))
    Bytes payload = Bytes.fromString("hello tcp")
    Result<Unit, Error> sent = client.writeAll(context, payload)
    Bytes response = Bytes.alloc(128)
    Result<Int, Error> received = client.read(context, response)
    String responseText = response.slice(0, received.value()).toString()
    print("echo=" + str(sent.isOk()) + "," + str(received.value()) + "," + responseText)
    Result<Unit, Error> readDeadline = client.setReadDeadline(nowMono() + 10)
    Result<Unit, Error> writeDeadline = client.setWriteDeadline(nowMono() + 10)
    print("deadline=" + errorKindName(readDeadline.error().kind()) + "," +
        errorKindName(writeDeadline.error().kind()))
    client.close()
    client.close()
    print("client-closed=" + str(client.isOpen()) + "," + socketStateName(client.state()) + "," +
        errorKindName(client.write(context, payload).error().kind()))
    echoTask.join()
    listener.close()
    listener.close()
    print("listener-closed=" + str(listener.isOpen()))
    group.close()

    SocketAddress serverAddress = SocketAddress.parse("127.0.0.1:19013").value()
    TcpServer server = TcpServer.bind(context, serverAddress).value()
    EchoHandler handler = new EchoHandler(server)
    TaskGroup serverGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> serveTask = serverGroup.spawn((Context taskContext) -> {
        Result<Unit, Error> served = server.serve(taskContext, handler)
        if served.isErr() { return Ok(1) }
        return Ok(0)
    })
    sleepMs(50)
    TcpClient clientRole = new TcpClient()
    TcpStream servedClient = clientRole.connect(context, serverAddress).value()
    servedClient.writeAll(context, payload)
    Bytes servedResponse = Bytes.alloc(128)
    Result<Int, Error> servedRead = servedClient.read(context, servedResponse)
    String servedText = servedResponse.slice(0, servedRead.value()).toString()
    print("server=" + str(server.isOpen()) + "," + str(servedRead.value()) + "," + servedText)
    servedClient.close()
    serveTask.join()
    print("server-done=" + str(server.isOpen()))
    serverGroup.close()

    SocketAddress failingAddress = SocketAddress.parse("127.0.0.1:19014").value()
    TcpServer failingServer = TcpServer.bind(context, failingAddress).value()
    TaskGroup failingGroup = TaskGroup.create(Context.withCancel(context))
    AtomicInt failingKind = AtomicInt(0)
    Task<Int> failingTask = failingGroup.spawn((Context taskContext) -> {
        Result<Unit, Error> served = failingServer.serve(taskContext, new FailingHandler())
        if served.isErr() {
            if served.error().kind() == ErrorKind.Io { failingKind.store(1) }
        }
        return Ok(0)
    })
    sleepMs(50)
    TcpStream failingClient = TcpStream.connect(context, failingAddress).value()
    failingClient.close()
    failingTask.join()
    print("handler-error=" + str(failingKind.load()) + "," + str(failingServer.isOpen()))
    failingGroup.close()

    SocketAddress cancelAddress = SocketAddress.parse("127.0.0.1:19015").value()
    TcpServer cancelServer = TcpServer.bind(context, cancelAddress).value()
    Context cancelled = Context.background()
    cancelled.cancel()
    Result<Unit, Error> cancelledServe = cancelServer.serve(cancelled, new CountingHandler(AtomicInt(0)))
    print("serve-cancel=" + errorKindName(cancelledServe.error().kind()))
    cancelServer.close()

    TcpListener duplicate = TcpListener.bind(context, SocketAddress.parse("127.0.0.1:19016").value()).value()
    Result<TcpListener, Error> conflict = TcpListener.bind(context, SocketAddress.parse("127.0.0.1:19016").value())
    print("conflict=" + errorKindName(conflict.error().kind()))
    duplicate.close()

    Result<TcpStream, Error> refused = TcpStream.connect(context, SocketAddress.parse("127.0.0.1:19019").value())
    print("refused=" + errorKindName(refused.error().kind()))

    TcpServerOptions serverOptions = new TcpServerOptions()
    serverOptions.backlog(64)
    serverOptions.closeOnHandlerError(false)
    TcpServerOptions copiedOptions = serverOptions.copy()
    print("options=" + str(copiedOptions.getBacklog()) + "," +
        str(copiedOptions.isCloseOnHandlerError()))

    Context cancelledConnect = Context.background()
    cancelledConnect.cancel()
    Result<TcpStream, Error> cancelledClient = TcpStream.connect(cancelledConnect, v4Address)
    Result<TcpListener, Error> cancelledBind = TcpListener.bind(cancelledConnect, v4Address)
    print("cancel=" + errorKindName(cancelledClient.error().kind()) + "," +
        errorKindName(cancelledBind.error().kind()))
    return 0
}
