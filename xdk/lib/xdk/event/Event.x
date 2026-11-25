// xdk.event —— 进程内同步事件总线（M21.3）
//
// 实现 Event/EventBus/EventSubscription；同步投递、锁外回调、首错短路。
// 不做异步队列、持久化、通配符、跨进程。
package xdk.event
import xdk.errors
import xdk.codec
import xdk.runtime

// ---------- Event ----------
class Event {
    final String _id
    final String _topic
    final JsonValue _payload
    final Long _timestampMono
    final String? _source

    Event(String eventId, String topic, JsonValue payload,
          Long timestampMono, String? source) {
        if eventId == null || topic == null || payload == null {
            throw "Event: null argument"
        }
        if eventId.trim() == "" { throw "Event: empty id" }
        if topic.trim() == "" { throw "Event: empty topic" }
        if timestampMono < 0 as Long { throw "Event: negative timestamp" }
        self._id = eventId
        self._topic = topic
        self._payload = payload
        self._timestampMono = timestampMono
        self._source = source
    }

    static Event now(String eventId, String topic, JsonValue payload, String? source) {
        return new Event(eventId, topic, payload, nowMono(), source)
    }

    String id() { return self._id }
    String topic() { return self._topic }
    JsonValue payload() { return self._payload }
    Long timestampMono() { return self._timestampMono }
    String? source() { return self._source }

    String describe() {
        String sourceText = "none"
        if self._source != null { sourceText = self._source as String }
        return "event " + self._id + " topic=" + self._topic +
            " at=" + str(self._timestampMono) + " source=" + sourceText +
            " payload=" + jsonKindName(self._payload.kind())
    }
}

// ---------- EventSubscription ----------
class EventSubscription {
    final EventBus _bus
    final String _id
    final String _topic
    Bool _cancelled

    EventSubscription(EventBus bus, String subscriptionId, String topic) {
        if bus == null || subscriptionId == null || topic == null {
            throw "EventSubscription: null argument"
        }
        self._bus = bus
        self._id = subscriptionId
        self._topic = topic
        self._cancelled = false
    }

    String id() { return self._id }
    String topic() { return self._topic }

    Bool cancel() {
        return self._bus.unsubscribe(self)
    }

    Bool isActive() {
        if self._cancelled { return false }
        return self._bus.isSubscribed(self)
    }

    Void markCancelled() { self._cancelled = true }
}

// ---------- handler slot ----------
class EventHandlerSlot {
    final Result<Unit, Error>(Event) _handler

    EventHandlerSlot(Result<Unit, Error>(Event) handler) {
        self._handler = handler
    }

    Result<Unit, Error> run(Event event) {
        return self._handler(event)
    }
}

// ---------- EventBus ----------
class EventBus {
    final RuntimeMonitor _monitor
    final List<EventSubscription> _subscriptions
    final List<String> _topics
    final List<EventHandlerSlot> _handlers
    Long _nextSubscriptionId
    Bool _closed

    EventBus() {
        self._monitor = new RuntimeMonitor()
        self._subscriptions = []
        self._topics = []
        self._handlers = []
        self._nextSubscriptionId = 1 as Long
        self._closed = false
    }

    Result<EventSubscription, Error> subscribe(String topic,
            Result<Unit, Error>(Event) handler) {
        if topic == null {
            throw "EventBus.subscribe: null topic"
        }
        if topic.trim() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "event topic is blank"))
        }
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "event bus is closed"))
        }
        String subscriptionId = "sub-" + str(self._nextSubscriptionId)
        self._nextSubscriptionId = self._nextSubscriptionId + 1 as Long
        EventSubscription subscription = new EventSubscription(self, subscriptionId, topic)
        self._subscriptions.push(subscription)
        self._topics.push(topic)
        self._handlers.push(new EventHandlerSlot(handler))
        self._monitor.exit()
        return Ok(subscription)
    }

    Result<Int, Error> publish(Event event) {
        if event == null { throw "EventBus.publish: null event" }
        List<EventSubscription> targets = []
        List<EventHandlerSlot> handlers = []
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "event bus is closed"))
        }
        Int index = 0
        while index < self._subscriptions.length() {
            if self._topics.get(index) == event.topic() {
                targets.push(self._subscriptions.get(index))
                handlers.push(self._handlers.get(index))
            }
            index = index + 1
        }
        self._monitor.exit()

        Int delivered = 0
        index = 0
        while index < targets.length() {
            if self.isClosed() { break }
            EventSubscription subscription = targets.get(index)
            if subscription.isActive() {
                EventHandlerSlot handler = handlers.get(index)
                Result<Unit, Error> result = handler.run(event)
                if result.isErr() { return Err(result.error()) }
                delivered = delivered + 1
            }
            index = index + 1
        }
        return Ok(delivered)
    }

    Bool unsubscribe(EventSubscription subscription) {
        if subscription == null { throw "EventBus.unsubscribe: null subscription" }
        self._monitor.enter()
        Int index = 0
        while index < self._subscriptions.length() {
            if self._subscriptions.get(index) == subscription {
                subscription.markCancelled()
                self._subscriptions.remove(index)
                self._topics.remove(index)
                self._handlers.remove(index)
                self._monitor.exit()
                return true
            }
            index = index + 1
        }
        self._monitor.exit()
        return false
    }

    Bool isSubscribed(EventSubscription subscription) {
        if subscription == null { throw "EventBus.isSubscribed: null subscription" }
        self._monitor.enter()
        Int index = 0
        while index < self._subscriptions.length() {
            if self._subscriptions.get(index) == subscription {
                self._monitor.exit()
                return true
            }
            index = index + 1
        }
        self._monitor.exit()
        return false
    }

    Bool isClosed() {
        self._monitor.enter()
        Bool result = self._closed
        self._monitor.exit()
        return result
    }

    Void close() {
        self._monitor.enter()
        if !self._closed {
            self._closed = true
            Int index = 0
            while index < self._subscriptions.length() {
                self._subscriptions.get(index).markCancelled()
                index = index + 1
            }
            self._subscriptions.clear()
            self._topics.clear()
            self._handlers.clear()
        }
        self._monitor.exit()
    }
}
