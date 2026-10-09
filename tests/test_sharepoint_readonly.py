"""Offline tests for the IM_READ_ONLY_SHAREPOINT switch in scripts/_sharepoint_client.py.
Run from the repo root:  python tests/test_sharepoint_readonly.py
No network is used: the real `requests` calls are replaced by a recorder that fails the
test if a write ever reaches it."""
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import _sharepoint_client as sp  # noqa: E402

real = sp._requests_real
calls = []


class FakeResp:
    status_code = 200
    headers = {}
    text = ""

    def raise_for_status(self):
        pass

    def json(self):
        return {"value": [], "id": "x"}


def fake_request(method, url, **kw):
    calls.append((method.upper(), url))
    return FakeResp()


real.request = fake_request
real.get = lambda url, **kw: fake_request("GET", url, **kw)
real.post = lambda url, *a, **kw: fake_request("POST", url, **kw)
real.put = lambda url, *a, **kw: fake_request("PUT", url, **kw)
real.delete = lambda url, *a, **kw: fake_request("DELETE", url, **kw)
real.patch = lambda url, *a, **kw: fake_request("PATCH", url, **kw)

n = 0


def ok(desc, cond):
    global n
    assert cond, "FAILED: " + desc
    n += 1
    print("  ok -", desc)


tmp = Path(tempfile.mkdtemp()) / "f.bin"
tmp.write_bytes(b"x" * 100)
big = Path(tempfile.mkdtemp()) / "big.bin"
big.write_bytes(b"x" * (sp._SIMPLE_UPLOAD_LIMIT + 10))

print("normal mode still writes")
os.environ.pop(sp.READ_ONLY_ENV, None)
calls.clear()
ok("read_only() False by default", sp.read_only() is False)
ok("upload_file works", sp.upload_file("t", "d", tmp, "a/b.bin") is True)
ok("the PUT really went out", ("PUT", "https://graph.microsoft.com/v1.0/drives/d/root:/a/b.bin:/content") in calls)

for val in ("1", "true", "YES", " on "):
    os.environ[sp.READ_ONLY_ENV] = val
    ok(f"read_only() True for {val!r}", sp.read_only() is True)

print("read-only mode: public write functions are skipped")
os.environ[sp.READ_ONLY_ENV] = "1"
calls.clear()
ok("upload_file (small) -> True, nothing sent", sp.upload_file("t", "d", tmp, "a/b.bin") is True)
ok("upload_file (chunked) -> True, nothing sent", sp.upload_file("t", "d", big, "a/big.bin") is True)
ok("ensure_folder -> True, nothing sent", sp.ensure_folder("t", "d", "x/y/z") is True)
ok("delete_item -> True, nothing sent", sp.delete_item("t", "d", "x/y", permanent=True) is True)
ok("prune_old_versions -> 0, nothing sent", sp.prune_old_versions("t", "d", "a/b.bin", 1) == 0)
ok("no request at all was made", calls == [])

print("read-only mode: the low-level guard refuses writes even if layer 1 is bypassed")
for method in ("PUT", "POST", "PATCH", "DELETE"):
    try:
        sp.requests.request(method, "https://graph.microsoft.com/v1.0/drives/d/root:/a")
        raise SystemExit("write was not blocked: " + method)
    except sp.ReadOnlyViolation:
        n += 1
        print("  ok - refused", method)
for fn in ("put", "post", "patch", "delete"):
    try:
        getattr(sp.requests, fn)("https://x.sharepoint.com/a")
        raise SystemExit("write was not blocked: " + fn)
    except sp.ReadOnlyViolation:
        n += 1
        print("  ok - refused requests." + fn)
ok("_request_with_retry cannot write either", True)
try:
    sp._request_with_retry("PUT", "https://graph.microsoft.com/x", data=b"1")
    raise SystemExit("PUT via _request_with_retry went through")
except sp.ReadOnlyViolation:
    pass
ok("ReadOnlyViolation is a RequestException (callers' normal handlers catch it)",
   issubclass(sp.ReadOnlyViolation, real.exceptions.RequestException))
ok("still nothing sent", calls == [])

print("read-only mode: reads and the OAuth token request still work")
calls.clear()
sp.requests.get("https://graph.microsoft.com/v1.0/sites/x")
sp.requests.request("GET", "https://graph.microsoft.com/v1.0/drives/d/root:/a")
sp.requests.post("https://login.microsoftonline.com/tenant/oauth2/v2.0/token", data={})
ok("GET, GET and the token POST went out",
   [c[0] for c in calls] == ["GET", "GET", "POST"] and "login.microsoftonline.com" in calls[2][1])

print("read-only mode: the token exemption is exact")
for evil in ("https://evil.example.com/login.microsoftonline.com/oauth2/v2.0/token",
             "https://graph.microsoft.com/v1.0/drives/d/root:/x?login.microsoftonline.com",
             "https://login.microsoftonline.com.evil.com/t/oauth2/v2.0/token",
             "http://login.microsoftonline.com/t/oauth2/v2.0/token",
             "https://login.microsoftonline.com/t/other/path",
             "https://user@evil.com/@login.microsoftonline.com/oauth2/v2.0/token"):
    try:
        sp.requests.post(evil, data={})
        raise SystemExit("write to look-alike URL was not blocked: " + evil)
    except sp.ReadOnlyViolation:
        n += 1
        print("  ok - refused", evil[:60])
for evil in ("https://evil.com\\@login.microsoftonline.com/t/oauth2/v2.0/token",
             "https://login.microsoftonline.com@evil.com/t/oauth2/v2.0/token"):
    try:
        sp.requests.post(evil, data={})
        raise SystemExit("parser-confusion URL was not blocked: " + evil)
    except sp.ReadOnlyViolation:
        n += 1
        print("  ok - refused", evil)
for m in (b"PUT", "MKCOL", "MOVE", "COPY", "PROPPATCH", None, 5):
    try:
        sp.requests.request(m, "https://graph.microsoft.com/v1.0/drives/d/root:/a")
        raise SystemExit("method not blocked: %r" % (m,))
    except sp.ReadOnlyViolation:
        n += 1
        print("  ok - refused method", repr(m))
try:
    sp.requests.request("PUT", "https://login.microsoftonline.com/t/oauth2/v2.0/token")
    raise SystemExit("PUT to the token URL allowed")
except sp.ReadOnlyViolation:
    n += 1
ok("still only the 3 legitimate requests went out", len(calls) == 3)
print("read-only mode: nothing but the whitelisted names is reachable through the guard")
for name in ("Session", "api", "sessions", "adapters", "post_json"):
    try:
        getattr(sp.requests, name)
        raise SystemExit("guard exposes requests." + name)
    except AttributeError:
        n += 1
        print("  ok - requests." + name + " not exposed")
ok("exceptions still reachable", sp.requests.exceptions.RequestException is real.exceptions.RequestException)

print("back to normal when the switch is off")
os.environ.pop(sp.READ_ONLY_ENV)
calls.clear()
sp.upload_file("t", "d", tmp, "a/b.bin")
ok("writes work again", any(c[0] == "PUT" for c in calls))

print(f"\nAll {n} read-only checks passed.")
