// xdk.net.service —— 面向连接的服务编排核心子集（M19.4）
//
// 实现状态/选项/心跳/背压/重连策略、统计快照、连接/会话与处理器协议。
// Server/Client/NetworkService、TLS、真实主循环留 M19.5。
// 稳定性：preview。合同见 docs/design/solutions/net-service/。
package xdk.net.service
import xdk.errors
import xdk.bytes
import xdk.net
import xdk.runtime
import xdk.random
import xdk.time

// ---------- NetServiceState ----------
enum NetServiceState {
    Created,
    Starting,
    Running,
    Draining,
    Stopped,
    Closed,
    Failed,
}

String netServiceStateName(NetServiceState state) {
    if state == NetServiceState.Created { return "created" }
    if state == NetServiceState.Starting { return "starting" }
    if state == NetServiceState.Running { return "running" }
    if state == NetServiceState.Draining { return "draining" }
    if state == NetServiceState.Stopped { return "stopped" }
    if state == NetServiceState.Closed { return "closed" }
    return "failed"
}

Bool netServiceStateIsTerminal(NetServiceState state) {
    return state == NetServiceState.Closed
}

Bool netServiceStateCanServe(NetServiceState state) {
    return state == NetServiceState.Running
}

Bool netServiceStateIsActive(NetServiceState state) {
    return state == NetServiceState.Starting || state == NetServiceState.Running ||
        state == NetServiceState.Draining
}

// ---------- HeartbeatPolicy ----------
class HeartbeatPolicy {
    Long _intervalMillis
    Long _timeoutMillis

    HeartbeatPolicy() {
        self._intervalMillis = 0 as Long
        self._timeoutMillis = 30000 as Long
    }

    HeartbeatPolicy intervalMillis(Long value) {
        if value < 0 as Long { throw "HeartbeatPolicy.intervalMillis: negative" }
        if value > 0 as Long && value > self._timeoutMillis {
            throw "HeartbeatPolicy.intervalMillis: exceeds timeout"
        }
        self._intervalMillis = value
        return self
    }

    HeartbeatPolicy timeoutMillis(Long value) {
        if value <= 0 as Long { throw "HeartbeatPolicy.timeoutMillis: invalid" }
        if self._intervalMillis > 0 as Long && value < self._intervalMillis {
            throw "HeartbeatPolicy.timeoutMillis: below interval"
        }
        self._timeoutMillis = value
        return self
    }

    Long getIntervalMillis() { return self._intervalMillis }
    Long getTimeoutMillis() { return self._timeoutMillis }

    Bool isEnabled() { return self._intervalMillis > 0 as Long }

    Long deadlineFrom(Long lastActivityMonoMillis) {
        if lastActivityMonoMillis < 0 as Long {
            throw "HeartbeatPolicy.deadlineFrom: negative"
        }
        return lastActivityMonoMillis + self._timeoutMillis
    }

    Bool isExpired(Long nowMonoMillis, Long lastActivityMonoMillis) {
        if nowMonoMillis < 0 as Long || lastActivityMonoMillis < 0 as Long {
            throw "HeartbeatPolicy.isExpired: negative"
        }
        if !self.isEnabled() { return false }
        return nowMonoMillis >= lastActivityMonoMillis + self._timeoutMillis
    }

    HeartbeatPolicy copy() {
        HeartbeatPolicy out = new HeartbeatPolicy()
        out._intervalMillis = self._intervalMillis
        out._timeoutMillis = self._timeoutMillis
        return out
    }
}

// ---------- BackpressurePolicy ----------
class BackpressurePolicy {
    Int _acceptHighWaterConnections
    Int _acceptLowWaterConnections
    Int _pendingAcceptHighWater
    Int _pendingAcceptLowWater
    Long _readHighWaterBytes
    Long _readLowWaterBytes
    Bool _rejectOnHighWater
    Bool _pauseReads

    BackpressurePolicy() {
        self._acceptHighWaterConnections = 0
        self._acceptLowWaterConnections = 0
        self._pendingAcceptHighWater = 0
        self._pendingAcceptLowWater = 0
        self._readHighWaterBytes = 1048576 as Long
        self._readLowWaterBytes = 262144 as Long
        self._rejectOnHighWater = false
        self._pauseReads = true
    }

    BackpressurePolicy acceptHighWaterConnections(Int value) {
        if value < 0 { throw "BackpressurePolicy.acceptHighWaterConnections: negative" }
        if value == 0 && self._acceptLowWaterConnections > 0 {
            throw "BackpressurePolicy.acceptHighWaterConnections: low enabled"
        }
        if value > 0 && value <= self._acceptLowWaterConnections {
            throw "BackpressurePolicy.acceptHighWaterConnections: below low"
        }
        self._acceptHighWaterConnections = value
        return self
    }

    BackpressurePolicy acceptLowWaterConnections(Int value) {
        if value < 0 { throw "BackpressurePolicy.acceptLowWaterConnections: negative" }
        if self._acceptHighWaterConnections == 0 && value > 0 {
            throw "BackpressurePolicy.acceptLowWaterConnections: high disabled"
        }
        if self._acceptHighWaterConnections > 0 && value >= self._acceptHighWaterConnections {
            throw "BackpressurePolicy.acceptLowWaterConnections: not below high"
        }
        self._acceptLowWaterConnections = value
        return self
    }

    BackpressurePolicy pendingAcceptHighWater(Int value) {
        if value < 0 { throw "BackpressurePolicy.pendingAcceptHighWater: negative" }
        if value == 0 && self._pendingAcceptLowWater > 0 {
            throw "BackpressurePolicy.pendingAcceptHighWater: low enabled"
        }
        if value > 0 && value <= self._pendingAcceptLowWater {
            throw "BackpressurePolicy.pendingAcceptHighWater: below low"
        }
        self._pendingAcceptHighWater = value
        return self
    }

    BackpressurePolicy pendingAcceptLowWater(Int value) {
        if value < 0 { throw "BackpressurePolicy.pendingAcceptLowWater: negative" }
        if self._pendingAcceptHighWater == 0 && value > 0 {
            throw "BackpressurePolicy.pendingAcceptLowWater: high disabled"
        }
        if self._pendingAcceptHighWater > 0 && value >= self._pendingAcceptHighWater {
            throw "BackpressurePolicy.pendingAcceptLowWater: not below high"
        }
        self._pendingAcceptLowWater = value
        return self
    }

    BackpressurePolicy readHighWaterBytes(Long value) {
        if value <= 0 as Long { throw "BackpressurePolicy.readHighWaterBytes: invalid" }
        if value <= self._readLowWaterBytes {
            throw "BackpressurePolicy.readHighWaterBytes: below low"
        }
        self._readHighWaterBytes = value
        return self
    }

    BackpressurePolicy readLowWaterBytes(Long value) {
        if value <= 0 as Long { throw "BackpressurePolicy.readLowWaterBytes: invalid" }
        if value >= self._readHighWaterBytes {
            throw "BackpressurePolicy.readLowWaterBytes: not below high"
        }
        self._readLowWaterBytes = value
        return self
    }

    BackpressurePolicy rejectOnHighWater(Bool value) {
        self._rejectOnHighWater = value
        return self
    }

    BackpressurePolicy pauseReads(Bool value) {
        self._pauseReads = value
        return self
    }

    Int getAcceptHighWaterConnections() { return self._acceptHighWaterConnections }
    Int getAcceptLowWaterConnections() { return self._acceptLowWaterConnections }
    Int getPendingAcceptHighWater() { return self._pendingAcceptHighWater }
    Int getPendingAcceptLowWater() { return self._pendingAcceptLowWater }
    Long getReadHighWaterBytes() { return self._readHighWaterBytes }
    Long getReadLowWaterBytes() { return self._readLowWaterBytes }
    Bool isRejectOnHighWater() { return self._rejectOnHighWater }
    Bool isPauseReads() { return self._pauseReads }

    Bool shouldPauseAccept(Int activeConnections, Int pendingAccepts) {
        if activeConnections < 0 || pendingAccepts < 0 {
            throw "BackpressurePolicy.shouldPauseAccept: negative"
        }
        if self._rejectOnHighWater { return false }
        if self._acceptHighWaterConnections > 0 &&
            activeConnections >= self._acceptHighWaterConnections {
            return true
        }
        if self._pendingAcceptHighWater > 0 &&
            pendingAccepts >= self._pendingAcceptHighWater {
            return true
        }
        return false
    }

    Bool canResumeAccept(Int activeConnections, Int pendingAccepts) {
        if activeConnections < 0 || pendingAccepts < 0 {
            throw "BackpressurePolicy.canResumeAccept: negative"
        }
        if self._acceptHighWaterConnections > 0 &&
            activeConnections > self._acceptLowWaterConnections {
            return false
        }
        if self._pendingAcceptHighWater > 0 &&
            pendingAccepts > self._pendingAcceptLowWater {
            return false
        }
        return true
    }

    Bool shouldPauseReads(Long bufferedBytes) {
        if bufferedBytes < 0 as Long {
            throw "BackpressurePolicy.shouldPauseReads: negative"
        }
        if !self._pauseReads { return false }
        return bufferedBytes >= self._readHighWaterBytes
    }

    Bool canResumeReads(Long bufferedBytes) {
        if bufferedBytes < 0 as Long {
            throw "BackpressurePolicy.canResumeReads: negative"
        }
        if !self._pauseReads { return true }
        return bufferedBytes <= self._readLowWaterBytes
    }

    BackpressurePolicy copy() {
        BackpressurePolicy out = new BackpressurePolicy()
        out._acceptHighWaterConnections = self._acceptHighWaterConnections
        out._acceptLowWaterConnections = self._acceptLowWaterConnections
        out._pendingAcceptHighWater = self._pendingAcceptHighWater
        out._pendingAcceptLowWater = self._pendingAcceptLowWater
        out._readHighWaterBytes = self._readHighWaterBytes
        out._readLowWaterBytes = self._readLowWaterBytes
        out._rejectOnHighWater = self._rejectOnHighWater
        out._pauseReads = self._pauseReads
        return out
    }
}

// ---------- ServiceReconnectPolicy ----------
class ServiceReconnectPolicy {
    Long _initialDelayMillis
    Long _maxDelayMillis
    Double _multiplier
    Int _maxAttempts
    Bool _jitter
    List<ErrorKind> _retryableKinds

    ServiceReconnectPolicy() {
        self._initialDelayMillis = 1000 as Long
        self._maxDelayMillis = 30000 as Long
        self._multiplier = 2.0
        self._maxAttempts = 5
        self._jitter = true
        self._retryableKinds = [ErrorKind.Network, ErrorKind.Timeout, ErrorKind.Unavailable, ErrorKind.Busy]
    }

    ServiceReconnectPolicy initialDelayMillis(Long value) {
        if value < 0 as Long {
            throw "ServiceReconnectPolicy.initialDelayMillis: negative"
        }
        if value > self._maxDelayMillis {
            throw "ServiceReconnectPolicy.initialDelayMillis: exceeds max"
        }
        self._initialDelayMillis = value
        return self
    }

    ServiceReconnectPolicy maxDelayMillis(Long value) {
        if value < self._initialDelayMillis {
            throw "ServiceReconnectPolicy.maxDelayMillis: below initial"
        }
        self._maxDelayMillis = value
        return self
    }

    ServiceReconnectPolicy multiplier(Double value) {
        if value < 1.0 { throw "ServiceReconnectPolicy.multiplier: below one" }
        if value != value { throw "ServiceReconnectPolicy.multiplier: NaN" }
        self._multiplier = value
        return self
    }

    ServiceReconnectPolicy maxAttempts(Int value) {
        if value < 0 { throw "ServiceReconnectPolicy.maxAttempts: negative" }
        self._maxAttempts = value
        return self
    }

    ServiceReconnectPolicy jitter(Bool value) {
        self._jitter = value
        return self
    }

    ServiceReconnectPolicy retryKind(ErrorKind kind) {
        if kind == null { throw "ServiceReconnectPolicy.retryKind: null" }
        if !self.isRetryableKind(kind) {
            self._retryableKinds.push(kind)
        }
        return self
    }

    ServiceReconnectPolicy clearRetryKinds() {
        self._retryableKinds = []
        return self
    }

    Long getInitialDelayMillis() { return self._initialDelayMillis }
    Long getMaxDelayMillis() { return self._maxDelayMillis }
    Double getMultiplier() { return self._multiplier }
    Int getMaxAttempts() { return self._maxAttempts }
    Bool isJitter() { return self._jitter }

    List<ErrorKind> retryableKinds() { return self._retryableKinds.copy() }

    Bool isRetryableKind(ErrorKind kind) {
        if kind == null { throw "ServiceReconnectPolicy.isRetryableKind: null" }
        Int index = 0
        while index < self._retryableKinds.length() {
            if self._retryableKinds.get(index) == kind { return true }
            index = index + 1
        }
        return false
    }

    Bool shouldRetry(Int attempt) {
        if attempt < 0 { throw "ServiceReconnectPolicy.shouldRetry: negative" }
        return attempt < self._maxAttempts
    }

    Bool shouldRetryError(Int attempt, Error error) {
        if attempt < 0 { throw "ServiceReconnectPolicy.shouldRetry: negative" }
        if error == null { throw "ServiceReconnectPolicy.shouldRetry: null error" }
        if !self.shouldRetry(attempt) { return false }
        return self.isRetryableKind(error.kind())
    }

    Long delayMillis(Int attempt) {
        if attempt < 0 { throw "ServiceReconnectPolicy.delayMillis: negative" }
        Double value = self._initialDelayMillis as Double
        Int index = 0
        while index < attempt {
            value = value * self._multiplier
            index = index + 1
        }
        Double maxValue = self._maxDelayMillis as Double
        if value > maxValue { value = maxValue }
        if self._jitter {
            Long seed = attempt as Long
            seed = seed * (7919 as Long) + (104729 as Long)
            Random random = new Random(seed)
            Double factor = 0.8 + random.nextDouble() * 0.4
            value = value * factor
        }
        return value as Long
    }

    ServiceReconnectPolicy copy() {
        ServiceReconnectPolicy out = new ServiceReconnectPolicy()
        out._initialDelayMillis = self._initialDelayMillis
        out._maxDelayMillis = self._maxDelayMillis
        out._multiplier = self._multiplier
        out._maxAttempts = self._maxAttempts
        out._jitter = self._jitter
        out._retryableKinds = self._retryableKinds.copy()
        return out
    }
}

// ---------- ServiceOptions ----------
class ServiceOptions {
    Int _maxConnections
    Int _acceptQueueCapacity
    Long _acceptBackoffMillis
    Int _readBufferBytes
    Long _idleTimeoutMillis
    Long _readTimeoutMillis
    Long _writeTimeoutMillis
    Long _gracefulShutdownTimeoutMillis
    BackpressurePolicy _backpressurePolicy
    HeartbeatPolicy _heartbeatPolicy
    ServiceReconnectPolicy _reconnectPolicy

    ServiceOptions() {
        self._maxConnections = 128
        self._acceptQueueCapacity = 256
        self._acceptBackoffMillis = 100 as Long
        self._readBufferBytes = 32768
        self._idleTimeoutMillis = 0 as Long
        self._readTimeoutMillis = 0 as Long
        self._writeTimeoutMillis = 0 as Long
        self._gracefulShutdownTimeoutMillis = 30000 as Long
        self._backpressurePolicy = new BackpressurePolicy()
        self._heartbeatPolicy = new HeartbeatPolicy()
        self._reconnectPolicy = new ServiceReconnectPolicy()
    }

    ServiceOptions maxConnections(Int value) {
        if value <= 0 { throw "ServiceOptions.maxConnections: invalid" }
        self._maxConnections = value
        return self
    }

    ServiceOptions acceptQueueCapacity(Int value) {
        if value < 0 { throw "ServiceOptions.acceptQueueCapacity: negative" }
        self._acceptQueueCapacity = value
        return self
    }

    ServiceOptions acceptBackoffMillis(Long value) {
        if value < 0 as Long { throw "ServiceOptions.acceptBackoffMillis: negative" }
        self._acceptBackoffMillis = value
        return self
    }

    ServiceOptions readBufferBytes(Int value) {
        if value < 1024 { throw "ServiceOptions.readBufferBytes: too small" }
        if value > 1048576 { throw "ServiceOptions.readBufferBytes: too large" }
        self._readBufferBytes = value
        return self
    }

    ServiceOptions idleTimeoutMillis(Long value) {
        if value < 0 as Long { throw "ServiceOptions.idleTimeoutMillis: negative" }
        self._idleTimeoutMillis = value
        return self
    }

    ServiceOptions readTimeoutMillis(Long value) {
        if value < 0 as Long { throw "ServiceOptions.readTimeoutMillis: negative" }
        self._readTimeoutMillis = value
        return self
    }

    ServiceOptions writeTimeoutMillis(Long value) {
        if value < 0 as Long { throw "ServiceOptions.writeTimeoutMillis: negative" }
        self._writeTimeoutMillis = value
        return self
    }

    ServiceOptions gracefulShutdownTimeoutMillis(Long value) {
        if value < 0 as Long {
            throw "ServiceOptions.gracefulShutdownTimeoutMillis: negative"
        }
        self._gracefulShutdownTimeoutMillis = value
        return self
    }

    ServiceOptions backpressurePolicy(BackpressurePolicy value) {
        if value == null { throw "ServiceOptions.backpressurePolicy: null" }
        self._backpressurePolicy = value.copy()
        return self
    }

    ServiceOptions heartbeatPolicy(HeartbeatPolicy value) {
        if value == null { throw "ServiceOptions.heartbeatPolicy: null" }
        self._heartbeatPolicy = value.copy()
        return self
    }

    ServiceOptions reconnectPolicy(ServiceReconnectPolicy value) {
        if value == null { throw "ServiceOptions.reconnectPolicy: null" }
        self._reconnectPolicy = value.copy()
        return self
    }

    Int getMaxConnections() { return self._maxConnections }
    Int getAcceptQueueCapacity() { return self._acceptQueueCapacity }
    Long getAcceptBackoffMillis() { return self._acceptBackoffMillis }
    Int getReadBufferBytes() { return self._readBufferBytes }
    Long getIdleTimeoutMillis() { return self._idleTimeoutMillis }
    Long getReadTimeoutMillis() { return self._readTimeoutMillis }
    Long getWriteTimeoutMillis() { return self._writeTimeoutMillis }
    Long getGracefulShutdownTimeoutMillis() {
        return self._gracefulShutdownTimeoutMillis
    }

    BackpressurePolicy getBackpressurePolicy() { return self._backpressurePolicy.copy() }
    HeartbeatPolicy getHeartbeatPolicy() { return self._heartbeatPolicy.copy() }
    ServiceReconnectPolicy getReconnectPolicy() { return self._reconnectPolicy.copy() }

    ServiceOptions copy() {
        ServiceOptions out = new ServiceOptions()
        out._maxConnections = self._maxConnections
        out._acceptQueueCapacity = self._acceptQueueCapacity
        out._acceptBackoffMillis = self._acceptBackoffMillis
        out._readBufferBytes = self._readBufferBytes
        out._idleTimeoutMillis = self._idleTimeoutMillis
        out._readTimeoutMillis = self._readTimeoutMillis
        out._writeTimeoutMillis = self._writeTimeoutMillis
        out._gracefulShutdownTimeoutMillis = self._gracefulShutdownTimeoutMillis
        out._backpressurePolicy = self._backpressurePolicy.copy()
        out._heartbeatPolicy = self._heartbeatPolicy.copy()
        out._reconnectPolicy = self._reconnectPolicy.copy()
        return out
    }
}

// ---------- ServiceStats ----------
class ServiceStats {
    final Int _activeConnections
    final Long _totalConnections
    final Long _rejectedConnections
    final Int _activeSessions
    final Long _totalSessions
    final Long _bytesRead
    final Long _bytesWritten
    final Long _messagesReceived
    final Long _messagesSent
    final Long _reconnectAttempts
    final Long _backpressureEvents
    final Long _errors
    final Long _uptimeMillis

    ServiceStats(Int activeConnections, Long totalConnections,
                 Long rejectedConnections, Int activeSessions,
                 Long totalSessions, Long bytesRead, Long bytesWritten,
                 Long messagesReceived, Long messagesSent,
                 Long reconnectAttempts, Long backpressureEvents,
                 Long errors, Long uptimeMillis) {
        if activeConnections < 0 || totalConnections < 0 as Long ||
            rejectedConnections < 0 as Long || activeSessions < 0 ||
            totalSessions < 0 as Long || bytesRead < 0 as Long ||
            bytesWritten < 0 as Long || messagesReceived < 0 as Long ||
            messagesSent < 0 as Long || reconnectAttempts < 0 as Long ||
            backpressureEvents < 0 as Long || errors < 0 as Long ||
            uptimeMillis < 0 as Long {
            throw "ServiceStats: negative value"
        }
        self._activeConnections = activeConnections
        self._totalConnections = totalConnections
        self._rejectedConnections = rejectedConnections
        self._activeSessions = activeSessions
        self._totalSessions = totalSessions
        self._bytesRead = bytesRead
        self._bytesWritten = bytesWritten
        self._messagesReceived = messagesReceived
        self._messagesSent = messagesSent
        self._reconnectAttempts = reconnectAttempts
        self._backpressureEvents = backpressureEvents
        self._errors = errors
        self._uptimeMillis = uptimeMillis
    }

    Int activeConnections() { return self._activeConnections }
    Long totalConnections() { return self._totalConnections }
    Long rejectedConnections() { return self._rejectedConnections }
    Int activeSessions() { return self._activeSessions }
    Long totalSessions() { return self._totalSessions }
    Long bytesRead() { return self._bytesRead }
    Long bytesWritten() { return self._bytesWritten }
    Long messagesReceived() { return self._messagesReceived }
    Long messagesSent() { return self._messagesSent }
    Long reconnectAttempts() { return self._reconnectAttempts }
    Long backpressureEvents() { return self._backpressureEvents }
    Long errors() { return self._errors }
    Long uptimeMillis() { return self._uptimeMillis }

    String describe() {
        String text = "connections active=" + str(self._activeConnections)
        text = text + " total=" + str(self._totalConnections)
        text = text + " rejected=" + str(self._rejectedConnections)
        text = text + " sessions active=" + str(self._activeSessions)
        text = text + " total=" + str(self._totalSessions)
        text = text + " bytesIn=" + str(self._bytesRead)
        text = text + " bytesOut=" + str(self._bytesWritten)
        text = text + " messagesIn=" + str(self._messagesReceived)
        text = text + " messagesOut=" + str(self._messagesSent)
        text = text + " reconnects=" + str(self._reconnectAttempts)
        text = text + " backpressure=" + str(self._backpressureEvents)
        text = text + " errors=" + str(self._errors)
        text = text + " uptimeMillis=" + str(self._uptimeMillis)
        return text
    }

    ServiceStats copy() {
        return new ServiceStats(self._activeConnections, self._totalConnections,
            self._rejectedConnections, self._activeSessions, self._totalSessions,
            self._bytesRead, self._bytesWritten, self._messagesReceived,
            self._messagesSent, self._reconnectAttempts, self._backpressureEvents,
            self._errors, self._uptimeMillis)
    }
}

// ---------- Handler protocols ----------
protocol ConnectionHandler {
    Result<Unit, Error> onOpen(Context context, Connection connection);
    Result<Unit, Error> onMessage(Context context, Connection connection, Bytes message);
    Result<Unit, Error> onClose(Context context, Connection connection, Error? cause);
    Result<Unit, Error> onError(Context context, Connection connection, Error error);
}

protocol SessionHandler {
    Result<Unit, Error> onOpen(Context context, Session session);
    Result<Unit, Error> onMessage(Context context, Session session, Bytes message);
    Result<Unit, Error> onClose(Context context, Session session, Error? cause);
    Result<Unit, Error> onError(Context context, Session session, Error error);
}

// ---------- Connection ----------
class Connection {
    final ByteStream _stream
    final SocketAddress _local
    final SocketAddress _remote
    final Long _connectionId
    final Long _openedAtMonoMillis
    final Int _readBufferBytes
    Long _lastActivityMonoMillis
    Long _readBytes
    Long _writtenBytes
    Bool _open
    Bool _draining
    Session? _session

    Connection(Long connectionId, ByteStream stream, SocketAddress local,
               SocketAddress remote, Int readBufferBytes) {
        if stream == null || local == null || remote == null {
            throw "Connection: null argument"
        }
        if connectionId < 0 as Long { throw "Connection: negative id" }
        if readBufferBytes <= 0 { throw "Connection: invalid buffer" }
        self._stream = stream
        self._local = local
        self._remote = remote
        self._connectionId = connectionId
        self._openedAtMonoMillis = nowMono()
        self._readBufferBytes = readBufferBytes
        self._lastActivityMonoMillis = self._openedAtMonoMillis
        self._readBytes = 0 as Long
        self._writtenBytes = 0 as Long
        self._open = true
        self._draining = false
        self._session = null
    }

    Long connectionId() { return self._connectionId }
    SocketAddress localAddress() { return self._local }
    SocketAddress remoteAddress() { return self._remote }
    Long openedAtMonoMillis() { return self._openedAtMonoMillis }
    Long lastActivityMonoMillis() { return self._lastActivityMonoMillis }
    Long readBytes() { return self._readBytes }
    Long writtenBytes() { return self._writtenBytes }
    Int readBufferBytes() { return self._readBufferBytes }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "Connection.read: null argument"
        }
        if !self.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "connection"))
        }
        Result<Int, Error> result = self._stream.read(context, buffer)
        if result.isErr() { return result }
        if result.value() > 0 {
            self._readBytes = self._readBytes + (result.value() as Long)
            self._lastActivityMonoMillis = nowMono()
        }
        return result
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if context == null || data == null {
            throw "Connection.write: null argument"
        }
        if !self.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "connection"))
        }
        if self._draining {
            return Err(new BasicError(ErrorKind.Busy, "connection draining"))
        }
        Result<Int, Error> result = self._stream.write(context, data)
        if result.isErr() { return result }
        if result.value() > 0 {
            self._writtenBytes = self._writtenBytes + (result.value() as Long)
            self._lastActivityMonoMillis = nowMono()
        }
        return result
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        if context == null || data == null {
            throw "Connection.writeAll: null argument"
        }
        Int total = 0
        while total < data.length() {
            Bytes part = data.slice(total, data.length())
            Result<Int, Error> written = self.write(context, part)
            if written.isErr() { return Err(written.error()) }
            if written.value() < 1 {
                return Err(new BasicError(ErrorKind.Unavailable, "connection write"))
            }
            total = total + written.value()
        }
        return Ok()
    }

    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis) {
        if !self.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "connection"))
        }
        return self._stream.setReadDeadline(deadlineMonoMillis)
    }

    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis) {
        if !self.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "connection"))
        }
        return self._stream.setWriteDeadline(deadlineMonoMillis)
    }

    Bool isOpen() {
        if !self._open { return false }
        return self._stream.isOpen()
    }

    Result<Unit, Error> beginDrain() {
        if !self.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "connection"))
        }
        self._draining = true
        return Ok()
    }

    Bool isDraining() { return self._draining }
    Bool hasSession() { return self._session != null }
    Session? session() { return self._session }

    Result<Session, Error> openSession(Int readBufferBytes,
                                       HeartbeatPolicy heartbeatPolicy) {
        if heartbeatPolicy == null {
            throw "Connection.openSession: null heartbeat policy"
        }
        if readBufferBytes <= 0 {
            throw "Connection.openSession: invalid buffer"
        }
        if !self.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "connection"))
        }
        if self._session != null {
            return Ok(self._session as Session)
        }
        Session created = new Session(self._connectionId, self,
            readBufferBytes, heartbeatPolicy.copy())
        self._session = created
        return Ok(created)
    }

    Result<Session, Error> openDefaultSession() {
        return self.openSession(self._readBufferBytes, new HeartbeatPolicy())
    }

    Result<Unit, Error> process(Context context, ConnectionHandler handler) {
        if context == null || handler == null {
            throw "Connection.process: null argument"
        }
        if !self.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "connection"))
        }
        Result<Unit, Error> opened = handler.onOpen(context, self)
        if opened.isErr() {
            Error openError = opened.error()
            handler.onError(context, self, openError)
            Result<Unit, Error> closed = self.close()
            handler.onClose(context, self, openError)
            if closed.isErr() { return Err(closed.error()) }
            return Err(openError)
        }
        Bytes buffer = Bytes.alloc(self._readBufferBytes)
        Error? cause = null
        Result<Unit, Error> result = Ok()
        while self.isOpen() && !context.isCancelled() {
            Result<Int, Error> read = self.read(context, buffer)
            if read.isErr() {
                Error readError = read.error()
                cause = readError
                result = Err(readError)
                break
            }
            if read.value() < 1 { break }
            Bytes message = buffer.slice(0, read.value())
            Result<Unit, Error> handled = handler.onMessage(context, self, message)
            if handled.isErr() {
                Error handledError = handled.error()
                cause = handledError
                result = Err(handledError)
                break
            }
        }
        if context.isCancelled() && cause == null {
            Error cancelled = new BasicError(ErrorKind.Cancelled, "connection cancelled")
            cause = cancelled
            result = Err(cancelled)
        }
        if cause != null {
            Error finalCause = cause as Error
            Result<Unit, Error> reported = handler.onError(context, self, finalCause)
            if reported.isErr() && result.isOk() {
                result = Err(reported.error())
            }
        }
        Result<Unit, Error> closed = self.close()
        handler.onClose(context, self, cause)
        if result.isOk() && closed.isErr() {
            result = Err(closed.error())
        }
        return result
    }

    String describe() {
        String text = "connection id=" + str(self._connectionId)
        text = text + " local=" + self._local.text()
        text = text + " remote=" + self._remote.text()
        text = text + " open=" + str(self.isOpen())
        text = text + " draining=" + str(self._draining)
        text = text + " readBytes=" + str(self._readBytes)
        text = text + " writtenBytes=" + str(self._writtenBytes)
        return text
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        self._draining = false
        self._stream.close()
        return Ok()
    }
}

// ---------- Session ----------
class Session {
    final Long _sessionId
    final Connection _connection
    final Int _readBufferBytes
    final HeartbeatPolicy _heartbeatPolicy
    final Long _openedAtMonoMillis
    Long _lastActivityMonoMillis
    Long _messagesReceived
    Long _messagesSent
    Long _bytesReceived
    Long _bytesSent
    Map<String, String> _attributes
    Bool _sessionOpen

    Session(Long sessionId, Connection connection, Int readBufferBytes,
            HeartbeatPolicy heartbeatPolicy) {
        if connection == null || heartbeatPolicy == null {
            throw "Session: null argument"
        }
        if sessionId < 0 as Long { throw "Session: negative id" }
        if readBufferBytes <= 0 { throw "Session: invalid buffer" }
        self._sessionId = sessionId
        self._connection = connection
        self._readBufferBytes = readBufferBytes
        self._heartbeatPolicy = heartbeatPolicy.copy()
        self._openedAtMonoMillis = nowMono()
        self._lastActivityMonoMillis = self._openedAtMonoMillis
        self._messagesReceived = 0 as Long
        self._messagesSent = 0 as Long
        self._bytesReceived = 0 as Long
        self._bytesSent = 0 as Long
        Map<String, String> attributes = [:]
        self._attributes = attributes
        self._sessionOpen = true
    }

    Long sessionId() { return self._sessionId }
    Connection connection() { return self._connection }
    Long openedAtMonoMillis() { return self._openedAtMonoMillis }
    Long lastActivityMonoMillis() { return self._lastActivityMonoMillis }
    Long messageCount() { return self._messagesReceived }
    Long sentMessageCount() { return self._messagesSent }
    Long bytesReceived() { return self._bytesReceived }
    Long bytesSent() { return self._bytesSent }
    Int readBufferBytes() { return self._readBufferBytes }
    HeartbeatPolicy heartbeatPolicy() { return self._heartbeatPolicy.copy() }

    String? attribute(String name) {
        if name == null || name == "" {
            throw "Session.attribute: empty name"
        }
        if !self._attributes.has(name) { return null }
        return self._attributes.getOr(name, "")
    }

    Void setAttribute(String name, String value) {
        if name == null || name == "" {
            throw "Session.setAttribute: empty name"
        }
        if value == null {
            throw "Session.setAttribute: null value"
        }
        self._attributes.put(name, value)
    }

    String? removeAttribute(String name) {
        if name == null || name == "" {
            throw "Session.removeAttribute: empty name"
        }
        if !self._attributes.has(name) { return null }
        String value = self._attributes.getOr(name, "")
        self._attributes.remove(name)
        return value
    }

    Map<String, String> attributes() {
        Map<String, String> result = [:]
        List<String> keys = self._attributes.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            result.put(key, self._attributes.getOr(key, ""))
            index = index + 1
        }
        return result
    }

    Result<Unit, Error> send(Context context, Bytes data) {
        if context == null || data == null {
            throw "Session.send: null argument"
        }
        if !self.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "session"))
        }
        Result<Unit, Error> result = self._connection.writeAll(context, data)
        if result.isErr() { return result }
        self._messagesSent = self._messagesSent + 1 as Long
        self._bytesSent = self._bytesSent + (data.length() as Long)
        self._lastActivityMonoMillis = self._connection.lastActivityMonoMillis()
        return Ok()
    }

    Bool isIdle(Long nowMonoMillis) {
        if nowMonoMillis < 0 as Long { throw "Session.isIdle: negative" }
        return self._heartbeatPolicy.isExpired(nowMonoMillis, self._lastActivityMonoMillis)
    }

    Result<Bytes?, Error> receive(Context context) {
        if context == null { throw "Session.receive: null argument" }
        if !self.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "session"))
        }
        Bytes buffer = Bytes.alloc(self._readBufferBytes)
        Result<Int, Error> read = self._connection.read(context, buffer)
        if read.isErr() { return Err(read.error()) }
        Int count = read.value()
        if count < 1 { return Ok(null) }
        Bytes message = buffer.slice(0, count)
        self._messagesReceived = self._messagesReceived + 1 as Long
        self._bytesReceived = self._bytesReceived + (count as Long)
        self._lastActivityMonoMillis = self._connection.lastActivityMonoMillis()
        return Ok(message)
    }

    Bool isOpen() {
        if !self._sessionOpen { return false }
        return self._connection.isOpen()
    }

    Result<Unit, Error> run(Context context, SessionHandler handler) {
        if context == null || handler == null {
            throw "Session.run: null argument"
        }
        if !self.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "session"))
        }
        Result<Unit, Error> opened = handler.onOpen(context, self)
        if opened.isErr() {
            Error openError = opened.error()
            handler.onError(context, self, openError)
            Result<Unit, Error> closed = self.close()
            handler.onClose(context, self, openError)
            if closed.isErr() { return Err(closed.error()) }
            return Err(openError)
        }
        Bytes buffer = Bytes.alloc(self._readBufferBytes)
        Error? cause = null
        Result<Unit, Error> result = Ok()
        while self.isOpen() && !context.isCancelled() {
            if self._heartbeatPolicy.isEnabled() {
                Long deadline = nowMono() + self._heartbeatPolicy.getTimeoutMillis()
                Result<Unit, Error> deadlineResult =
                    self._connection.setReadDeadline(deadline)
                if deadlineResult.isErr() {
                    Error deadlineError = deadlineResult.error()
                    cause = deadlineError
                    result = Err(deadlineError)
                    break
                }
            }
            Result<Int, Error> read = self._connection.read(context, buffer)
            if read.isErr() {
                Error readError = read.error()
                cause = readError
                result = Err(readError)
                break
            }
            if read.value() < 1 { break }
            Bytes message = buffer.slice(0, read.value())
            self._messagesReceived = self._messagesReceived + 1 as Long
            self._bytesReceived = self._bytesReceived + (read.value() as Long)
            self._lastActivityMonoMillis = self._connection.lastActivityMonoMillis()
            Result<Unit, Error> handled = handler.onMessage(context, self, message)
            if handled.isErr() {
                Error handledError = handled.error()
                cause = handledError
                result = Err(handledError)
                break
            }
        }
        if context.isCancelled() && cause == null {
            Error cancelled = new BasicError(ErrorKind.Cancelled, "session cancelled")
            cause = cancelled
            result = Err(cancelled)
        }
        if cause != null {
            Error finalCause = cause as Error
            Result<Unit, Error> reported = handler.onError(context, self, finalCause)
            if reported.isErr() && result.isOk() {
                result = Err(reported.error())
            }
        }
        Result<Unit, Error> closed = self.close()
        handler.onClose(context, self, cause)
        if result.isOk() && closed.isErr() {
            result = Err(closed.error())
        }
        return result
    }

    String describe() {
        String text = "session id=" + str(self._sessionId)
        text = text + " connection=" + str(self._connection.connectionId())
        text = text + " open=" + str(self.isOpen())
        text = text + " messagesIn=" + str(self._messagesReceived)
        text = text + " messagesOut=" + str(self._messagesSent)
        text = text + " bytesIn=" + str(self._bytesReceived)
        text = text + " bytesOut=" + str(self._bytesSent)
        return text
    }

    Result<Unit, Error> close() {
        if !self._sessionOpen { return Ok() }
        self._sessionOpen = false
        return self._connection.close()
    }
}

// ---------- Server ----------
class Server {
    final TcpListener _listener
    final ServiceOptions _options
    final Long _startedAtMonoMillis
    NetServiceState _state
    Bool _served
    Bool _closed
    Long _nextConnectionId
    Connection? _activeConnection
    Session? _activeSession
    Long _totalConnections
    Long _rejectedConnections
    Long _totalSessions
    Long _bytesRead
    Long _bytesWritten
    Long _messagesReceived
    Long _messagesSent
    Long _backpressureEvents
    Long _errors

    private Server(TcpListener listener, ServiceOptions options) {
        if listener == null || options == null { throw "Server: null argument" }
        self._listener = listener
        self._options = options.copy()
        self._startedAtMonoMillis = nowMono()
        self._state = NetServiceState.Created
        self._served = false
        self._closed = false
        self._nextConnectionId = 1 as Long
        self._activeConnection = null
        self._activeSession = null
        self._totalConnections = 0 as Long
        self._rejectedConnections = 0 as Long
        self._totalSessions = 0 as Long
        self._bytesRead = 0 as Long
        self._bytesWritten = 0 as Long
        self._messagesReceived = 0 as Long
        self._messagesSent = 0 as Long
        self._backpressureEvents = 0 as Long
        self._errors = 0 as Long
    }

    static Result<Server, Error> bindDefault(Context context, SocketAddress local) {
        return Server.bind(context, local, new ServiceOptions())
    }

    static Result<Server, Error> bind(Context context, SocketAddress local,
                                      ServiceOptions options) {
        if context == null || local == null || options == null {
            throw "Server.bind: null argument"
        }
        Result<TcpListener, Error> bound = TcpListener.bind(context, local)
        if bound.isErr() { return Err(bound.error()) }
        return Ok(new Server(bound.value(), options))
    }

    Result<Unit, Error> serve(Context context, SessionHandler handler) {
        if context == null || handler == null {
            throw "Server.serve: null argument"
        }
        if self._closed {
            return Err(new BasicError(ErrorKind.Unavailable, "server"))
        }
        if self._served {
            return Err(new BasicError(ErrorKind.AlreadyExists, "server already serving"))
        }
        self._served = true
        self._state = NetServiceState.Running
        while !self._closed && self._listener.isOpen() && !context.isCancelled() {
            Result<TcpStream, Error> accepted = self._listener.accept(context)
            if accepted.isErr() {
                if self._closed { break }
                if context.isCancelled() {
                    self._state = NetServiceState.Stopped
                    return Err(new BasicError(ErrorKind.Cancelled, "server cancelled"))
                }
                self._errors = self._errors + 1
                self._state = NetServiceState.Failed
                return Err(accepted.error())
            }
            TcpStream stream = accepted.value()
            Int active = 0
            if self._activeConnection != null { active = 1 }
            BackpressurePolicy backpressure = self._options.getBackpressurePolicy()
            if backpressure.shouldPauseAccept(active, 0) {
                self._rejectedConnections = self._rejectedConnections + 1
                self._backpressureEvents = self._backpressureEvents + 1
                stream.close()
                continue
            }
            Result<Unit, Error> handled = self.handleConnection(context, stream, handler)
            if handled.isErr() { return Err(handled.error()) }
        }
        if context.isCancelled() && !self._closed {
            self._state = NetServiceState.Stopped
            return Err(new BasicError(ErrorKind.Cancelled, "server cancelled"))
        }
        if self._closed {
            self._state = NetServiceState.Closed
        } else {
            self._state = NetServiceState.Stopped
        }
        return Ok()
    }

    private Result<Unit, Error> handleConnection(Context context, TcpStream stream,
                                                  SessionHandler handler) {
        Long id = self._nextConnectionId
        self._nextConnectionId = self._nextConnectionId + 1 as Long
        Connection connection = new Connection(id, stream, stream.localAddress(),
            stream.remoteAddress(), self._options.getReadBufferBytes())
        self._activeConnection = connection
        self._totalConnections = self._totalConnections + 1 as Long
        Result<Session, Error> openedSession = connection.openSession(
            self._options.getReadBufferBytes(), self._options.getHeartbeatPolicy())
        if openedSession.isErr() {
            self._errors = self._errors + 1
            connection.close()
            self._activeConnection = null
            return Ok()
        }
        Session session = openedSession.value()
        self._activeSession = session
        self._totalSessions = self._totalSessions + 1 as Long

        Result<Unit, Error> opened = handler.onOpen(context, session)
        if opened.isErr() {
            Error openError = opened.error()
            handler.onError(context, session, openError)
            session.close()
            handler.onClose(context, session, openError)
            self.finishConnection(session, false)
            self._errors = self._errors + 1
            return Err(openError)
        }

        Error? cause = null
        Bool fatal = false
        while session.isOpen() && !context.isCancelled() && !self._closed {
            HeartbeatPolicy heartbeat = self._options.getHeartbeatPolicy()
            if heartbeat.isEnabled() {
                Result<Unit, Error> deadline = session.connection().setReadDeadline(
                    nowMono() + heartbeat.getTimeoutMillis())
                if deadline.isErr() {
                    cause = deadline.error()
                    fatal = true
                    break
                }
            }
            Result<Bytes?, Error> received = session.receive(context)
            if received.isErr() {
                cause = received.error()
                fatal = true
                break
            }
            Bytes? maybe = received.value()
            if maybe == null { break }
            Bytes message = maybe as Bytes
            Result<Unit, Error> handled = handler.onMessage(context, session, message)
            if handled.isErr() {
                cause = handled.error()
                fatal = true
                break
            }
        }

        if context.isCancelled() && cause == null {
            Error cancelled = new BasicError(ErrorKind.Cancelled, "server connection cancelled")
            cause = cancelled
            fatal = true
        }
        if cause != null {
            Error actualCause = cause as Error
            handler.onError(context, session, actualCause)
        }
        session.close()
        handler.onClose(context, session, cause)
        self.finishConnection(session, cause != null)
        if fatal {
            if cause != null { return Err(cause as Error) }
            return Err(new BasicError(ErrorKind.Io, "server connection failed"))
        }
        return Ok()
    }

    private Void finishConnection(Session session, Bool failed) {
        self._bytesRead = self._bytesRead + session.bytesReceived()
        self._bytesWritten = self._bytesWritten + session.bytesSent()
        self._messagesReceived = self._messagesReceived + session.messageCount()
        self._messagesSent = self._messagesSent + session.sentMessageCount()
        if failed { self._errors = self._errors + 1 }
        self._activeSession = null
        self._activeConnection = null
    }

    SocketAddress localAddress() { return self._listener.localAddress() }
    NetServiceState state() { return self._state }
    ServiceOptions options() { return self._options.copy() }

    ServiceStats stats() {
        Int activeConnections = 0
        Int activeSessions = 0
        Long bytesRead = self._bytesRead
        Long bytesWritten = self._bytesWritten
        Long messagesReceived = self._messagesReceived
        Long messagesSent = self._messagesSent
        if self._activeConnection != null {
            Connection connection = self._activeConnection as Connection
            if connection.isOpen() { activeConnections = 1 }
        }
        if self._activeSession != null {
            Session session = self._activeSession as Session
            if session.isOpen() { activeSessions = 1 }
            bytesRead = bytesRead + session.bytesReceived()
            bytesWritten = bytesWritten + session.bytesSent()
            messagesReceived = messagesReceived + session.messageCount()
            messagesSent = messagesSent + session.sentMessageCount()
        }
        return new ServiceStats(activeConnections, self._totalConnections,
            self._rejectedConnections, activeSessions, self._totalSessions,
            bytesRead, bytesWritten, messagesReceived, messagesSent, 0 as Long,
            self._backpressureEvents, self._errors,
            nowMono() - self._startedAtMonoMillis)
    }

    Bool isOpen() {
        if self._closed { return false }
        return self._listener.isOpen()
    }

    Bool isServing() {
        if self._closed || !self._served { return false }
        return self._state == NetServiceState.Running || self._state == NetServiceState.Draining
    }

    Result<Unit, Error> close() {
        if self._closed { return Ok() }
        self._closed = true
        self._state = NetServiceState.Closed
        self._listener.close()
        if self._activeConnection != null {
            Connection connection = self._activeConnection as Connection
            connection.close()
        }
        return Ok()
    }
}

// ---------- Client ----------
class Client {
    final TcpClient _tcpClient
    final ServiceOptions _options
    final ServiceReconnectPolicy _policy
    final Long _startedAtMonoMillis
    Connection? _connection
    SocketAddress? _lastRemote
    Error? _lastError
    NetServiceState _state
    Bool _open
    Int _attempt
    Long _nextConnectionId
    Long _totalConnections
    Long _totalSessions
    Long _reconnectAttempts
    Long _errors
    Long _bytesRead
    Long _bytesWritten
    Long _messagesReceived
    Long _messagesSent

    Client(ServiceOptions options, ServiceReconnectPolicy policy) {
        if options == null || policy == null { throw "Client: null argument" }
        self._tcpClient = new TcpClient()
        self._options = options.copy()
        self._policy = policy.copy()
        self._startedAtMonoMillis = nowMono()
        self._connection = null
        self._lastRemote = null
        self._lastError = null
        self._state = NetServiceState.Created
        self._open = true
        self._attempt = 0
        self._nextConnectionId = 1 as Long
        self._totalConnections = 0 as Long
        self._totalSessions = 0 as Long
        self._reconnectAttempts = 0 as Long
        self._errors = 0 as Long
        self._bytesRead = 0 as Long
        self._bytesWritten = 0 as Long
        self._messagesReceived = 0 as Long
        self._messagesSent = 0 as Long
    }

    Result<Connection, Error> connect(Context context, SocketAddress remote,
                                      SessionHandler handler) {
        if context == null || remote == null || handler == null {
            throw "Client.connect: null argument"
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "client"))
        }
        if self._connection != null {
            Connection current = self._connection as Connection
            if current.isOpen() {
                return Err(new BasicError(ErrorKind.Busy, "client already connected"))
            }
        }
        self._lastRemote = remote
        self._connection = null
        Bool firstConnect = true
        while self._open && !context.isCancelled() {
            self._state = NetServiceState.Starting
            Result<TcpStream, Error> connected = self._tcpClient.connect(context, remote)
            if connected.isErr() {
                Error connectError = connected.error()
                self._lastError = connectError
                self._errors = self._errors + 1
                if !self._open { break }
                if !self._policy.shouldRetryError(self._attempt, connectError) {
                    self._state = NetServiceState.Stopped
                    return Err(connectError)
                }
                Long delay = self._policy.delayMillis(self._attempt)
                self._attempt = self._attempt + 1
                self._reconnectAttempts = self._reconnectAttempts + 1 as Long
                Result<Unit, Error> slept = sleepContext(context, durationOfMillis(delay))
                if slept.isErr() {
                    self._state = NetServiceState.Stopped
                    return Err(slept.error())
                }
                continue
            }
            TcpStream stream = connected.value()
            Long id = self._nextConnectionId
            self._nextConnectionId = self._nextConnectionId + 1 as Long
            Connection connection = new Connection(id, stream, stream.localAddress(),
                stream.remoteAddress(), self._options.getReadBufferBytes())
            self._connection = connection
            self._totalConnections = self._totalConnections + 1 as Long
            if firstConnect {
                self._attempt = 0
                firstConnect = false
            }
            self._lastError = null
            self._state = NetServiceState.Running
            Result<Session, Error> openedSession = connection.openSession(
                self._options.getReadBufferBytes(), self._options.getHeartbeatPolicy())
            if openedSession.isErr() {
                self._errors = self._errors + 1
                connection.close()
                self._connection = null
                self._state = NetServiceState.Stopped
                return Err(openedSession.error())
            }
            Session session = openedSession.value()
            self._totalSessions = self._totalSessions + 1 as Long
            Result<Unit, Error> opened = handler.onOpen(context, session)
            if opened.isErr() {
                Error openError = opened.error()
                handler.onError(context, session, openError)
                session.close()
                handler.onClose(context, session, openError)
                self._bytesRead = self._bytesRead + session.bytesReceived()
                self._bytesWritten = self._bytesWritten + session.bytesSent()
                self._messagesReceived = self._messagesReceived + session.messageCount()
                self._messagesSent = self._messagesSent + session.sentMessageCount()
                self._connection = null
                self._errors = self._errors + 1
                self._state = NetServiceState.Stopped
                return Err(openError)
            }
            Error? cause = null
            Bool fatal = false
            while session.isOpen() && !context.isCancelled() && self._open {
                HeartbeatPolicy heartbeat = self._options.getHeartbeatPolicy()
                if heartbeat.isEnabled() {
                    Result<Unit, Error> deadline = session.connection().setReadDeadline(
                        nowMono() + heartbeat.getTimeoutMillis())
                    if deadline.isErr() {
                        cause = deadline.error()
                        fatal = true
                        break
                    }
                }
                Result<Bytes?, Error> received = session.receive(context)
                if received.isErr() {
                    cause = received.error()
                    fatal = true
                    break
                }
                Bytes? maybe = received.value()
                if maybe == null { break }
                Bytes message = maybe as Bytes
                Result<Unit, Error> handled = handler.onMessage(context, session, message)
                if handled.isErr() {
                    cause = handled.error()
                    fatal = true
                    break
                }
            }
            if context.isCancelled() && cause == null {
                Error cancelled = new BasicError(ErrorKind.Cancelled, "client cancelled")
                cause = cancelled
                fatal = true
            }
            if cause != null {
                Error actualCause = cause as Error
                handler.onError(context, session, actualCause)
            }
            session.close()
            handler.onClose(context, session, cause)
            self._bytesRead = self._bytesRead + session.bytesReceived()
            self._bytesWritten = self._bytesWritten + session.bytesSent()
            self._messagesReceived = self._messagesReceived + session.messageCount()
            self._messagesSent = self._messagesSent + session.sentMessageCount()
            self._connection = null
            if !self._open {
                self._state = NetServiceState.Closed
                return Ok()
            }
            if fatal {
                self._errors = self._errors + 1
                if cause != null {
                    self._lastError = cause as Error
                    if self._policy.shouldRetryError(self._attempt, cause as Error) {
                        Long delay = self._policy.delayMillis(self._attempt)
                        self._attempt = self._attempt + 1
                        self._reconnectAttempts = self._reconnectAttempts + 1 as Long
                        Result<Unit, Error> slept = sleepContext(context,
                            durationOfMillis(delay))
                        if slept.isErr() {
                            self._state = NetServiceState.Stopped
                            return Err(slept.error())
                        }
                        continue
                    }
                    self._state = NetServiceState.Stopped
                    return Err(cause as Error)
                }
            }
            if self._policy.shouldRetry(self._attempt) {
                Long delay = self._policy.delayMillis(self._attempt)
                self._attempt = self._attempt + 1
                self._reconnectAttempts = self._reconnectAttempts + 1 as Long
                Result<Unit, Error> slept = sleepContext(context, durationOfMillis(delay))
                if slept.isErr() {
                    self._state = NetServiceState.Stopped
                    return Err(slept.error())
                }
                continue
            }
            self._state = NetServiceState.Stopped
            Error closedError = new BasicError(ErrorKind.Network, "client connection closed")
            self._lastError = closedError
            return Err(closedError)
        }
        if !self._open {
            self._state = NetServiceState.Closed
            return Ok()
        }
        self._state = NetServiceState.Stopped
        return Err(new BasicError(ErrorKind.Cancelled, "client cancelled"))
    }

    Connection? connection() { return self._connection }
    Int attempt() { return self._attempt }
    Error? lastError() { return self._lastError }
    ServiceReconnectPolicy reconnectPolicy() { return self._policy.copy() }
    ServiceOptions options() { return self._options.copy() }

    NetServiceState state() {
        if self._state == NetServiceState.Running && self._connection != null {
            Connection current = self._connection as Connection
            if !current.isOpen() { return NetServiceState.Stopped }
        }
        return self._state
    }

    Bool isOpen() { return self._open }

    Result<Session, Error> openSession(Int readBufferBytes,
                                       HeartbeatPolicy heartbeatPolicy) {
        if heartbeatPolicy == null {
            throw "Client.openSession: null heartbeat policy"
        }
        if self._connection == null {
            return Err(new BasicError(ErrorKind.Unavailable, "client connection"))
        }
        Connection current = self._connection as Connection
        if !current.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "client connection"))
        }
        Bool hadSession = current.hasSession()
        Result<Session, Error> result = current.openSession(readBufferBytes, heartbeatPolicy)
        if result.isOk() && !hadSession {
            self._totalSessions = self._totalSessions + 1 as Long
        }
        return result
    }

    Result<Session, Error> openDefaultSession() {
        return self.openSession(self._options.getReadBufferBytes(),
            self._options.getHeartbeatPolicy())
    }

    ServiceStats stats() {
        Int activeConnections = 0
        Int activeSessions = 0
        Long bytesRead = self._bytesRead
        Long bytesWritten = self._bytesWritten
        Long messagesReceived = self._messagesReceived
        Long messagesSent = self._messagesSent
        if self._connection != null {
            Connection connection = self._connection as Connection
            if connection.isOpen() { activeConnections = 1 }
            bytesRead = bytesRead + connection.readBytes()
            bytesWritten = bytesWritten + connection.writtenBytes()
            Session? session = connection.session()
            if session != null {
                Session actual = session as Session
                if actual.isOpen() { activeSessions = 1 }
                messagesReceived = messagesReceived + actual.messageCount()
                messagesSent = messagesSent + actual.sentMessageCount()
            }
        }
        return new ServiceStats(activeConnections, self._totalConnections, 0 as Long,
            activeSessions, self._totalSessions, bytesRead, bytesWritten,
            messagesReceived, messagesSent, self._reconnectAttempts, 0 as Long,
            self._errors, nowMono() - self._startedAtMonoMillis)
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        self._state = NetServiceState.Closed
        if self._connection == null { return Ok() }
        Connection connection = self._connection as Connection
        return connection.close()
    }
}

// ---------- NetworkService ----------
class NetworkService {
    final ServiceOptions _options
    final Long _startedAtMonoMillis
    TaskGroup? _group
    Server? _server
    Client? _client
    NetServiceState _state
    Bool _open
    Bool _started
    Long _errors

    NetworkService(ServiceOptions options) {
        if options == null { throw "NetworkService: null options" }
        self._options = options.copy()
        self._startedAtMonoMillis = nowMono()
        self._group = null
        self._server = null
        self._client = null
        self._state = NetServiceState.Created
        self._open = true
        self._started = false
        self._errors = 0 as Long
    }

    Result<Server, Error> startServer(Context context, SocketAddress local,
                                      SessionHandler handler) {
        if context == null || local == null || handler == null {
            throw "NetworkService.startServer: null argument"
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "network service"))
        }
        if self._started {
            return Err(new BasicError(ErrorKind.AlreadyExists, "network service already started"))
        }
        Result<Server, Error> bound = Server.bind(context, local, self._options)
        if bound.isErr() { return Err(bound.error()) }
        Server server = bound.value()
        TaskGroup group = TaskGroup.create(Context.withCancel(context))
        self._group = group
        self._server = server
        self._started = true
        self._state = NetServiceState.Starting
        Task<Int> task = group.spawn((Context taskContext) -> {
            Result<Unit, Error> served = server.serve(taskContext, handler)
            if served.isErr() { return Ok(1) }
            return Ok(0)
        })
        self._state = NetServiceState.Running
        return Ok(server)
    }

    Result<Client, Error> startClient(Context context, SocketAddress remote,
                                      SessionHandler handler) {
        return self.startClientWithPolicy(context, remote, handler,
            self._options.getReconnectPolicy())
    }

    Result<Client, Error> startClientWithPolicy(Context context, SocketAddress remote,
                                                SessionHandler handler,
                                                ServiceReconnectPolicy policy) {
        if context == null || remote == null || handler == null || policy == null {
            throw "NetworkService.startClient: null argument"
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "network service"))
        }
        if self._started {
            return Err(new BasicError(ErrorKind.AlreadyExists, "network service already started"))
        }
        Client client = new Client(self._options, policy)
        TaskGroup group = TaskGroup.create(Context.withCancel(context))
        self._group = group
        self._client = client
        self._started = true
        self._state = NetServiceState.Starting
        Task<Int> task = group.spawn((Context taskContext) -> {
            Result<Connection, Error> connected = client.connect(taskContext, remote, handler)
            if connected.isErr() { return Ok(1) }
            return Ok(0)
        })
        self._state = NetServiceState.Running
        return Ok(client)
    }

    Server? server() { return self._server }
    Client? client() { return self._client }
    NetServiceState state() { return self._state }
    ServiceOptions options() { return self._options.copy() }

    ServiceStats stats() {
        if self._server != null {
            Server server = self._server as Server
            return server.stats()
        }
        if self._client != null {
            Client client = self._client as Client
            return client.stats()
        }
        return new ServiceStats(0, 0 as Long, 0 as Long, 0, 0 as Long,
            0 as Long, 0 as Long, 0 as Long, 0 as Long, 0 as Long, 0 as Long,
            0 as Long, nowMono() - self._startedAtMonoMillis)
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "NetworkService.stop: null context" }
        if self._state == NetServiceState.Closed || self._state == NetServiceState.Stopped {
            return Ok()
        }
        self._state = NetServiceState.Draining
        if self._server != null {
            Server server = self._server as Server
            server.close()
        }
        if self._client != null {
            Client client = self._client as Client
            client.close()
        }
        if self._group != null {
            TaskGroup group = self._group as TaskGroup
            group.close()
        }
        self._group = null
        self._state = NetServiceState.Stopped
        return Ok()
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self.stop(Context.background())
        self._open = false
        self._state = NetServiceState.Closed
        return Ok()
    }
}
