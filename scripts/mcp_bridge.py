#!/usr/bin/env python3
"""Local stdio MCP bridge to the Android app. Python standard library only."""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("port must be 1024..65535")
    token = os.environ.get("DERK_MCP_TOKEN")
    if not token:
        print("Set DERK_MCP_TOKEN to a fresh user-issued app token.", file=sys.stderr)
        return 2
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.ProxyHandler({}))
    endpoint = "http://127.0.0.1:" + str(args.port) + "/mcp"
    for line in sys.stdin.buffer:
        request_id = None
        notification = False
        try:
            if len(line) > 65536:
                raise ValueError("Request too large")
            message = json.loads(line)
            if not isinstance(message, dict):
                raise ValueError("JSON-RPC object required")
            request_id = message.get("id")
            notification = "id" not in message
            request = urllib.request.Request(endpoint, data=line, headers={
                "Authorization": "Bearer " + token,
                "Content-Type": "application/json",
                "Accept": "application/json, text/event-stream",
                "MCP-Protocol-Version": "2025-06-18",
            }, method="POST")
            with opener.open(request, timeout=30) as response:
                result = response.read()
            if not notification and result:
                sys.stdout.write(result.decode("utf-8") + "\n")
                sys.stdout.flush()
        except (urllib.error.URLError, TimeoutError, OSError):
            if not notification:
                print(json.dumps({"jsonrpc": "2.0", "id": request_id,
                    "error": {"code": -32000, "message": "App unavailable or token expired. Unlock the app, issue a new token and check adb forwarding."}}), flush=True)
        except (ValueError, TypeError):
            if not notification:
                print(json.dumps({"jsonrpc": "2.0", "id": request_id,
                    "error": {"code": -32700, "message": "Invalid JSON-RPC message"}}), flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
