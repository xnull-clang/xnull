#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.service
import xdk.net.service
import xdk.net
import xdk.errors
import xdk.bytes

class NullStream implements ByteStream {
    Result<Int, Error> read(Context context, Bytes buffer) { return Ok(0) }
    Result<Int, Error> write(Context context, Bytes data) { return Ok(data.length()) }
    Result<Unit, Error> writeAll(Context context, Bytes data) { return Ok() }
    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis) { return Ok() }
    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis) { return Ok() }
    Bool isOpen() { return true }
    Void close() { }
}

static SocketAddress panicAddress() {
    return SocketAddress.parse("127.0.0.1:1").value()
}

static Connection panicConnection() {
    return new Connection(0 as Long, new NullStream(), panicAddress(), panicAddress(), 1024)
}

static Int main(String[] args) {
    String name = args.get(0)
    if name == "optionsMaxConnections" {
        ServiceOptions options = new ServiceOptions()
        options.maxConnections(0)
    } else if name == "optionsAcceptQueue" {
        ServiceOptions options = new ServiceOptions()
        options.acceptQueueCapacity(-1)
    } else if name == "optionsAcceptBackoff" {
        ServiceOptions options = new ServiceOptions()
        options.acceptBackoffMillis(-1 as Long)
    } else if name == "optionsReadBufferSmall" {
        ServiceOptions options = new ServiceOptions()
        options.readBufferBytes(512)
    } else if name == "optionsReadBufferLarge" {
        ServiceOptions options = new ServiceOptions()
        options.readBufferBytes(1048577)
    } else if name == "optionsIdle" {
        ServiceOptions options = new ServiceOptions()
        options.idleTimeoutMillis(-1 as Long)
    } else if name == "optionsReadTimeout" {
        ServiceOptions options = new ServiceOptions()
        options.readTimeoutMillis(-1 as Long)
    } else if name == "optionsWriteTimeout" {
        ServiceOptions options = new ServiceOptions()
        options.writeTimeoutMillis(-1 as Long)
    } else if name == "optionsGraceful" {
        ServiceOptions options = new ServiceOptions()
        options.gracefulShutdownTimeoutMillis(-1 as Long)
    } else if name == "optionsBackpressure" {
        ServiceOptions options = new ServiceOptions()
        options.backpressurePolicy(null)
    } else if name == "optionsHeartbeat" {
        ServiceOptions options = new ServiceOptions()
        options.heartbeatPolicy(null)
    } else if name == "optionsReconnect" {
        ServiceOptions options = new ServiceOptions()
        options.reconnectPolicy(null)
    } else if name == "heartbeatInterval" {
        HeartbeatPolicy policy = new HeartbeatPolicy()
        policy.intervalMillis(40000 as Long)
    } else if name == "heartbeatTimeout" {
        HeartbeatPolicy policy = new HeartbeatPolicy()
        policy.timeoutMillis(0 as Long)
    } else if name == "heartbeatDeadline" {
        HeartbeatPolicy policy = new HeartbeatPolicy()
        Long value = policy.deadlineFrom(-1 as Long)
    } else if name == "heartbeatExpired" {
        HeartbeatPolicy policy = new HeartbeatPolicy()
        Bool value = policy.isExpired(-1 as Long, 0 as Long)
    } else if name == "bpAcceptLow" {
        BackpressurePolicy policy = new BackpressurePolicy()
        policy.acceptHighWaterConnections(10)
        policy.acceptLowWaterConnections(20)
    } else if name == "bpLowWithoutHigh" {
        BackpressurePolicy policy = new BackpressurePolicy()
        policy.acceptLowWaterConnections(1)
    } else if name == "bpPendingHigh" {
        BackpressurePolicy policy = new BackpressurePolicy()
        policy.pendingAcceptHighWater(10)
        policy.pendingAcceptLowWater(20)
    } else if name == "bpReadHigh" {
        BackpressurePolicy policy = new BackpressurePolicy()
        policy.readHighWaterBytes(1000 as Long)
    } else if name == "bpReadLow" {
        BackpressurePolicy policy = new BackpressurePolicy()
        policy.readLowWaterBytes(2000000 as Long)
    } else if name == "bpPauseAccept" {
        BackpressurePolicy policy = new BackpressurePolicy()
        Bool value = policy.shouldPauseAccept(-1, 0)
    } else if name == "bpPauseReads" {
        BackpressurePolicy policy = new BackpressurePolicy()
        Bool value = policy.shouldPauseReads(-1 as Long)
    } else if name == "reconnectInitial" {
        ServiceReconnectPolicy policy = new ServiceReconnectPolicy()
        policy.initialDelayMillis(40000 as Long)
    } else if name == "reconnectMax" {
        ServiceReconnectPolicy policy = new ServiceReconnectPolicy()
        policy.maxDelayMillis(1 as Long)
    } else if name == "reconnectMultiplier" {
        ServiceReconnectPolicy policy = new ServiceReconnectPolicy()
        policy.multiplier(0.5)
    } else if name == "reconnectAttempts" {
        ServiceReconnectPolicy policy = new ServiceReconnectPolicy()
        policy.maxAttempts(-1)
    } else if name == "reconnectShouldRetry" {
        ServiceReconnectPolicy policy = new ServiceReconnectPolicy()
        Bool value = policy.shouldRetry(-1)
    } else if name == "reconnectDelay" {
        ServiceReconnectPolicy policy = new ServiceReconnectPolicy()
        Long value = policy.delayMillis(-1)
    } else if name == "reconnectNullError" {
        ServiceReconnectPolicy policy = new ServiceReconnectPolicy()
        Bool value = policy.shouldRetryError(0, null)
    } else if name == "statsNegative" {
        ServiceStats stats = new ServiceStats(0, 0 as Long, 0 as Long, 0, 0 as Long,
            0 as Long, 0 as Long, 0 as Long, 0 as Long, 0 as Long, 0 as Long,
            0 as Long, -1 as Long)
    } else if name == "connectionNullStream" {
        Connection connection = new Connection(0 as Long, null, panicAddress(),
            panicAddress(), 1024)
    } else if name == "connectionNegativeId" {
        Connection connection = new Connection(-1 as Long, new NullStream(),
            panicAddress(), panicAddress(), 1024)
    } else if name == "connectionZeroBuffer" {
        Connection connection = new Connection(0 as Long, new NullStream(),
            panicAddress(), panicAddress(), 0)
    } else if name == "connectionReadNull" {
        Connection connection = panicConnection()
        Result<Int, Error> value = connection.read(Context.background(), null)
    } else if name == "connectionSessionBuffer" {
        Connection connection = panicConnection()
        Result<Session, Error> value = connection.openSession(0, new HeartbeatPolicy())
    } else if name == "connectionSessionHeartbeat" {
        Connection connection = panicConnection()
        Result<Session, Error> value = connection.openSession(1024, null)
    } else if name == "sessionNullConnection" {
        Session session = new Session(0 as Long, null, 1024, new HeartbeatPolicy())
    } else if name == "sessionNegativeId" {
        Session session = new Session(-1 as Long, panicConnection(), 1024,
            new HeartbeatPolicy())
    } else if name == "sessionZeroBuffer" {
        Session session = new Session(0 as Long, panicConnection(), 0,
            new HeartbeatPolicy())
    } else if name == "sessionEmptyAttribute" {
        Session session = new Session(0 as Long, panicConnection(), 1024,
            new HeartbeatPolicy())
        String? value = session.attribute("")
    } else if name == "sessionNullValue" {
        Session session = new Session(0 as Long, panicConnection(), 1024,
            new HeartbeatPolicy())
        session.setAttribute("k", null)
    } else if name == "sessionNegativeIdle" {
        Session session = new Session(0 as Long, panicConnection(), 1024,
            new HeartbeatPolicy())
        Bool value = session.isIdle(-1 as Long)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "service panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "service panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic optionsMaxConnections "ServiceOptions.maxConnections: invalid"
check_panic optionsAcceptQueue "ServiceOptions.acceptQueueCapacity: negative"
check_panic optionsAcceptBackoff "ServiceOptions.acceptBackoffMillis: negative"
check_panic optionsReadBufferSmall "ServiceOptions.readBufferBytes: too small"
check_panic optionsReadBufferLarge "ServiceOptions.readBufferBytes: too large"
check_panic optionsIdle "ServiceOptions.idleTimeoutMillis: negative"
check_panic optionsReadTimeout "ServiceOptions.readTimeoutMillis: negative"
check_panic optionsWriteTimeout "ServiceOptions.writeTimeoutMillis: negative"
check_panic optionsGraceful "ServiceOptions.gracefulShutdownTimeoutMillis: negative"
check_panic optionsBackpressure "ServiceOptions.backpressurePolicy: null"
check_panic optionsHeartbeat "ServiceOptions.heartbeatPolicy: null"
check_panic optionsReconnect "ServiceOptions.reconnectPolicy: null"
check_panic heartbeatInterval "HeartbeatPolicy.intervalMillis: exceeds timeout"
check_panic heartbeatTimeout "HeartbeatPolicy.timeoutMillis: invalid"
check_panic heartbeatDeadline "HeartbeatPolicy.deadlineFrom: negative"
check_panic heartbeatExpired "HeartbeatPolicy.isExpired: negative"
check_panic bpAcceptLow "BackpressurePolicy.acceptLowWaterConnections: not below high"
check_panic bpLowWithoutHigh "BackpressurePolicy.acceptLowWaterConnections: high disabled"
check_panic bpPendingHigh "BackpressurePolicy.pendingAcceptLowWater: not below high"
check_panic bpReadHigh "BackpressurePolicy.readHighWaterBytes: below low"
check_panic bpReadLow "BackpressurePolicy.readLowWaterBytes: not below high"
check_panic bpPauseAccept "BackpressurePolicy.shouldPauseAccept: negative"
check_panic bpPauseReads "BackpressurePolicy.shouldPauseReads: negative"
check_panic reconnectInitial "ServiceReconnectPolicy.initialDelayMillis: exceeds max"
check_panic reconnectMax "ServiceReconnectPolicy.maxDelayMillis: below initial"
check_panic reconnectMultiplier "ServiceReconnectPolicy.multiplier: below one"
check_panic reconnectAttempts "ServiceReconnectPolicy.maxAttempts: negative"
check_panic reconnectShouldRetry "ServiceReconnectPolicy.shouldRetry: negative"
check_panic reconnectDelay "ServiceReconnectPolicy.delayMillis: negative"
check_panic reconnectNullError "ServiceReconnectPolicy.shouldRetry: null error"
check_panic statsNegative "ServiceStats: negative value"
check_panic connectionNullStream "Connection: null argument"
check_panic connectionNegativeId "Connection: negative id"
check_panic connectionZeroBuffer "Connection: invalid buffer"
check_panic connectionReadNull "Connection.read: null argument"
check_panic connectionSessionBuffer "Connection.openSession: invalid buffer"
check_panic connectionSessionHeartbeat "Connection.openSession: null heartbeat policy"
check_panic sessionNullConnection "Session: null argument"
check_panic sessionNegativeId "Session: negative id"
check_panic sessionZeroBuffer "Session: invalid buffer"
check_panic sessionEmptyAttribute "Session.attribute: empty name"
check_panic sessionNullValue "Session.setAttribute: null value"
check_panic sessionNegativeIdle "Session.isIdle: negative"
echo "service_panic: PASS"
