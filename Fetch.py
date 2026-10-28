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
import json
import sys
import time
import urllib.error
import urllib.request

LIMIT = 16 * 1024 * 1024
REQUEST_LIMIT = 4 * 1024 * 1024
DEADLINE = 20
CHUNK = 65536


class NoRedirect(urllib.request.HTTPRedirectHandler):
    # Never forward the token to another address.
    def redirect_request(self, *args):
        return None


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
