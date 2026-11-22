@Builder
class ServerConfig {
    final String host
    final Int port
    final Bool tls
    ServerConfig(String host, Int port, Bool tls) {
        self.host = host
        self.port = port
        self.tls = tls
    }
}
static Int main() {
    ServerConfigBuilder builder = new ServerConfigBuilder()
    ServerConfig cfg = builder.withHost("h").withPort(8080).withTls(true).build()
    print(cfg.host)
    print(cfg.port)
    print(cfg.tls)
    return 0
}
