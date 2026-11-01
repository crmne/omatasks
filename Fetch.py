# Makes one Todoist API request for the service and caps what comes back.
#
# QML's XMLHttpRequest keeps the whole response body in the shell's memory
# before a script can look at it, and Qt's network thread keeps reading while
# the shell is busy, so no check in QML can bound it. This process reads at
# most LIMIT bytes and then stops, and the shell reads only what it prints.
#
# The request, including the API token, arrives as one JSON object on stdin,
# because a process's arguments and environment are readable by other
# processes. The answer is one JSON line ({"status": 200, "retryAfter": ""},
# or {"status": 0, "error": "too-large"}), then the response body as is.
#
# Each request opens its own connection, so a connection stranded by a dropped
# network or a route change never outlives the request that found it. The
# error "unreachable" means no connection was made, so nothing was sent.
import itertools
import json
import socket
import sys
import time
import urllib.error
import urllib.request

LIMIT = 16 * 1024 * 1024
REQUEST_LIMIT = 4 * 1024 * 1024
DEADLINE = 20
CHUNK = 65536
CONNECT_TIMEOUT = 4
CONNECT_ATTEMPTS = 4


class Unreachable(OSError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    # Never forward the token to another address.
    def redirect_request(self, *args):
        return None


def alternate(addresses):
    first = [a for a in addresses if a[0] == addresses[0][0]]
    others = [a for a in addresses if a[0] != addresses[0][0]]
    pairs = itertools.zip_longest(first, others)
    return [a for pair in pairs for a in pair if a]


# A dead IPv6 path swallows connection attempts without an error, and the
# resolver can list many addresses on it before any IPv4 one. Trying each for
# the whole deadline would never reach a path that works, so give each a few
# seconds and alternate between IPv6 and IPv4.
def connect(address, timeout=None, source_address=None, **_):
    try:
        found = socket.getaddrinfo(*address, type=socket.SOCK_STREAM)
    except OSError as e:
        raise Unreachable from e
    for family, kind, protocol, _, target in alternate(found)[:CONNECT_ATTEMPTS]:
        sock = socket.socket(family, kind, protocol)
        try:
            sock.settimeout(CONNECT_TIMEOUT)
            if source_address:
                sock.bind(source_address)
            sock.connect(target)
        except OSError:
            sock.close()
            continue
        sock.settimeout(timeout)
        return sock
    raise Unreachable


# http.client looks this up for each connection. This process makes only one.
socket.create_connection = connect


def answer(meta, body=b''):
    out = sys.stdout.buffer
    out.write(json.dumps(meta).encode() + b'\n')
    out.write(body)
    out.flush()


def fetch(request):
    started = time.monotonic()
    headers = {'Authorization': 'Bearer ' + str(request['token']),
               'Content-Type': str(request.get('contentType') or 'application/json'),
               'Accept-Encoding': 'identity'}
    if request.get('requestId'):
        headers['X-Request-Id'] = str(request['requestId'])
    body = str(request.get('body') or '').encode()
    opener = urllib.request.build_opener(NoRedirect)
    req = urllib.request.Request(str(request['url']), data=body, headers=headers,
                                 method=str(request.get('method') or 'GET'))
    try:
        response = opener.open(req, timeout=DEADLINE)
    except urllib.error.HTTPError as e:
        # The service reads only the status and Retry-After of a failure.
        answer({'status': e.code, 'retryAfter': e.headers.get('Retry-After') or ''})
        e.close()
        return
    except urllib.error.URLError as e:
        if isinstance(e.reason, Unreachable):
            answer({'status': 0, 'error': 'unreachable'})
            return
        raise
    with response:
        status = response.status
        retry = response.headers.get('Retry-After') or ''
        length = response.headers.get('Content-Length')
        if length and length.isdigit() and int(length) > LIMIT:
            answer({'status': 0, 'error': 'too-large'})
            return
        chunks, size = [], 0
        while True:
            if time.monotonic() - started > DEADLINE:
                answer({'status': 0, 'error': 'timeout'})
                return
            chunk = response.read1(CHUNK)
            if not chunk:
                break
            size += len(chunk)
            if size > LIMIT:
                answer({'status': 0, 'error': 'too-large'})
                return
            chunks.append(chunk)
    answer({'status': status, 'retryAfter': retry}, b''.join(chunks))


def main():
    try:
        raw = sys.stdin.buffer.read(REQUEST_LIMIT + 1)
        request = json.loads(raw) if len(raw) <= REQUEST_LIMIT else None
        if not isinstance(request, dict):
            raise ValueError
    except ValueError:
        answer({'status': 0, 'error': 'request'})
        return
    try:
        fetch(request)
    except Exception:
        # Never print a traceback: it could include request details.
        answer({'status': 0, 'error': 'network'})


main()
