// R4 evidence: mapOk cross-type inference over a complex receiver expression.
// Before the fix, `makeItem(value).label()` made typeArgsFor fail to infer U,
// so the generic call stayed unresolved and reported SEM-001 undefined mapOk.
import xdk.errors

class Item {
    Int value
    Item(Int value) { self.value = value }
    String label() { return "v=" + str(self.value) }
}

static Result<Int, Error> okOne() {
    return Ok(1)
}

static Item makeItem(Int value) {
    return new Item(value)
}

static Int main() {
    Result<String, Error> direct = mapOk(okOne(), (Int value) -> makeItem(value).label())
    print(direct.value())

    List<Item> items = []
    items.push(new Item(7))
    Result<String, Error> viaList = mapOk(okOne(), (Int value) -> items.get(0).label())
    print(viaList.value())

    Result<Item, Error> mapped = mapOk(okOne(), (Int value) -> makeItem(value))
    print(mapped.value().label())
    return 0
}
