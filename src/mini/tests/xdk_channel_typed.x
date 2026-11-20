import xdk.sync
import xdk.errors

class Item {
    Int value

    Item(Int value) {
        self.value = value
    }
}

static Int main() {
    Channel<String> text = new Channel<String>(1)
    print(text.send("hello").isOk())
    Result<String, CancelledError> receivedText = text.receive()
    print(receivedText.isOk())
    print(receivedText.value())

    Channel<Item> items = new Channel<Item>(1)
    Item item = new Item(7)
    print(items.send(item).isOk())
    Result<Item, CancelledError> receivedItem = items.receive()
    print(receivedItem.isOk())
    print(receivedItem.value().value)

    Channel<String?> nullable = new Channel<String?>(1)
    print(nullable.send(null).isOk())
    Result<String?, CancelledError> receivedNull = nullable.receive()
    print(receivedNull.isOk())
    print(receivedNull.value() == null)

    Channel<Error> errors = new Channel<Error>(1)
    BasicError missing = new BasicError(ErrorKind.NotFound, "missing")
    print(errors.send(missing).isOk())
    Result<Error, CancelledError> receivedError = errors.receive()
    print(receivedError.isOk())
    print(receivedError.value().kind() == ErrorKind.NotFound)
    return 0
}
