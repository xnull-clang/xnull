#!/usr/bin/env python3
"""Standard-library client fixture for the M5.3b HTTP server gate."""
import http.client
import socket
import sys


def request(port, method, path, body=None, headers=None):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    conn.request(method, path, body=body, headers=headers or {})
    response = conn.getresponse()
    data = response.read().decode("utf-8", "replace")
    status = response.status
    conn.close()
    return status, data


def raw_invalid(port, payload):
    sock = socket.create_connection(("127.0.0.1", port), timeout=5)
    sock.sendall(payload)
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    sock.close()
    first = data.split(b"\r\n", 1)[0].decode("ascii", "replace")
    return first


def main():
    port = int(sys.argv[1])
    hello_status, hello_body = request(port, "GET", "/hello")
    print("hello=%d,%s" % (hello_status, hello_body))

    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    conn.putrequest("POST", "/echo")
    conn.putheader("X-Test", "one")
    conn.putheader("X-Test", "two")
    conn.putheader("Content-Length", "7")
    conn.endheaders(b"payload")
    response = conn.getresponse()
    echo_body = response.read().decode("utf-8", "replace")
    echo_status = response.status
    echo_header = response.getheader("X-Test")
    conn.close()
    print("echo=%d,%s" % (echo_status, echo_body))
    print("echo-header=%s" % echo_header)

    twice_status, _twice_body = request(port, "GET", "/twice")
    print("twice=%d" % twice_status)

    missing_status, missing_body = request(port, "GET", "/missing")
    print("missing=%d,%s" % (missing_status, missing_body))

    print("invalid=" + raw_invalid(port, b"BROKEN\r\n\r\n"))
    print("chunked=" + raw_invalid(port, b"POST /echo HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"))

    unresponded_status, _unresponded_body = request(port, "GET", "/unresponded")
    print("unresponded=%d" % unresponded_status)
    return 0


if __name__ == "__main__":
    sys.exit(main())
