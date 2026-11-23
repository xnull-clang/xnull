#!/usr/bin/env python3
"""Deterministic local HTTP fixture for the M5.3a client gate."""
import socket
import sys
from pathlib import Path


def read_request(conn):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(4096)
        if not chunk:
            return None, None, b""
        data += chunk
    header_end = data.index(b"\r\n\r\n")
    head = data[:header_end].decode("iso-8859-1")
    body = data[header_end + 4:]
    lines = head.split("\r\n")
    request_line = lines[0].split(" ")
    method = request_line[0]
    path = request_line[1]
    length = 0
    for line in lines[1:]:
        name, _, value = line.partition(":")
        if name.lower() == "content-length":
            length = int(value.strip())
    while len(body) < length:
        chunk = conn.recv(4096)
        if not chunk:
            break
        body += chunk
    return method, path, body[:length]


def main():
    if len(sys.argv) != 3:
        print("usage: server_fixture.py <port-file> <request-count>", file=sys.stderr)
        return 2
    port_file = Path(sys.argv[1])
    count = int(sys.argv[2])
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    server.listen(8)
    server.settimeout(10.0)
    port_file.write_text(str(server.getsockname()[1]), encoding="ascii")
    try:
        for _ in range(count):
            conn, _address = server.accept()
            conn.settimeout(5.0)
            with conn:
                method, path, body = read_request(conn)
                if method is None:
                    continue
                if method == "GET" and path == "/hello":
                    status, reason, response = 200, "OK", b"hello"
                elif method == "POST" and path == "/echo":
                    status, reason, response = 200, "OK", body
                else:
                    status, reason, response = 404, "Not Found", b"missing"
                head = ("HTTP/1.1 %d %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" %
                        (status, reason, len(response))).encode("ascii")
                conn.sendall(head + response)
    except socket.timeout:
        return 3
    finally:
        server.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
