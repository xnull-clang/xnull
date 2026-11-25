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
