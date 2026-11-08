static Int main() {
    Int x = 0
    x++
    x += 1
    do { x = x - 1 } while x > 0
    switch x {
        case 0:
            print("zero")
        default:
            print("other")
    }
    defer print(x)
    defer { print(x) }
    label:
    if x < 0 { goto label }
    throw x
}
