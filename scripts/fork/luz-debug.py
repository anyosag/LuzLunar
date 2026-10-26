#!/usr/bin/env python3
"""Follow LuzLunar and the PC's Apollo from this Mac, to debug either (see FORK.md, "Debug channel").

LuzLunar answers on its debug socket while it runs; its log files are read straight from /tmp.
Apollo answers /actions/log over HTTPS, with LuzLunar's own paired identity (its certificate and
key in LuzLunar's settings), so it needs the Read Log permission on Apollo's PIN page. The key is
used from a private temporary file and never printed.

  luz-debug.py luz status                     LuzLunar's state and log file
  luz-debug.py luz log [-n 200] [-g TEXT] [-f] its log: the last lines, those containing TEXT, or follow it
  luz-debug.py luz level debug [-m 30]        more detail for a while (info, debug, verbose)
  luz-debug.py apollo status                  Apollo's version, state and log level
  luz-debug.py apollo log [-n] [-g] [-f]      Apollo's log, the same way
  luz-debug.py apollo level debug [-m 30]     (verbose, debug, info, warning, error, fatal, none; configured)
  luz-debug.py apollo get /actions/displaygroup     any request LuzLunar can make, as JSON or XML
  luz-debug.py apollo post /actions/cursor '{"..."}'
  luz-debug.py mark "copy test 1"             a line in both logs, to find later

Apollo is the paired PC that runs it (or --host NAME); --address overrides where to reach it.
"""

import argparse
import http.client
import json
import os
import plistlib
import socket
import ssl
import sys
import tempfile
import time
import urllib.parse
import uuid
import xml.etree.ElementTree as ElementTree
from pathlib import Path

SETTINGS = Path.home() / "Library/Preferences/com.moonlight-stream.Moonlight.plist"
SOCKET = Path.home() / "Library/Application Support/LuzLunar/debug.sock"
LOG_DIR = Path("/tmp")


class Failure(Exception):
    pass


# LuzLunar


def luz_request(request):
    """One request on LuzLunar's debug socket; its JSON reply"""
    if not SOCKET.exists():
        raise Failure(f"LuzLunar isn't running, or is older than its debug channel ({SOCKET} is missing)")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        try:
            connection.connect(str(SOCKET))
        except OSError as error:
            raise Failure(f"LuzLunar doesn't answer on {SOCKET}: {error}")
        connection.sendall(json.dumps(request).encode() + b"\n")
        reply = b""
        while not reply.endswith(b"\n"):
            chunk = connection.recv(65536)
            if not chunk:
                break
            reply += chunk
    answer = json.loads(reply)
    if not answer.get("ok"):
        raise Failure(f"LuzLunar: {answer.get('error', 'refused')}")
    return answer


def luz_log_file(args):
    if args.file:
        return Path(args.file)
    try:
        current = luz_request({"op": "status"}).get("logFile")
        if current:
            return Path(current)
    except Failure:
        pass
    logs = [path for path in LOG_DIR.glob("Moonlight-*.log") if "-slot" not in path.name]
    if not logs:
        raise Failure(f"no LuzLunar logs in {LOG_DIR}")
    return max(logs, key=lambda path: path.stat().st_mtime)


def matching(lines, grep):
    needle = (grep or "").lower()
    return [line for line in lines if needle in line.lower()]


def luz_log(args):
    path = luz_log_file(args)
    print(f"# {path}", file=sys.stderr)
    with open(path, "rb") as log:
        text = log.read().decode("utf-8", "replace")
        offset = log.tell()
    for line in matching(text.splitlines(), args.grep)[-args.lines:]:
        print(line)
    while args.follow:
        time.sleep(0.5)
        size = path.stat().st_size
        if size < offset:
            offset = 0
        if size == offset:
            continue
        with open(path, "rb") as log:
            log.seek(offset)
            chunk = log.read()
        whole = chunk.rfind(b"\n") + 1
        offset += whole
        for line in matching(chunk[:whole].decode("utf-8", "replace").splitlines(), args.grep):
            print(line, flush=True)


def show(state, keys):
    for key in keys:
        if key in state:
            print(f"{key}: {state[key]}")


LUZ_KEYS = ["app", "version", "pid", "streaming", "level", "secondsLeft", "logFile", "logBytes", "logLimit"]


# Apollo


def settings():
    try:
        with open(SETTINGS, "rb") as file:
            return plistlib.load(file)
    except OSError as error:
        raise Failure(f"can't read LuzLunar's settings: {error}")


def apollo_host(values, wanted):
    """The paired host to talk to: by name, else the one running Apollo"""
    hosts = []
    for index in range(1, int(values.get("hosts.size", 0)) + 1):
        prefix = f"hosts.{index}."
        host = {key[len(prefix):]: value for key, value in values.items() if key.startswith(prefix)}
        if host.get("srvcert"):
            hosts.append(host)
    if wanted:
        hosts = [host for host in hosts if host.get("hostname", "").lower() == wanted.lower()]
    else:
        hosts.sort(key=lambda host: not host.get("forkapollosw"))
    if not hosts:
        raise Failure(f"no paired host{' named ' + wanted if wanted else ''} in LuzLunar's settings")
    return hosts[0]


def addresses(host, override):
    if override:
        address, _, port = override.partition(":")
        return [(address, int(port or 47989))]
    found = []
    for kind in ("manual", "local", "remote", "ipv6"):
        address = host.get(f"{kind}address")
        if address and address not in [entry[0] for entry in found]:
            found.append((address, host.get(f"{kind}port") or 47989))
    return found


class Apollo:
    def __init__(self, args):
        values = settings()
        self.host = apollo_host(values, args.host)
        self.unique_id = values.get("uniqueid", "0123456789ABCDEF")
        self.server_cert = ssl.PEM_cert_to_DER_cert(self.host["srvcert"].decode())
        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        self.context.check_hostname = False
        self.context.verify_mode = ssl.CERT_NONE  # pinned to the paired certificate instead, below
        with tempfile.TemporaryDirectory() as folder:
            cert, key = Path(folder, "cert.pem"), Path(folder, "key.pem")
            for path, data in ((cert, values["certificate"]), (key, values["key"])):
                descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(descriptor, "wb") as file:
                    file.write(data)
            self.context.load_cert_chain(cert, key)
        self.target = self.reach(addresses(self.host, args.address))

    def reach(self, candidates):
        """The first address that answers serverinfo, and its HTTPS port"""
        failures = []
        for address, port in candidates:
            try:
                connection = http.client.HTTPConnection(address, port, timeout=3)
                connection.request("GET", f"/serverinfo?uniqueid={self.unique_id}&uuid={uuid.uuid4().hex}")
                body = connection.getresponse().read()
                https = ElementTree.fromstring(body).findtext("HttpsPort") or "47984"
                return address, int(https)
            except (OSError, ElementTree.ParseError, ValueError) as error:
                failures.append(f"{address}:{port} ({error})")
        raise Failure(f"{self.host.get('hostname')} doesn't answer: " + ", ".join(failures))

    def request(self, method, path, body=None, timeout=10):
        address, port = self.target
        connection = http.client.HTTPSConnection(address, port, timeout=timeout, context=self.context)
        connection.connect()
        if connection.sock.getpeercert(binary_form=True) != self.server_cert:
            connection.close()
            raise Failure(f"{address}:{port} isn't the paired {self.host.get('hostname')} (its certificate differs)")
        headers = {"Content-Type": "application/json"} if body is not None else {}
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        return response.status, response.read()

    def json(self, method, path, body=None):
        status, data = self.request(method, path, None if body is None else json.dumps(body))
        try:
            answer = json.loads(data) if data else {}
        except ValueError:
            answer = {"raw": data.decode("utf-8", "replace")}
        if status == 404:
            raise Failure(f"Apollo has no {path.split('?')[0]} (older than its debug channel?)")
        if status in (401, 403):
            raise Failure(f"Apollo refused {path.split('?')[0]}: give LuzLunar's client the Read Log permission on Apollo's PIN page")
        if status >= 400:
            raise Failure(f"Apollo answered {status}: {answer.get('error', answer)}")
        return answer


def apollo_status(apollo):
    status, body = apollo.request("GET", f"/serverinfo?uniqueid={apollo.unique_id}&uuid={uuid.uuid4().hex}")
    root = ElementTree.fromstring(body)
    print(f"host: {root.findtext('hostname')} at {apollo.target[0]}")
    for tag in ("appversion", "state", "currentgame", "PairStatus", "Permission"):
        print(f"{tag}: {root.findtext(tag)}")
    print("fork: " + " ".join(f"{child.tag}={child.text}" for child in root if child.tag.startswith("Luz")))
    try:
        log = apollo.json("GET", "/actions/log?lines=1")
        show(log, ["level", "configuredLevel", "secondsLeft"])
    except Failure as error:
        print(f"log: {error}")


def apollo_log(apollo, args):
    query = {"lines": args.lines}
    if args.grep:
        query["grep"] = args.grep
    answer = apollo.json("GET", "/actions/log?" + urllib.parse.urlencode(query))
    for line in answer["lines"]:
        print(line)
    following = answer["next"]
    while args.follow:
        time.sleep(1)
        query = {"lines": 5000, "from": following}
        if args.grep:
            query["grep"] = args.grep
        answer = apollo.json("GET", "/actions/log?" + urllib.parse.urlencode(query))
        if answer.get("restarted"):
            print("# Apollo restarted: its new log", file=sys.stderr)
        for line in answer["lines"]:
            print(line, flush=True)
        following = answer["next"]


# Commands


def run(args):
    if args.app == "luz":
        if args.command == "status":
            show(luz_request({"op": "status"}), LUZ_KEYS)
        elif args.command == "log":
            luz_log(args)
        elif args.command == "level":
            show(luz_request({"op": "level", "level": args.level, "minutes": args.minutes}), ["level", "secondsLeft"])
        elif args.command == "mark":
            luz_request({"op": "mark", "text": args.text})
            print("marked LuzLunar's log")
        return

    if args.app == "mark":
        for name, action in (("LuzLunar", lambda: luz_request({"op": "mark", "text": args.text})),
                             ("Apollo", lambda: Apollo(args).json("POST", "/actions/log", {"mark": args.text}))):
            try:
                action()
                print(f"marked {name}'s log")
            except Failure as error:
                print(f"{name}: {error}", file=sys.stderr)
        return

    apollo = Apollo(args)
    if args.command == "status":
        apollo_status(apollo)
    elif args.command == "log":
        apollo_log(apollo, args)
    elif args.command == "level":
        body = {"level": args.level} if args.level == "configured" else {"level": args.level, "minutes": args.minutes}
        show(apollo.json("POST", "/actions/log", body), ["level", "configuredLevel", "secondsLeft"])
    elif args.command == "mark":
        apollo.json("POST", "/actions/log", {"mark": args.text})
        print("marked Apollo's log")
    elif args.command in ("get", "post"):
        status, data = apollo.request(args.command.upper(), args.path, args.body if args.command == "post" else None)
        print(f"# {status}", file=sys.stderr)
        text = data.decode("utf-8", "replace")
        try:
            print(json.dumps(json.loads(text), indent=2))
        except ValueError:
            print(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", help="the paired PC's name (default: the one running Apollo)")
    parser.add_argument("--address", help="where to reach Apollo, ADDRESS[:HTTP_PORT]")
    apps = parser.add_subparsers(dest="app", required=True)

    def common(commands, levels):
        commands.add_parser("status")
        log = commands.add_parser("log")
        log.add_argument("-n", "--lines", type=int, default=200)
        log.add_argument("-g", "--grep", help="only lines containing this, ignoring case")
        log.add_argument("-f", "--follow", action="store_true", help="keep printing new lines")
        level = commands.add_parser("level")
        level.add_argument("level", choices=levels)
        level.add_argument("-m", "--minutes", type=int, default=30)
        mark = commands.add_parser("mark")
        mark.add_argument("text")
        return log

    luz = apps.add_parser("luz", help="LuzLunar on this Mac").add_subparsers(dest="command", required=True)
    common(luz, ["info", "debug", "verbose"]).add_argument("--file", help="a log file instead of the current one")

    apollo = apps.add_parser("apollo", help="Apollo on the PC").add_subparsers(dest="command", required=True)
    common(apollo, ["verbose", "debug", "info", "warning", "error", "fatal", "none", "configured"])
    get = apollo.add_parser("get")
    get.add_argument("path")
    post = apollo.add_parser("post")
    post.add_argument("path")
    post.add_argument("body")

    both = apps.add_parser("mark", help="a line in both logs")
    both.add_argument("text")

    args = parser.parse_args()
    try:
        run(args)
    except Failure as error:
        print(error, file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
