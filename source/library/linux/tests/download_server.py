#!/usr/bin/env python3

import http.server
import ssl
import sys
import time

MP4 = b"\x00\x00\x00\x18ftypisom\x00\x00\x00\x00isommp41"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if "Mozilla" not in self.headers.get("User-Agent", ""):
            self.send_error(403)
            return
        if self.path == "/status":
            self.send_error(503)
            return
        body = b"not an mp4 response" if self.path == "/invalid" else MP4
        if self.path == "/slow":
            body = MP4 * 4096
        self.send_response(200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.path == "/slow":
            time.sleep(0.1)
            for offset in range(0, len(body), 1024):
                try:
                    self.wfile.write(body[offset : offset + 1024])
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                    break
                time.sleep(0.005)
        else:
            self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def main():
    certificate, key, port_file = sys.argv[1:4]
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certificate, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    with open(port_file, "w", encoding="ascii") as output:
        output.write(str(server.server_port))
    server.serve_forever()


if __name__ == "__main__":
    main()
