// xdk.queue —— 有界/批量/延迟队列（M21.1）
//
// 实现 DropPolicy/QueueStats/BoundedQueue/BatchQueue/DelayQueue。
// 不做无界队列、持久化、优先级；DelayQueue 用监视器等待，非忙等。
// 稳定性：preview。合同见 docs/design/utils/queue/。
package xdk.queue
import xdk.errors
import xdk.runtime
import xdk.time

// ---------- DropPolicy ----------
enum DropPolicy {
    Error,
    DropNewest,
    DropOldest,
}

String dropPolicyName(DropPolicy policy) {
    if policy == DropPolicy.Error { return "error" }
    if policy == DropPolicy.DropNewest { return "drop_newest" }
    return "drop_oldest"
}

DropPolicy? parseDropPolicy(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "error" { return DropPolicy.Error }
    if normalized == "drop_newest" || normalized == "drop-newest" {
        return DropPolicy.DropNewest
    }
    if normalized == "drop_oldest" || normalized == "drop-oldest" {
        return DropPolicy.DropOldest
    }
    return null
}

// ---------- QueueStats ----------
class QueueStats {
    final Int _size
    final Long _pushed
    final Long _popped
    final Long _dropped
    final Long _rejected
    final Bool _closed

    QueueStats(Int size, Long pushed, Long popped, Long dropped,
               Long rejected, Bool closed) {
        if size < 0 || pushed < 0 as Long || popped < 0 as Long ||
            dropped < 0 as Long || rejected < 0 as Long {
            throw "QueueStats: negative value"
        }
        self._size = size
        self._pushed = pushed
        self._popped = popped
        self._dropped = dropped
        self._rejected = rejected
        self._closed = closed
    }

    Int size() { return self._size }
    Long pushed() { return self._pushed }
    Long popped() { return self._popped }
    Long dropped() { return self._dropped }
    Long rejected() { return self._rejected }
    Bool isClosed() { return self._closed }

    String describe() {
        return "QueueStats(size=" + str(self._size) + ", pushed=" + str(self._pushed) +
            ", popped=" + str(self._popped) + ", dropped=" + str(self._dropped) +
            ", rejected=" + str(self._rejected) + ", closed=" + str(self._closed) + ")"
    }

    String toString() { return self.describe() }

    Bool equals(QueueStats other) {
        if other == null { return false }
        return self._size == other.size() &&
            self._pushed == other.pushed() &&
            self._popped == other.popped() &&
            self._dropped == other.dropped() &&
            self._rejected == other.rejected() &&
            self._closed == other.isClosed()
    }

    QueueStats copy() {
        return new QueueStats(self._size, self._pushed, self._popped,
            self._dropped, self._rejected, self._closed)
    }
}

// ---------- BoundedQueue ----------
class BoundedQueue<T> {
    final Int _capacity
    final DropPolicy _policy
    final RuntimeMonitor _monitor
    final List<T> _items
    Bool _closed
    Long _pushed
    Long _popped
    Long _dropped
    Long _rejected

    BoundedQueue(Int capacity, DropPolicy policy) {
        if capacity < 1 { throw "BoundedQueue: capacity < 1" }
        self._capacity = capacity
        self._policy = policy
        self._monitor = new RuntimeMonitor()
        self._items = []
        self._closed = false
        self._pushed = 0 as Long
        self._popped = 0 as Long
        self._dropped = 0 as Long
        self._rejected = 0 as Long
    }

    Bool push(T value) {
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return false
        }
        if self._items.length() < self._capacity {
            self._items.push(value)
            self._pushed = self._pushed + 1 as Long
            self._monitor.notifyAll()
            self._monitor.exit()
            return true
        }
        if self._policy == DropPolicy.Error {
            self._rejected = self._rejected + 1 as Long
            self._monitor.exit()
            return false
        }
        if self._policy == DropPolicy.DropNewest {
            self._dropped = self._dropped + 1 as Long
            self._monitor.exit()
            return false
        }
        self._items.remove(0)
        self._dropped = self._dropped + 1 as Long
        self._items.push(value)
        self._pushed = self._pushed + 1 as Long
        self._monitor.notifyAll()
        self._monitor.exit()
        return true
    }

    T? pop() {
        self._monitor.enter()
        if self._items.length() == 0 {
            self._monitor.exit()
            return null
        }
        T value = self._items.get(0)
        self._items.remove(0)
        self._popped = self._popped + 1 as Long
        self._monitor.exit()
        return value
    }

    T? peek() {
        self._monitor.enter()
        if self._items.length() == 0 {
            self._monitor.exit()
            return null
        }
        T value = self._items.get(0)
        self._monitor.exit()
        return value
    }

    Int size() {
        self._monitor.enter()
        Int result = self._items.length()
        self._monitor.exit()
        return result
    }

    Int capacity() { return self._capacity }

    Bool isEmpty() {
        self._monitor.enter()
        Bool result = self._items.length() == 0
        self._monitor.exit()
        return result
    }

    Bool isFull() {
        self._monitor.enter()
        Bool result = !self._closed && self._items.length() >= self._capacity
        self._monitor.exit()
        return result
    }

    Void clear() {
        self._monitor.enter()
        self._dropped = self._dropped + (self._items.length() as Long)
        self._items.clear()
        self._monitor.exit()
    }

    Void close() {
        self._monitor.enter()
        if !self._closed {
            self._closed = true
            self._dropped = self._dropped + (self._items.length() as Long)
            self._items.clear()
        }
        self._monitor.notifyAll()
        self._monitor.exit()
    }

    Bool isClosed() {
        self._monitor.enter()
        Bool result = self._closed
        self._monitor.exit()
        return result
    }

    QueueStats stats() {
        self._monitor.enter()
        QueueStats result = new QueueStats(self._items.length(), self._pushed,
            self._popped, self._dropped, self._rejected, self._closed)
        self._monitor.exit()
        return result
    }
}

// ---------- BatchQueue ----------
class BatchQueue<T> {
    final Int _batchSize
    final RuntimeMonitor _monitor
    final List<T> _items
    Bool _closed

    BatchQueue(Int batchSize) {
        if batchSize < 1 { throw "BatchQueue: batchSize < 1" }
        self._batchSize = batchSize
        self._monitor = new RuntimeMonitor()
        self._items = []
        self._closed = false
    }

    Bool add(T value) {
        self._monitor.enter()
        if self._closed || self._items.length() >= self._batchSize {
            self._monitor.exit()
            return false
        }
        self._items.push(value)
        self._monitor.exit()
        return true
    }

    Bool isFull() {
        self._monitor.enter()
        Bool result = !self._closed && self._items.length() >= self._batchSize
        self._monitor.exit()
        return result
    }

    List<T> flush() {
        self._monitor.enter()
        List<T> result = self._items.copy()
        self._items.clear()
        self._monitor.exit()
        return result
    }

    List<T> peek() {
        self._monitor.enter()
        List<T> result = self._items.copy()
        self._monitor.exit()
        return result
    }

    Int size() {
        self._monitor.enter()
        Int result = self._items.length()
        self._monitor.exit()
        return result
    }

    Int batchSize() { return self._batchSize }

    Void clear() {
        self._monitor.enter()
        self._items.clear()
        self._monitor.exit()
    }

    Void close() {
        self._monitor.enter()
        if !self._closed {
            self._closed = true
            self._items.clear()
        }
        self._monitor.exit()
    }

    Bool isClosed() {
        self._monitor.enter()
        Bool result = self._closed
        self._monitor.exit()
        return result
    }
}

// ---------- DelayQueue ----------
class DelayQueue<T> {
    final List<T> _values
    final List<Long> _readyAt
    final RuntimeMonitor _monitor
    Bool _closed
    Long _pushed
    Long _popped
    Long _dropped

    DelayQueue() {
        self._values = []
        self._readyAt = []
        self._monitor = new RuntimeMonitor()
        self._closed = false
        self._pushed = 0 as Long
        self._popped = 0 as Long
        self._dropped = 0 as Long
    }

    Bool put(T value, Long delayMillis) {
        if delayMillis < 0 as Long {
            throw "DelayQueue.put: negative delay"
        }
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return false
        }
        Long ready = nowMono() + delayMillis
        Int position = 0
        while position < self._readyAt.length() &&
            self._readyAt.get(position) <= ready {
            position = position + 1
        }
        self._values.insert(position, value)
        self._readyAt.insert(position, ready)
        self._pushed = self._pushed + 1 as Long
        self._monitor.notifyAll()
        self._monitor.exit()
        return true
    }

    Result<T, Error> take(Context context) {
        if context == null { throw "DelayQueue.take: null context" }
        self._monitor.enter()
        while true {
            if context.isCancelled() {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "delay queue take"))
            }
            if self._closed {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Unavailable, "delay queue is closed"))
            }
            if self._values.length() == 0 {
                Bool woke = self._monitor.waitContext(context)
                if !woke {
                    self._monitor.exit()
                    return Err(new BasicError(ErrorKind.Cancelled, "delay queue take"))
                }
                continue
            }
            Int index = self.earliestIndex()
            Long ready = self._readyAt.get(index)
            if ready <= nowMono() {
                T value = self._values.get(index)
                self._values.remove(index)
                self._readyAt.remove(index)
                self._popped = self._popped + 1 as Long
                self._monitor.notifyAll()
                self._monitor.exit()
                return Ok(value)
            }
            Int state = self._monitor.waitDeadline(context, ready)
            if state == 0 {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "delay queue take"))
            }
        }
    }

    T? tryTake() {
        self._monitor.enter()
        if self._values.length() == 0 {
            self._monitor.exit()
            return null
        }
        Int index = self.earliestIndex()
        if self._readyAt.get(index) > nowMono() {
            self._monitor.exit()
            return null
        }
        T value = self._values.get(index)
        self._values.remove(index)
        self._readyAt.remove(index)
        self._popped = self._popped + 1 as Long
        self._monitor.notifyAll()
        self._monitor.exit()
        return value
    }

    Long? nextReadyAt() {
        self._monitor.enter()
        if self._values.length() == 0 {
            self._monitor.exit()
            return null
        }
        Int index = self.earliestIndex()
        Long value = self._readyAt.get(index)
        self._monitor.exit()
        return value
    }

    Int size() {
        self._monitor.enter()
        Int result = self._values.length()
        self._monitor.exit()
        return result
    }

    Bool isEmpty() {
        self._monitor.enter()
        Bool result = self._values.length() == 0
        self._monitor.exit()
        return result
    }

    Void clear() {
        self._monitor.enter()
        self._dropped = self._dropped + (self._values.length() as Long)
        self._values.clear()
        self._readyAt.clear()
        self._monitor.exit()
    }

    Void close() {
        self._monitor.enter()
        if !self._closed {
            self._closed = true
            self._dropped = self._dropped + (self._values.length() as Long)
            self._values.clear()
            self._readyAt.clear()
        }
        self._monitor.notifyAll()
        self._monitor.exit()
    }

    Bool isClosed() {
        self._monitor.enter()
        Bool result = self._closed
        self._monitor.exit()
        return result
    }

    QueueStats stats() {
        self._monitor.enter()
        QueueStats result = new QueueStats(self._values.length(), self._pushed,
            self._popped, self._dropped, 0 as Long, self._closed)
        self._monitor.exit()
        return result
    }

    private Int earliestIndex() {
        Int index = 0
        Int scan = 1
        while scan < self._readyAt.length() {
            if self._readyAt.get(scan) < self._readyAt.get(index) {
                index = scan
            }
            scan = scan + 1
        }
        return index
    }
}
