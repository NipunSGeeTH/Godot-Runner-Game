#!/usr/bin/env python3
"""Tiny HTTPS static server for the exported Godot web build.

Godot 4 web builds only run in a "secure context" (https:// or localhost),
so we serve over HTTPS using the self-signed cert.pem / key.pem in this folder.

Serves ./build/web on 0.0.0.0:8000 so phones on the same Wi-Fi can open it.
Also adds cross-origin-isolation headers (harmless for the single-threaded
build, required if you later switch to a multi-threaded web export).

Usage:  python3 serve.py
Then open  https://<your-computer-ip>:8000  on your phone and tap
"proceed / continue" past the self-signed certificate warning once.
"""
import http.server
import socketserver
import ssl
import os

PORT = 8000
HERE = os.path.dirname(os.path.abspath(__file__))
DIRECTORY = os.path.join(HERE, "build", "web")
CERT = os.path.join(HERE, "cert.pem")
KEY = os.path.join(HERE, "key.pem")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(certfile=CERT, keyfile=KEY)
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
        print(f"Serving {DIRECTORY} at https://0.0.0.0:{PORT}")
        httpd.serve_forever()
