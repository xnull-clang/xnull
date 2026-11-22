@Deprecated Int old() {
    return 1
}

@SuppressWarnings("AN9999")
static Int badSuppression() {
    return 2
}

static Int main() {
    Int value = old()
    print("business")
    return 0
}
