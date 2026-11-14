import xdk.net

static Int main(String[] args) {
    if args.length() != 1 { return 2 }
    Int port = parseInt(args.get(0)).value()
    Result<Listener, Error> bound = bindListener("127.0.0.1", port)
    print(bound.isOk())
    if bound.isErr() { return 1 }
    Listener listener = bound.value()
    print(listener.isOpen())
    Result<Socket, Error> accepted = listener.accept()
    print(accepted.isOk())
    if accepted.isErr() { return 1 }
    Socket socket = accepted.value()
    Result<String, Error> message = socket.recv(4)
    print(message.value())
    Result<Int, Error> sent = socket.send("pong")
    print(sent.value())
    socket.close()
    listener.close()
    print(listener.isOpen())
    return 0
}
