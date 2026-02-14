#!/usr/bin/env python3
"""Simple HTTP server for Godot web exports with correct MIME types."""
import http.server
import os

os.chdir("/home/sprite/game/build")

class GodotHTTPHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".wasm"):
            return "application/wasm"
        if path.endswith(".pck"):
            return "application/octet-stream"
        return super().guess_type(path)

with http.server.HTTPServer(("", 8080), GodotHTTPHandler) as httpd:
    print("Serving Godot game on port 8080")
    httpd.serve_forever()
