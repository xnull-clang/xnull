import xdk.cli

static Int main() {
    List<String> argv = ["--name", "argv"]
    Args flagged = new Args(argv)
    print(resolveValue(flagged, "--name", "XDK_R4_CLI", "config", "fallback"))
    List<String> empty = []
    Args none = new Args(empty)
    print(resolveValue(none, "--name", "XDK_R4_CLI", "config", "fallback"))
    print(resolveValue(none, "--name", "XDK_R4_MISSING", "config", "fallback"))
    print(resolveValue(none, "--name", "XDK_R4_MISSING", "", "fallback"))
    print(defaultFromEnv("XDK_R4_CLI", "fb"))
    print(defaultFromEnv("XDK_R4_MISSING", "fb"))
    return 0
}
