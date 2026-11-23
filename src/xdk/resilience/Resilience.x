package xdk.resilience
import xdk.errors
import xdk.runtime
import xdk.tasks
import xdk.time

enum CircuitState {
    Closed,
    Open,
    HalfOpen,
}

String circuitStateName(CircuitState state) {
    if state == CircuitState.Closed { return "closed" }
    if state == CircuitState.Open { return "open" }
    return "half_open"
}

static Error resilienceError(ErrorKind kind, String message) {
    return new BasicError(kind, message)
}

static Bool resilienceCancelled(Error error) {
    return error.kind() == ErrorKind.Cancelled
}
