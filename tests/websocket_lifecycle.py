"""Real RFC6455 connection lifecycle checks against either installed driver."""

import base64
import http.client
import json
import os
import secrets
import socket
import struct
import time
import urllib.parse


class WebSocket:
    def __init__(
        self, base, query="", *, path="/__fixtures/ws/lifecycle", headers=None, opened=True
    ):
        self.address = urllib.parse.urlsplit(base)
        self.socket = socket.create_connection(
            (self.address.hostname, self.address.port), timeout=5
        )
        self.socket.settimeout(5)
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        path += query
        extra_headers = "".join(
            name + ": " + value + "\r\n" for name, value in (headers or {}).items()
        )
        request = (
            "GET "
            + path
            + " HTTP/1.1\r\nHost: "
            + self.address.netloc
            + "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: "
            + key
            + "\r\nSec-WebSocket-Version: 13\r\n"
            + extra_headers
            + "\r\n"
        )
        self.socket.sendall(request.encode())
        self.buffer = b""
        while b"\r\n\r\n" not in self.buffer:
            block = self.socket.recv(4096)
            if not block:
                raise AssertionError("WebSocket handshake ended early")
            self.buffer += block
        header, self.buffer = self.buffer.split(b"\r\n\r\n", 1)
        if not header.startswith(b"HTTP/1.1 101"):
            self.socket.close()
            raise AssertionError(header[:200])
        if opened:
            assert self.receive() == (1, b"opened")

    def exact(self, length):
        while len(self.buffer) < length:
            block = self.socket.recv(max(4096, length - len(self.buffer)))
            if not block:
                raise EOFError()
            self.buffer += block
        result, self.buffer = self.buffer[:length], self.buffer[length:]
        return result

    def send(self, payload=b"", opcode=1, masked=True):
        if isinstance(payload, str):
            payload = payload.encode()
        length = len(payload)
        flag = 128 if masked else 0
        if length < 126:
            header = bytes([128 | opcode, flag | length])
        elif length < 65536:
            header = bytes([128 | opcode, flag | 126]) + struct.pack(">H", length)
        else:
            header = bytes([128 | opcode, flag | 127]) + struct.pack(">Q", length)
        if masked:
            mask = secrets.token_bytes(4)
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
            header += mask
        self.socket.sendall(header + payload)

    def receive(self):
        while True:
            first, second = self.exact(2)
            length = second & 127
            if length == 126:
                length = struct.unpack(">H", self.exact(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self.exact(8))[0]
            assert length <= 10 * 1024 * 1024
            payload = self.exact(length)
            opcode = first & 15
            if opcode == 9:
                self.send(payload, opcode=10)
                continue
            return opcode, payload

    def close(self, allow_eof=False):
        try:
            self.send(struct.pack(">H", 1000), opcode=8)
            try:
                assert self.receive()[0] == 8
            except EOFError:
                if not allow_eof:
                    raise
        finally:
            self.socket.close()

    def abort(self):
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        self.socket.close()


def request(base, path, method="GET"):
    address = urllib.parse.urlsplit(base)
    connection = http.client.HTTPConnection(address.hostname, address.port, timeout=5)
    connection.request(method, path)
    response = connection.getresponse()
    body = response.read()
    connection.close()
    assert response.status == 200, (response.status, body[:200])
    return json.loads(body)


def wait_registered(base, expected, timeout=3):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        last = request(base, "/__fixtures/ws/status")
        if last["registered"] == expected:
            return last
        time.sleep(0.02)
    raise AssertionError(
        "getSessions() should contain " + str(expected) + " connections; actual " + str(last)
    )


def run(base=None, blocked=True):
    base = base or os.environ["TEST_URL"]
    wait_registered(base, 0)
    for close_mode in ("normal", "reset", "server", "callback-error", "close-error"):
        query = "?throwClose=1" if close_mode == "close-error" else ""
        connection = WebSocket(base, query)
        wait_registered(base, 1)
        if close_mode == "reset":
            connection.abort()
        elif close_mode in ("server", "callback-error"):
            connection.send("close" if close_mode == "server" else "fail")
            try:
                assert connection.receive()[0] == 8
                connection.send(struct.pack(">H", 1000), opcode=8)
            except (EOFError, OSError):
                # Undertow's owner close shuts the channel without a close frame.
                pass
            connection.socket.close()
        else:
            connection.close(allow_eof=close_mode == "close-error")
        wait_registered(base, 0)
    for _ in range(20):
        connection = WebSocket(base)
        wait_registered(base, 1)
        connection.close()
        wait_registered(base, 0)
    if blocked:
        connection = WebSocket(base)
        connection.send("block")
        assert connection.receive() == (1, b"blocked")
        connection.abort()
        try:
            wait_registered(base, 0)
        finally:
            request(base, "/__fixtures/ws/release", "POST")
        deadline = time.monotonic() + 3
        while request(base, "/__fixtures/ws/status")["blocked"] and time.monotonic() < deadline:
            time.sleep(0.02)
    result = wait_registered(base, 0)
    assert result["opened"] == result["closed"], result
    print(
        "PASS WebSocket lifecycle: normal/reset/server/error closes, 20 reconnects, zero retained sessions"
        + (" and blocked-callback detachment" if blocked else ""),
        flush=True,
    )
    return result


if __name__ == "__main__":
    run()
