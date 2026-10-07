#!/usr/bin/env python3
"""Local forward proxy (127.0.0.1:8888) that relays to the sandbox egress
proxy, injecting Proxy-Authorization from the ambient *_proxy env vars.

Why: some JVM/Dart HTTP clients use a proxy but never send proxy auth, so
requests to auth-requiring hosts fail. This shim adds the auth header
without ever writing the credential to a file or argument.

Reads credentials ONLY from the existing environment (same as curl does).
"""
import base64
import os
import socket
import threading
import urllib.parse

LISTEN = ("127.0.0.1", 8888)


def _upstream():
    raw = os.environ.get("https_proxy") or os.environ.get("http_proxy") or ""
    u = urllib.parse.urlparse(raw)
    auth = ""
    if u.username:
        token = f"{urllib.parse.unquote(u.username)}:{urllib.parse.unquote(u.password or '')}"
        auth = "Basic " + base64.b64encode(token.encode()).decode()
    return u.hostname, u.port or 3128, auth


# NOTE: upstream credentials rotate frequently — re-resolve per connection.
def _upstream_now():
    return _upstream()


def relay(a, b):
    try:
        while True:
            data = a.recv(65536)
            if not data:
                break
            b.sendall(data)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            s.close()


def handle(client):
    try:
        # Read headers.
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = client.recv(4096)
            if not chunk:
                client.close()
                return
            buf += chunk
            if len(buf) > 65536:
                client.close()
                return
        head, rest = buf.split(b"\r\n\r\n", 1)
        lines = head.decode("latin1").split("\r\n")
        method, target, _ = lines[0].split(" ", 2)

        UP_HOST, UP_PORT, UP_AUTH = _upstream_now()
        up = socket.create_connection((UP_HOST, UP_PORT), timeout=30)
        if method.upper() == "CONNECT":
            # target is host:port
            req = f"CONNECT {target} HTTP/1.1\r\nHost: {target}\r\n"
            if UP_AUTH:
                req += f"Proxy-Authorization: {UP_AUTH}\r\n"
            req += "Proxy-Connection: keep-alive\r\n\r\n"
            up.sendall(req.encode("latin1"))
            # Read upstream response headers.
            rbuf = b""
            while b"\r\n\r\n" not in rbuf:
                chunk = up.recv(4096)
                if not chunk:
                    break
                rbuf += chunk
            client.sendall(rbuf)
            if b" 200" not in rbuf.split(b"\r\n", 1)[0]:
                client.close()
                up.close()
                return
        else:
            # Plain HTTP: forward request with absolute URI.
            out_lines = [lines[0]]
            for ln in lines[1:]:
                if ln.lower().startswith("proxy-authorization:"):
                    continue
                out_lines.append(ln)
            if UP_AUTH:
                out_lines.append(f"Proxy-Authorization: {UP_AUTH}")
            up.sendall(("\r\n".join(out_lines) + "\r\n\r\n").encode("latin1") + rest)

        t1 = threading.Thread(target=relay, args=(client, up), daemon=True)
        t2 = threading.Thread(target=relay, args=(up, client), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
    except OSError:
        try:
            client.close()
        except OSError:
            pass


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(LISTEN)
    srv.listen(100)
    print("auth_proxy: listening on 127.0.0.1:8888", flush=True)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handle, args=(c,), daemon=True).start()


if __name__ == "__main__":
    main()
