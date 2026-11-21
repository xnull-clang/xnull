class Item {
    String name
    Int count

    Item(String name, Int count) {
        self.name = name
        self.count = count
    }
}

Int total(List<Int> values) {
    Int sum = 0
    Int index = 0
    while index < values.length() {
        sum = sum + values.get(index)
        index = index + 1
    }
    return sum
}
