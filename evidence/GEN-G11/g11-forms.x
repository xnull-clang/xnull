static String f(String v) { List<String> b = [v]; return b.get(0) }
static Int g(Int v) { List<Int> b = [v]; return b.length() }
static Int main() { print(f("hi")); print(g(3)); return 0 }
