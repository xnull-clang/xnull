import xdk.sync

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
    return 0
}
