import xdk.sync
import xdk.errors
import xdk.bytes

static Result<Int, Error> okOne() {
    return Ok(1)
}

static Result<Int, Error> badResult() {
    return Err(new BasicError(ErrorKind.InvalidArgument, "bad"))
}

static Result<Int, String> okTextResult() {
    return Ok(2)
}

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

    Channel<Int128> bigs = new Channel<Int128>(1)
    print(bigs.send(170141183460469231731687303715884105727).isOk())
    Result<Int128, CancelledError> receivedBig = bigs.receive()
    print(receivedBig.value())

    Channel<Result<Int, Error>> boxes = new Channel<Result<Int, Error>>(1)
    print(boxes.send(okOne()).isOk())
    Result<Result<Int, Error>, CancelledError> receivedOk = boxes.receive()
    print(receivedOk.value().isOk())
    print(receivedOk.value().value())
    print(boxes.send(badResult()).isOk())
    Result<Result<Int, Error>, CancelledError> receivedBad = boxes.receive()
    print(receivedBad.value().isErr())
    print(receivedBad.value().error().describe())

    Channel<Result<Int, String>> textBoxes = new Channel<Result<Int, String>>(1)
    print(textBoxes.send(okTextResult()).isOk())
    Result<Result<Int, String>, CancelledError> receivedIntText = textBoxes.receive()
    print(receivedIntText.isOk())
    print(receivedIntText.value().isOk())
    print(receivedIntText.value().value())
    return 0
}
