import xdk.sync
import xdk.errors
import xdk.bytes

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

    Channel<Long> longs = new Channel<Long>(1)
    print(longs.send(9000000000).isOk())
    Result<Long, CancelledError> receivedLong = longs.receive()
    print(receivedLong.value())

    Channel<Bool> bools = new Channel<Bool>(1)
    print(bools.send(true).isOk())
    Result<Bool, CancelledError> receivedBool = bools.receive()
    print(receivedBool.value())

    Channel<Char> chars = new Channel<Char>(1)
    print(chars.send('x').isOk())
    Result<Char, CancelledError> receivedChar = chars.receive()
    print(str(receivedChar.value()))

    Channel<Bytes> payloads = new Channel<Bytes>(1)
    Bytes raw = fromUtf8("ffi")
    print(payloads.send(raw).isOk())
    Result<Bytes, CancelledError> receivedBytes = payloads.receive()
    print(receivedBytes.isOk())
    print(toUtf8(receivedBytes.value()))

    Channel<Double> doubles = new Channel<Double>(1)
    print(doubles.send(1.5).isOk())
    Result<Double, CancelledError> receivedDouble = doubles.receive()
    print(receivedDouble.isOk())
    print(receivedDouble.value())
    return 0
}
