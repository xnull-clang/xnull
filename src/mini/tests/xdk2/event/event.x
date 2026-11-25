package xdk2.event
import xdk.event
import xdk.codec
import xdk.errors

class Recorder {
    List<String> items
    Int calls
    Recorder() {
        self.items = []
        self.calls = 0
    }
    Void add(String value) {
        self.items.push(value)
        self.calls = self.calls + 1
    }
    String text() {
        String result = ""
        Int index = 0
        while index < self.items.length() {
            if index > 0 { result = result + "," }
            result = result + self.items.get(index)
            index = index + 1
        }
        return result
    }
}

class SubscriptionBox {
    EventSubscription? value
    SubscriptionBox() { self.value = null }
}

static Int main() {
    Event event = new Event("evt-1", "orders.created", Json.string("42"),
        100 as Long, "checkout")
    print("event=" + event.id() + "," + event.topic() + "," +
        jsonKindName(event.payload().kind()) + "," + str(event.timestampMono()) + "," +
        (event.source() as String))
    Event noSource = new Event("evt-2", "users.created", Json.number("1"),
        0 as Long, null)
    print("event-nosource=" + noSource.describe() + "," +
        str(noSource.source() == null) + "," + str(noSource.timestampMono()))
    Event nowEvent = Event.now("evt-3", "clock", Json.nullValue(), "")
    print("event-now=" + str(nowEvent.timestampMono() >= 0 as Long) + "," +
        (nowEvent.source() as String) + "," + str(nowEvent.topic() == "clock"))

    EventBus bus = new EventBus()
    Recorder recorder = new Recorder()
    Result<EventSubscription, Error> first = bus.subscribe("orders.created",
        (Event value) -> {
            recorder.add("a:" + value.id())
            return Ok()
        })
    Result<EventSubscription, Error> second = bus.subscribe("orders.created",
        (Event value) -> {
            recorder.add("b:" + value.id())
            return Ok()
        })
    Result<EventSubscription, Error> other = bus.subscribe("users.created",
        (Event value) -> {
            recorder.add("u:" + value.id())
            return Ok()
        })
    print("subscribe=" + str(first.isOk()) + "," + str(second.isOk()) + "," +
        str(other.isOk()) + "," + first.value().id() + "," + first.value().topic())
    Result<Int, Error> orders = bus.publish(event)
    print("publish=" + str(orders.isOk()) + "," + str(orders.value()) + "," +
        recorder.text() + "," + str(bus.isSubscribed(first.value())))
    Event users = Event.now("evt-4", "users.created", Json.string("u"), null)
    Result<Int, Error> usersResult = bus.publish(users)
    Result<Int, Error> none = bus.publish(Event.now("evt-5", "missing",
        Json.string("x"), null))
    Result<Int, Error> caseMismatch = bus.publish(Event.now("evt-6", "Orders",
        Json.string("x"), null))
    print("publish-topics=" + str(usersResult.value()) + "," + str(none.value()) + "," +
        str(caseMismatch.value()) + "," + recorder.text())
    Bool unsubscribed = bus.unsubscribe(first.value())
    Bool unsubscribedAgain = bus.unsubscribe(first.value())
    Result<Int, Error> afterUnsubscribe = bus.publish(Event.now("evt-7", "orders.created",
        Json.string("x"), null))
    print("unsubscribe=" + str(unsubscribed) + "," + str(unsubscribedAgain) + "," +
        str(first.value().isActive()) + "," + str(afterUnsubscribe.value()) + "," +
        recorder.text())

    EventBus failBus = new EventBus()
    Recorder failRecorder = new Recorder()
    Result<EventSubscription, Error> failFirst = failBus.subscribe("fail",
        (Event value) -> {
            failRecorder.add("first")
            return Err(new BasicError(ErrorKind.DataCorrupted, "handler failed"))
        })
    Result<EventSubscription, Error> failSecond = failBus.subscribe("fail",
        (Event value) -> {
            failRecorder.add("second")
            return Ok()
        })
    Result<Int, Error> failResult = failBus.publish(Event.now("evt-8", "fail",
        Json.string("x"), null))
    print("handler-error=" + errorKindName(failResult.error().kind()) + "," +
        failRecorder.text() + "," + str(failRecorder.calls))
    failBus.close()

    EventBus reentrantBus = new EventBus()
    SubscriptionBox box = new SubscriptionBox()
    Recorder reentrantRecorder = new Recorder()
    Result<EventSubscription, Error> reentrantFirst = reentrantBus.subscribe("re",
        (Event value) -> {
            reentrantRecorder.add("first")
            if box.value != null {
                EventSubscription target = box.value as EventSubscription
                target.cancel()
            }
            return Ok()
        })
    Result<EventSubscription, Error> reentrantSecond = reentrantBus.subscribe("re",
        (Event value) -> {
            reentrantRecorder.add("second")
            return Ok()
        })
    box.value = reentrantSecond.value()
    Result<Int, Error> reentrantResult = reentrantBus.publish(Event.now("evt-9", "re",
        Json.string("x"), null))
    print("reentrant=" + str(reentrantResult.value()) + "," + reentrantRecorder.text() +
        "," + str(reentrantSecond.value().isActive()) + "," +
        str(reentrantFirst.value().isActive()))
    reentrantBus.close()

    EventBus closeBus = new EventBus()
    Recorder closeRecorder = new Recorder()
    Result<EventSubscription, Error> closeSub = closeBus.subscribe("close",
        (Event value) -> {
            closeRecorder.add("called")
            return Ok()
        })
    closeBus.close()
    closeBus.close()
    Result<EventSubscription, Error> afterCloseSub = closeBus.subscribe("close",
        (Event value) -> Ok())
    Result<Int, Error> afterClosePublish = closeBus.publish(Event.now("evt-10", "close",
        Json.string("x"), null))
    print("close=" + str(closeBus.isClosed()) + "," + str(closeSub.value().isActive()) +
        "," + errorKindName(afterCloseSub.error().kind()) + "," +
        errorKindName(afterClosePublish.error().kind()) + "," + str(closeRecorder.calls))
    return 0
}
