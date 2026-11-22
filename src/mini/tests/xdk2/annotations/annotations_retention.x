@Retention(Source)
@annotation SrcOnly {
}

@Retention(Binary)
@annotation BinOnly {
}

@Retention(Runtime)
@annotation RunOnly {
}

@SrcOnly
@BinOnly
@RunOnly
class Retained {
}

static Int main() {
    print("retention")
    return 0
}
