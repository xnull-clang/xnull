enum Color { Red, Green }

@annotation Inner {
    final Int n = 0
}

@annotation Sample {
    final Bool enabled = true
    final Int i = -7
    final Double d = 1.5
    final Char c = 'x'
    final String s = "text"
    final Color color = Color.Red
    final Int[] nums = [1, 2, 3]
    final Inner inner = @Inner(2)
    final String typeRef = "demo.Box"
}

@Sample(true, -3, 2.5, 'z', "hello", Color.Green, [4, 5], @Inner(9), "demo.Thing")
class Args {
}

static Int main() {
    print("args")
    return 0
}
