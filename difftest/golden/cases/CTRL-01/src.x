static Int main() {
    Int hits = 0
    outer: for i in 0..<3 {
        for j in 0..<3 {
            if j == 1 {
                continue outer
            }
            if i == 2 {
                break outer
            }
            hits += 1
        }
    }
    print(hits)
    switch 1 {
        case 1: print("case1"); break
        default: print("no")
    }
    return 0
}
