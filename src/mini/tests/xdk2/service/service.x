package xdk2.service
import xdk.net.service
import xdk.net
import xdk.errors
import xdk.bytes
import xdk.tasks
import xdk.time

static Error serviceUnavailable(String message) {
    return new BasicError(ErrorKind.Unavailable, message)
}

static Error serviceIo(String message) {
    return new BasicError(ErrorKind.Io, message)
}

static Error serviceDataCorrupted(String message) {
    return new BasicError(ErrorKind.DataCorrupted, message)
}

static Error serviceNetwork(String message) {
    return new BasicError(ErrorKind.Network, message)
}

static Error serviceCancelled(String message) {
    return new BasicError(ErrorKind.Cancelled, message)
}

class MemoryStream implements ByteStream {
    Bytes input
    Int readOffset
    Bytes output
    Bool open
    Int maxWriteChunk
    Int readDeadlineCalls
    Int writeDeadlineCalls

    MemoryStream(Bytes input) {
        self.input = input
        self.readOffset = 0
        self.output = Bytes.fromString("")
        self.open = true
        self.maxWriteChunk = 1024
        self.readDeadlineCalls = 0
        self.writeDeadlineCalls = 0
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if !self.open {
            return Err(serviceUnavailable("stream closed"))
        }
        if self.readOffset >= self.input.length() { return Ok(0) }
        Int remaining = self.input.length() - self.readOffset
        Int count = buffer.length()
        if remaining < count { count = remaining }
        Int index = 0
        while index < count {
            buffer.set(index, self.input.get(self.readOffset + index))
            index = index + 1
        }
        self.readOffset = self.readOffset + count
        return Ok(count)
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if !self.open {
            return Err(serviceUnavailable("stream closed"))
        }
        Int count = data.length()
        if count > self.maxWriteChunk { count = self.maxWriteChunk }
        Int index = 0
        while index < count {
            self.output.push(data.get(index))
            index = index + 1
        }
        return Ok(count)
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Int offset = 0
        while offset < data.length() {
            Bytes part = data.slice(offset, data.length())
            Result<Int, Error> written = self.write(context, part)
            if written.isErr() { return Err(written.error()) }
            if written.value() < 1 {
                return Err(serviceIo("stream no progress"))
            }
            offset = offset + written.value()
        }
        return Ok()
    }

    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis) {
        self.readDeadlineCalls = self.readDeadlineCalls + 1
        return Ok()
    }

    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis) {
        self.writeDeadlineCalls = self.writeDeadlineCalls + 1
        return Ok()
    }

    Bool isOpen() { return self.open }

    Void close() { self.open = false }
}

class RecordingConnectionHandler implements ConnectionHandler {
    List<String> events
    Bool failOpen
    Bool failMessage

    RecordingConnectionHandler() {
        self.events = []
        self.failOpen = false
        self.failMessage = false
    }

    Result<Unit, Error> onOpen(Context context, Connection connection) {
        self.events.push("open")
        if self.failOpen {
            return Err(serviceIo("open fail"))
        }
        return Ok()
    }

    Result<Unit, Error> onMessage(Context context, Connection connection, Bytes message) {
        String text = message.toString()
        self.events.push("msg:" + text)
        if self.failMessage {
            return Err(serviceDataCorrupted("msg fail"))
        }
        return Ok()
    }

    Result<Unit, Error> onClose(Context context, Connection connection, Error? cause) {
        if cause == null {
            self.events.push("close:none")
        } else {
            self.events.push("close:error")
        }
        return Ok()
    }

    Result<Unit, Error> onError(Context context, Connection connection, Error error) {
        self.events.push("error:" + error.describe())
        return Ok()
    }
}

class RecordingSessionHandler implements SessionHandler {
    List<String> events
    Bool failOpen

    RecordingSessionHandler() {
        self.events = []
        self.failOpen = false
    }

    Result<Unit, Error> onOpen(Context context, Session session) {
        self.events.push("open")
        if self.failOpen {
            return Err(serviceIo("open fail"))
        }
        return Ok()
    }

    Result<Unit, Error> onMessage(Context context, Session session, Bytes message) {
        String text = message.toString()
        self.events.push("msg:" + text)
        return Ok()
    }

    Result<Unit, Error> onClose(Context context, Session session, Error? cause) {
        if cause == null {
            self.events.push("close:none")
        } else {
            self.events.push("close:error")
        }
        return Ok()
    }

    Result<Unit, Error> onError(Context context, Session session, Error error) {
        self.events.push("error:" + error.describe())
        return Ok()
    }
}

static String eventsText(List<String> events) {
    String text = ""
    Int index = 0
    while index < events.length() {
        if index > 0 { text = text + "," }
        text = text + events.get(index)
        index = index + 1
    }
    return text
}

static MemoryStream streamFrom(String text) {
    return new MemoryStream(Bytes.fromString(text))
}

static SocketAddress localAddress() {
    return SocketAddress.parse("127.0.0.1:1").value()
}

static Connection connectionFor(MemoryStream stream) {
    return new Connection(1 as Long, stream, localAddress(), localAddress(), 1024)
}


class EchoServiceHandler implements SessionHandler {
    List<String> messages
    Bool opened
    Bool closed

    EchoServiceHandler() {
        self.messages = []
        self.opened = false
        self.closed = false
    }

    Result<Unit, Error> onOpen(Context context, Session session) {
        self.opened = true
        return Ok()
    }

    Result<Unit, Error> onMessage(Context context, Session session, Bytes message) {
        String text = message.toString()
        self.messages.push(text)
        return session.send(context, message)
    }

    Result<Unit, Error> onClose(Context context, Session session, Error? cause) {
        self.closed = true
        return Ok()
    }

    Result<Unit, Error> onError(Context context, Session session, Error error) {
        return Ok()
    }
}

class OneShotClientHandler implements SessionHandler {
    String received
    Bool opened
    Bool closed

    OneShotClientHandler() {
        self.received = ""
        self.opened = false
        self.closed = false
    }

    Result<Unit, Error> onOpen(Context context, Session session) {
        self.opened = true
        return session.send(context, Bytes.fromString("hello"))
    }

    Result<Unit, Error> onMessage(Context context, Session session, Bytes message) {
        self.received = message.toString()
        return session.close()
    }

    Result<Unit, Error> onClose(Context context, Session session, Error? cause) {
        self.closed = true
        return Ok()
    }

    Result<Unit, Error> onError(Context context, Session session, Error error) {
        return Ok()
    }
}

class HoldClientHandler implements SessionHandler {
    Bool opened
    Bool received
    Bool closed
    String receivedText

    HoldClientHandler() {
        self.opened = false
        self.received = false
        self.closed = false
        self.receivedText = ""
    }

    Result<Unit, Error> onOpen(Context context, Session session) {
        self.opened = true
        return session.send(context, Bytes.fromString("network"))
    }

    Result<Unit, Error> onMessage(Context context, Session session, Bytes message) {
        self.receivedText = message.toString()
        self.received = true
        return Ok()
    }

    Result<Unit, Error> onClose(Context context, Session session, Error? cause) {
        self.closed = true
        return Ok()
    }

    Result<Unit, Error> onError(Context context, Session session, Error error) {
        return Ok()
    }
}

static Bool waitClientReady(Client client) {
    Int index = 0
    while index < 300 {
        if client.state() == NetServiceState.Running {
            Connection? maybe = client.connection()
            if maybe != null {
                Connection connection = maybe as Connection
                if connection.isOpen() { return true }
            }
        }
        sleepMs(5 as Long)
        index = index + 1
    }
    return false
}

static Bool waitHoldReceived(HoldClientHandler handler) {
    Int index = 0
    while index < 300 {
        if handler.received { return true }
        sleepMs(5 as Long)
        index = index + 1
    }
    return false
}

static Bool waitNetworkClientReady(NetworkService service) {
    Int index = 0
    while index < 300 {
        if service.state() == NetServiceState.Running {
            Client? maybe = service.client()
            if maybe != null {
                Client client = maybe as Client
                Connection? connection = client.connection()
                if connection != null {
                    Connection actual = connection as Connection
                    if actual.isOpen() { return true }
                }
            }
        }
        sleepMs(5 as Long)
        index = index + 1
    }
    return false
}

static Bool waitServiceRunning(NetworkService service) {
    Int index = 0
    while index < 300 {
        if service.state() == NetServiceState.Running {
            Server? maybe = service.server()
            if maybe != null {
                Server server = maybe as Server
                if server.isOpen() { return true }
            }
        }
        sleepMs(5 as Long)
        index = index + 1
    }
    return false
}

static Int main() {
    Context context = Context.background()

    NetServiceState created = NetServiceState.Created
    NetServiceState running = NetServiceState.Running
    NetServiceState draining = NetServiceState.Draining
    NetServiceState closed = NetServiceState.Closed
    print("state=" + netServiceStateName(created) + "," + netServiceStateName(running) + "," +
        netServiceStateName(draining) + "," + netServiceStateName(closed) + "," +
        str(netServiceStateCanServe(created)) + "," + str(netServiceStateCanServe(running)) + "," +
        str(netServiceStateIsActive(draining)) + "," + str(netServiceStateIsTerminal(closed)) + "," +
        str(netServiceStateIsTerminal(NetServiceState.Stopped)))

    ServiceOptions options = new ServiceOptions()
    print("options=" + str(options.getMaxConnections()) + "," +
        str(options.getAcceptQueueCapacity()) + "," + str(options.getAcceptBackoffMillis()) + "," +
        str(options.getReadBufferBytes()) + "," + str(options.getIdleTimeoutMillis()) + "," +
        str(options.getReadTimeoutMillis()) + "," + str(options.getWriteTimeoutMillis()) + "," +
        str(options.getGracefulShutdownTimeoutMillis()))

    BackpressurePolicy bp = new BackpressurePolicy()
    bp.acceptHighWaterConnections(10)
    bp.acceptLowWaterConnections(4)
    HeartbeatPolicy heartbeat = new HeartbeatPolicy()
    heartbeat.intervalMillis(100 as Long)
    heartbeat.timeoutMillis(300 as Long)
    ServiceReconnectPolicy reconnect = new ServiceReconnectPolicy()
    reconnect.maxAttempts(2)
    options.maxConnections(512)
    options.acceptQueueCapacity(64)
    options.acceptBackoffMillis(5 as Long)
    options.readBufferBytes(4096)
    options.idleTimeoutMillis(60000 as Long)
    options.readTimeoutMillis(30000 as Long)
    options.writeTimeoutMillis(20000 as Long)
    options.gracefulShutdownTimeoutMillis(0 as Long)
    options.backpressurePolicy(bp)
    options.heartbeatPolicy(heartbeat)
    options.reconnectPolicy(reconnect)
    bp.acceptHighWaterConnections(20)
    heartbeat.timeoutMillis(900 as Long)
    reconnect.maxAttempts(9)
    print("options-set=" + str(options.getMaxConnections()) + "," +
        str(options.getAcceptQueueCapacity()) + "," + str(options.getAcceptBackoffMillis()) + "," +
        str(options.getReadBufferBytes()) + "," + str(options.getIdleTimeoutMillis()) + "," +
        str(options.getReadTimeoutMillis()) + "," + str(options.getWriteTimeoutMillis()) + "," +
        str(options.getGracefulShutdownTimeoutMillis()))
    print("options-policy=" + str(options.getBackpressurePolicy().getAcceptHighWaterConnections()) +
        "," + str(options.getHeartbeatPolicy().getTimeoutMillis()) + "," +
        str(options.getReconnectPolicy().getMaxAttempts()))
    BackpressurePolicy fetched = options.getBackpressurePolicy()
    fetched.acceptHighWaterConnections(30)
    ServiceOptions copy = options.copy()
    copy.maxConnections(999)
    print("options-copy=" + str(options.getMaxConnections()) + "," +
        str(copy.getMaxConnections()) + "," +
        str(options.getBackpressurePolicy().getAcceptHighWaterConnections()))

    HeartbeatPolicy defaultHeartbeat = new HeartbeatPolicy()
    print("heartbeat-default=" + str(defaultHeartbeat.getIntervalMillis()) + "," +
        str(defaultHeartbeat.getTimeoutMillis()) + "," + str(defaultHeartbeat.isEnabled()))
    print("heartbeat-deadline=" + str(heartbeat.deadlineFrom(1000 as Long)) + "," +
        str(heartbeat.isExpired(1299 as Long, 1000 as Long)) + "," +
        str(heartbeat.isExpired(1300 as Long, 1000 as Long)) + "," +
        str(defaultHeartbeat.isExpired(90000 as Long, 0 as Long)))
    HeartbeatPolicy heartbeatCopy = heartbeat.copy()
    heartbeat.timeoutMillis(400 as Long)
    print("heartbeat-copy=" + str(heartbeatCopy.getTimeoutMillis()) + "," +
        str(heartbeat.getTimeoutMillis()))

    BackpressurePolicy policy = new BackpressurePolicy()
    print("bp-default=" + str(policy.getAcceptHighWaterConnections()) + "," +
        str(policy.getAcceptLowWaterConnections()) + "," + str(policy.getPendingAcceptHighWater()) +
        "," + str(policy.getPendingAcceptLowWater()) + "," + str(policy.getReadHighWaterBytes()) +
        "," + str(policy.getReadLowWaterBytes()) + "," + str(policy.isRejectOnHighWater()) + "," +
        str(policy.isPauseReads()))
    policy.acceptHighWaterConnections(96)
    policy.acceptLowWaterConnections(32)
    policy.pendingAcceptHighWater(64)
    policy.pendingAcceptLowWater(16)
    print("bp-bounds=" + str(policy.shouldPauseAccept(96, 0)) + "," +
        str(policy.shouldPauseAccept(95, 64)) + "," +
        str(policy.shouldPauseAccept(95, 15)) + "," +
        str(policy.canResumeAccept(32, 16)) + "," + str(policy.canResumeAccept(33, 0)))
    policy.rejectOnHighWater(true)
    print("bp-reject=" + str(policy.shouldPauseAccept(200, 200)))
    policy.rejectOnHighWater(false)
    policy.pauseReads(true)
    print("bp-read=" + str(policy.shouldPauseReads(1048576 as Long)) + "," +
        str(policy.shouldPauseReads(1048575 as Long)) + "," +
        str(policy.canResumeReads(262144 as Long)) + "," +
        str(policy.canResumeReads(262145 as Long)))
    policy.pauseReads(false)
    print("bp-read-off=" + str(policy.shouldPauseReads(1048576 as Long)) + "," +
        str(policy.canResumeReads(262145 as Long)))
    BackpressurePolicy bpCopy = policy.copy()
    policy.acceptHighWaterConnections(120)
    print("bp-copy=" + str(bpCopy.getAcceptHighWaterConnections()) + "," +
        str(policy.getAcceptHighWaterConnections()))

    ServiceReconnectPolicy serviceReconnect = new ServiceReconnectPolicy()
    print("sreconnect-default=" + str(serviceReconnect.getInitialDelayMillis()) + "," +
        str(serviceReconnect.getMaxDelayMillis()) + "," + str(serviceReconnect.getMultiplier()) +
        "," + str(serviceReconnect.getMaxAttempts()) + "," + str(serviceReconnect.isJitter()) +
        "," + str(serviceReconnect.retryableKinds().length()))
    print("sreconnect-retry=" + str(serviceReconnect.shouldRetry(0)) + "," +
        str(serviceReconnect.shouldRetry(4)) + "," + str(serviceReconnect.shouldRetry(5)))
    Error networkError = serviceNetwork("net")
    Error cancelledError = serviceCancelled("cancel")
    print("sreconnect-kind=" + str(serviceReconnect.shouldRetryError(0, networkError)) + "," +
        str(serviceReconnect.shouldRetryError(0, cancelledError)) + "," +
        str(serviceReconnect.isRetryableKind(ErrorKind.Busy)))
    serviceReconnect.clearRetryKinds()
    serviceReconnect.retryKind(ErrorKind.DataCorrupted)
    serviceReconnect.retryKind(ErrorKind.DataCorrupted)
    print("sreconnect-clear=" + str(serviceReconnect.retryableKinds().length()) + "," +
        str(serviceReconnect.isRetryableKind(ErrorKind.Network)) + "," +
        str(serviceReconnect.shouldRetryError(0, networkError)))
    serviceReconnect.jitter(false)
    serviceReconnect.initialDelayMillis(1000 as Long)
    serviceReconnect.maxDelayMillis(30000 as Long)
    print("sreconnect-delay=" + str(serviceReconnect.delayMillis(0)) + "," +
        str(serviceReconnect.delayMillis(1)) + "," + str(serviceReconnect.delayMillis(2)) + "," +
        str(serviceReconnect.delayMillis(10)))
    serviceReconnect.jitter(true)
    Long jitterOne = serviceReconnect.delayMillis(0)
    Long jitterTwo = serviceReconnect.delayMillis(0)
    print("sreconnect-jitter=" + str(jitterOne >= 800 as Long && jitterOne <= 1200 as Long) + "," +
        str(jitterOne == jitterTwo))
    ServiceReconnectPolicy serviceReconnectCopy = serviceReconnect.copy()
    serviceReconnect.maxAttempts(1)
    print("sreconnect-copy=" + str(serviceReconnectCopy.getMaxAttempts()) + "," +
        str(serviceReconnect.getMaxAttempts()))

    ServiceStats stats = new ServiceStats(1, 2 as Long, 3 as Long, 1, 4 as Long,
        5 as Long, 6 as Long, 7 as Long, 8 as Long, 9 as Long, 10 as Long, 11 as Long,
        12 as Long)
    print("stats=" + str(stats.activeConnections()) + "," + str(stats.totalConnections()) + "," +
        str(stats.rejectedConnections()) + "," + str(stats.activeSessions()) + "," +
        str(stats.totalSessions()) + "," + str(stats.bytesRead()) + "," +
        str(stats.bytesWritten()) + "," + str(stats.messagesReceived()) + "," +
        str(stats.messagesSent()) + "," + str(stats.reconnectAttempts()) + "," +
        str(stats.backpressureEvents()) + "," + str(stats.errors()) + "," +
        str(stats.uptimeMillis()))
    print("stats-describe=" + stats.describe())
    ServiceStats statsCopy = stats.copy()
    print("stats-copy=" + str(statsCopy.activeConnections()) + "," +
        str(statsCopy.uptimeMillis()))

    MemoryStream readStream = streamFrom("hello")
    Connection connection = connectionFor(readStream)
    Bytes buffer = Bytes.alloc(3)
    Result<Int, Error> readOne = connection.read(context, buffer)
    String readPrefix = buffer.slice(0, 2).toString()
    print("conn-read=" + str(readOne.value()) + "," + readPrefix + "," +
        str(connection.readBytes()) + "," + str(connection.isOpen()) + "," +
        str(connection.connectionId()))
    Result<Unit, Error> deadline = connection.setReadDeadline(123 as Long)
    print("conn-deadline=" + str(deadline.isOk()) + "," + str(readStream.readDeadlineCalls))

    MemoryStream writeStream = streamFrom("")
    writeStream.maxWriteChunk = 2
    Connection writer = new Connection(7 as Long, writeStream, localAddress(),
        localAddress(), 1024)
    Bytes payload = Bytes.fromString("abcd")
    Result<Int, Error> shortWrite = writer.write(context, payload)
    Result<Unit, Error> writeAll = writer.writeAll(context, payload)
    String writtenText = writeStream.output.toString()
    print("conn-write=" + str(shortWrite.value()) + "," + str(writeAll.isOk()) + "," +
        writtenText + "," + str(writer.writtenBytes()))
    Result<Unit, Error> drain = writer.beginDrain()
    Result<Int, Error> drainedWrite = writer.write(context, payload)
    print("conn-drain=" + str(drain.isOk()) + "," + str(writer.isDraining()) + "," +
        errorKindName(drainedWrite.error().kind()) + "," + str(writer.isOpen()))

    Result<Session, Error> sessionResult = connection.openSession(1024, new HeartbeatPolicy())
    Session session = sessionResult.value()
    Result<Session, Error> again = connection.openSession(512, new HeartbeatPolicy())
    print("session-open=" + str(sessionResult.isOk()) + "," + str(connection.hasSession()) +
        "," + str(again.value().sessionId()) + "," + str(session.readBufferBytes()))
    session.setAttribute("tenant", "a")
    print("session-attr=" + (session.attribute("tenant") as String) + "," +
        str(session.attribute("missing") == null) + "," + str(session.attributes().keys().length()))
    String? removed = session.removeAttribute("tenant")
    print("session-remove=" + (removed as String) + "," +
        str(session.removeAttribute("tenant") == null))
    Result<Unit, Error> sent = session.send(context, Bytes.fromString("xyz"))
    String sessionOutput = writeStream.output.toString()
    print("session-send=" + str(sent.isOk()) + "," + str(session.sentMessageCount()) + "," +
        str(session.bytesSent()) + "," + sessionOutput)
    print("session-idle=" + str(session.isIdle(0 as Long)) + "," + str(session.isOpen()))
    Result<Unit, Error> sessionClose = session.close()
    Result<Unit, Error> sessionCloseAgain = session.close()
    print("session-close=" + str(sessionClose.isOk()) + "," + str(sessionCloseAgain.isOk()) + "," +
        str(session.isOpen()) + "," + errorKindName(session.send(context,
            Bytes.fromString("z")).error().kind()))

    MemoryStream processStream = streamFrom("ab")
    Connection processConnection = connectionFor(processStream)
    RecordingConnectionHandler connectionHandler = new RecordingConnectionHandler()
    Result<Unit, Error> processed = processConnection.process(context, connectionHandler)
    print("process=" + str(processed.isOk()) + "," + eventsText(connectionHandler.events) + "," +
        str(processConnection.isOpen()) + "," + str(processConnection.readBytes()))

    MemoryStream openFailStream = streamFrom("")
    Connection openFailConnection = connectionFor(openFailStream)
    RecordingConnectionHandler openFailHandler = new RecordingConnectionHandler()
    openFailHandler.failOpen = true
    Result<Unit, Error> openFail = openFailConnection.process(context, openFailHandler)
    print("process-open-fail=" + errorKindName(openFail.error().kind()) + "," +
        eventsText(openFailHandler.events))

    MemoryStream messageFailStream = streamFrom("x")
    Connection messageFailConnection = connectionFor(messageFailStream)
    RecordingConnectionHandler messageFailHandler = new RecordingConnectionHandler()
    messageFailHandler.failMessage = true
    Result<Unit, Error> messageFail = messageFailConnection.process(context, messageFailHandler)
    print("process-message-fail=" + errorKindName(messageFail.error().kind()) + "," +
        eventsText(messageFailHandler.events))

    MemoryStream receiveStream = streamFrom("byte")
    Connection receiveConnection = connectionFor(receiveStream)
    Session receiveSession = receiveConnection.openSession(1024, new HeartbeatPolicy()).value()
    Result<Bytes?, Error> receivedOne = receiveSession.receive(context)
    Bytes? receivedBytes = receivedOne.value()
    Bytes messageBytes = receivedBytes as Bytes
    String receivedText = messageBytes.toString()
    Result<Bytes?, Error> receivedEnd = receiveSession.receive(context)
    print("session-receive=" + receivedText + "," + str(receivedEnd.value() == null) + "," +
        str(receiveSession.messageCount()) + "," + str(receiveSession.bytesReceived()))

    MemoryStream runStream = streamFrom("hi")
    Connection runConnection = connectionFor(runStream)
    Session runSession = runConnection.openSession(1024, new HeartbeatPolicy()).value()
    RecordingSessionHandler sessionHandler = new RecordingSessionHandler()
    Result<Unit, Error> ran = runSession.run(context, sessionHandler)
    print("session-run=" + str(ran.isOk()) + "," + eventsText(sessionHandler.events) + "," +
        str(runSession.messageCount()) + "," + str(runSession.bytesReceived()) + "," +
        str(runSession.isOpen()))

    MemoryStream runFailStream = streamFrom("")
    Connection runFailConnection = connectionFor(runFailStream)
    Session runFailSession = runFailConnection.openSession(1024, new HeartbeatPolicy()).value()
    RecordingSessionHandler runFailHandler = new RecordingSessionHandler()
    runFailHandler.failOpen = true
    Result<Unit, Error> runFail = runFailSession.run(context, runFailHandler)
    print("session-run-fail=" + errorKindName(runFail.error().kind()) + "," +
        eventsText(runFailHandler.events))

    MemoryStream heartbeatStream = streamFrom("")
    Connection heartbeatConnection = connectionFor(heartbeatStream)
    HeartbeatPolicy runHeartbeat = new HeartbeatPolicy()
    runHeartbeat.intervalMillis(10 as Long)
    runHeartbeat.timeoutMillis(20 as Long)
    Session heartbeatSession = heartbeatConnection.openSession(1024, runHeartbeat).value()
    RecordingSessionHandler heartbeatHandler = new RecordingSessionHandler()
    Result<Unit, Error> heartbeatRun = heartbeatSession.run(context, heartbeatHandler)
    print("session-heartbeat=" + str(heartbeatRun.isOk()) + "," +
        str(heartbeatStream.readDeadlineCalls > 0) + "," + eventsText(heartbeatHandler.events))

    MemoryStream closedStream = streamFrom("")
    Connection closedConnection = connectionFor(closedStream)
    Result<Unit, Error> connectionClose = closedConnection.close()
    Result<Unit, Error> connectionCloseAgain = closedConnection.close()
    print("conn-close=" + str(connectionClose.isOk()) + "," + str(connectionCloseAgain.isOk()) +
        "," + errorKindName(closedConnection.read(context, buffer).error().kind()) + "," +
        errorKindName(closedConnection.beginDrain().error().kind()) + "," +
        str(closedConnection.session() == null))

    SocketAddress serverAddress = SocketAddress.parse("127.0.0.1:19301").value()
    Server server = Server.bindDefault(context, serverAddress).value()
    EchoServiceHandler serverHandler = new EchoServiceHandler()
    TaskGroup serverGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> serverTask = serverGroup.spawn((Context taskContext) -> {
        server.serve(taskContext, serverHandler).value()
        return Ok(0)
    })
    sleepMs(20 as Long)
    ServiceReconnectPolicy clientPolicy = new ServiceReconnectPolicy()
    clientPolicy.maxAttempts(0)
    Client client = new Client(new ServiceOptions(), clientPolicy)
    OneShotClientHandler clientHandler = new OneShotClientHandler()
    TaskGroup clientGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> clientTask = clientGroup.spawn((Context taskContext) -> {
        client.connect(taskContext, serverAddress, clientHandler).value()
        return Ok(0)
    })
    clientTask.join()
    sleepMs(20 as Long)
    print("service-server-client=" + clientHandler.received + "," +
        serverHandler.messages.get(0) + "," + str(clientHandler.opened) + "," +
        str(clientHandler.closed) + "," + str(serverHandler.closed))
    ServiceStats serverStats = server.stats()
    ServiceStats clientStats = client.stats()
    print("service-stats=" + str(serverStats.totalConnections()) + "," +
        str(serverStats.totalSessions()) + "," + str(serverStats.messagesReceived()) + "," +
        str(serverStats.messagesSent()) + "," + str(serverStats.bytesRead() > 0) + "," +
        str(clientStats.totalConnections()) + "," + str(clientStats.messagesSent() > 0))
    Result<Unit, Error> serverClose = server.close()
    Result<Unit, Error> serverCloseAgain = server.close()
    serverTask.join()
    serverGroup.close()
    clientGroup.close()
    Result<Unit, Error> clientClose = client.close()
    Result<Unit, Error> clientCloseAgain = client.close()
    print("service-close=" + str(serverClose.isOk()) + "," + str(serverCloseAgain.isOk()) +
        "," + str(server.isOpen()) + "," + netServiceStateName(server.state()) + "," +
        str(clientClose.isOk()) + "," + str(clientCloseAgain.isOk()) + "," +
        netServiceStateName(client.state()) + "," + str(client.isOpen()))

    SocketAddress dropAddress = SocketAddress.parse("127.0.0.1:19302").value()
    Server dropServer = Server.bindDefault(context, dropAddress).value()
    EchoServiceHandler dropHandler = new EchoServiceHandler()
    TaskGroup dropGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> dropTask = dropGroup.spawn((Context taskContext) -> {
        dropServer.serve(taskContext, dropHandler).value()
        return Ok(0)
    })
    sleepMs(20 as Long)
    ServiceReconnectPolicy noRetry = new ServiceReconnectPolicy()
    noRetry.maxAttempts(0)
    Client dropClient = new Client(new ServiceOptions(), noRetry)
    HoldClientHandler dropClientHandler = new HoldClientHandler()
    TaskGroup dropClientGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> dropClientTask = dropClientGroup.spawn((Context taskContext) -> {
        dropClient.connect(taskContext, dropAddress, dropClientHandler).value()
        return Ok(0)
    })
    Bool dropReady = waitClientReady(dropClient)
    dropServer.close()
    dropClientTask.join()
    Error? dropError = dropClient.lastError()
    String dropKind = "none"
    if dropError != null {
        Error actualDrop = dropError as Error
        dropKind = errorKindName(actualDrop.kind())
    }
    print("service-drop=" + str(dropReady) + "," + str(dropClientHandler.opened) + "," +
        dropKind + "," + netServiceStateName(dropClient.state()) + "," +
        str(dropClient.connection() == null))
    dropClient.close()
    dropTask.join()
    dropGroup.close()
    dropClientGroup.close()

    SocketAddress netAddress = SocketAddress.parse("127.0.0.1:19303").value()
    NetworkService serverService = new NetworkService(new ServiceOptions())
    EchoServiceHandler netServerHandler = new EchoServiceHandler()
    Result<Server, Error> netServer = serverService.startServer(context, netAddress,
        netServerHandler)
    Bool serverServiceReady = waitServiceRunning(serverService)
    Result<Server, Error> duplicateServer = serverService.startServer(context, netAddress,
        netServerHandler)
    print("service-network-server=" + str(netServer.isOk()) + "," +
        str(serverServiceReady) + "," + netServiceStateName(serverService.state()) + "," +
        errorKindName(duplicateServer.error().kind()) + "," + str(serverService.stats().totalConnections()))
    Result<Unit, Error> serverStop = serverService.stop(context)
    Server? stoppedServer = serverService.server()
    Bool stoppedServerOpen = true
    if stoppedServer != null { Server value = stoppedServer as Server; stoppedServerOpen = value.isOpen() }
    print("service-network-server-stop=" + str(serverStop.isOk()) + "," +
        netServiceStateName(serverService.state()) + "," + str(stoppedServerOpen))
    Result<Unit, Error> netServerClose = serverService.close()
    Result<Unit, Error> netServerCloseAgain = serverService.close()
    Result<Server, Error> afterCloseServer = serverService.startServer(context, netAddress,
        netServerHandler)
    print("service-network-server-close=" + str(netServerClose.isOk()) + "," +
        str(netServerCloseAgain.isOk()) + "," + netServiceStateName(serverService.state()) + "," +
        errorKindName(afterCloseServer.error().kind()))

    SocketAddress netClientAddress = SocketAddress.parse("127.0.0.1:19305").value()
    Server netTarget = Server.bindDefault(context, netClientAddress).value()
    EchoServiceHandler netTargetHandler = new EchoServiceHandler()
    TaskGroup netTargetGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> netTargetTask = netTargetGroup.spawn((Context taskContext) -> {
        netTarget.serve(taskContext, netTargetHandler).value()
        return Ok(0)
    })
    sleepMs(10 as Long)
    NetworkService clientService = new NetworkService(new ServiceOptions())
    ServiceReconnectPolicy netPolicy = new ServiceReconnectPolicy()
    netPolicy.maxAttempts(0)
    HoldClientHandler netClientHandler = new HoldClientHandler()
    Result<Client, Error> netClient = clientService.startClientWithPolicy(context,
        netClientAddress, netClientHandler, netPolicy)
    Bool clientServiceReady = waitNetworkClientReady(clientService)
    Bool netReceived = waitHoldReceived(netClientHandler)
    Result<Client, Error> duplicateClient = clientService.startClient(context,
        netClientAddress, netClientHandler)
    ServiceStats netStats = clientService.stats()
    print("service-network-client=" + str(netClient.isOk()) + "," +
        str(clientServiceReady) + "," + netServiceStateName(clientService.state()) + "," +
        str(netReceived) + "," + errorKindName(duplicateClient.error().kind()) + "," +
        str(netStats.totalConnections() > 0) + "," + str(netStats.messagesSent() > 0))
    Result<Unit, Error> clientStop = clientService.stop(context)
    Client? stoppedClient = clientService.client()
    Bool stoppedClientOpen = true
    if stoppedClient != null { Client value = stoppedClient as Client; stoppedClientOpen = value.isOpen() }
    print("service-network-client-stop=" + str(clientStop.isOk()) + "," +
        netServiceStateName(clientService.state()) + "," + str(stoppedClientOpen))
    Result<Unit, Error> netClientClose = clientService.close()
    Result<Unit, Error> netClientCloseAgain = clientService.close()
    Result<Client, Error> afterCloseClient = clientService.startClient(context,
        netClientAddress, netClientHandler)
    print("service-network-client-close=" + str(netClientClose.isOk()) + "," +
        str(netClientCloseAgain.isOk()) + "," + netServiceStateName(clientService.state()) + "," +
        errorKindName(afterCloseClient.error().kind()))
    netTarget.close()
    netTargetTask.join()
    netTargetGroup.close()

    SocketAddress lateAddress = SocketAddress.parse("127.0.0.1:19304").value()
    ServiceReconnectPolicy retryPolicy = new ServiceReconnectPolicy()
    retryPolicy.initialDelayMillis(5 as Long)
    retryPolicy.maxDelayMillis(10 as Long)
    retryPolicy.maxAttempts(100)
    retryPolicy.jitter(false)
    retryPolicy.retryKind(ErrorKind.Io)
    Client retryClient = new Client(new ServiceOptions(), retryPolicy)
    HoldClientHandler retryClientHandler = new HoldClientHandler()
    TaskGroup retryClientGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> retryClientTask = retryClientGroup.spawn((Context taskContext) -> {
        retryClient.connect(taskContext, lateAddress, retryClientHandler).value()
        return Ok(0)
    })
    sleepMs(30 as Long)
    Server lateServer = Server.bindDefault(context, lateAddress).value()
    EchoServiceHandler lateHandler = new EchoServiceHandler()
    TaskGroup lateGroup = TaskGroup.create(Context.withCancel(context))
    Task<Int> lateTask = lateGroup.spawn((Context taskContext) -> {
        lateServer.serve(taskContext, lateHandler).value()
        return Ok(0)
    })
    Bool retryReceived = waitHoldReceived(retryClientHandler)
    ServiceStats retryStats = retryClient.stats()
    retryClient.close()
    retryClientTask.join()
    sleepMs(10 as Long)
    print("service-reconnect=" + retryClientHandler.receivedText + "," +
        str(retryReceived) + "," +
        str(retryStats.reconnectAttempts() > 0) + "," +
        str(retryStats.totalConnections()) + "," +
        str(lateHandler.messages.length() > 0))
    lateServer.close()
    lateTask.join()
    lateGroup.close()
    retryClientGroup.close()
    return 0

}
