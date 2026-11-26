#!/usr/bin/env python3
"""Fetch one GitHub REST response via gh; cache it and print a readable view."""
import argparse
import base64
import datetime
import json
import re
import subprocess
import tempfile
from pathlib import Path


def split_response(raw):
    """Separate gh --include headers without modifying the response body."""
    status, headers = None, {}
    while re.match(rb"HTTP/\S+ \d{3}", raw):
        boundary = re.search(rb"\r?\n\r?\n", raw)
        if boundary is None:
            break
        lines = raw[:boundary.start()].decode("utf-8", "replace").splitlines()
        status = int(lines[0].split()[1])
        headers = {}
        for line in lines[1:]:
            key, sep, value = line.partition(":")
            if sep:
                key = key.lower()
                headers[key] = ", ".join(filter(None, [headers.get(key), value.strip()]))
        raw = raw[boundary.end():]
        if status >= 200:
            break
    return status, headers, raw


def request(endpoint, params, accept="application/vnd.github.text-match+json"):
    command = ["gh", "api", "--method", "GET", "--include", "-H", f"Accept: {accept}", endpoint]
    for param in params:
        command.extend(["-f", param])
    meta = {"started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    try:
        result = subprocess.run(command, capture_output=True, timeout=90)
        status, headers, body = split_response(result.stdout)
        stderr = result.stderr.decode("utf-8", "replace").strip()
        failed = result.returncode != 0 or (status is not None and status >= 400)
        meta.update(status=status, headers=headers, exit_code=result.returncode,
                    error=(stderr or f"GitHub request failed: HTTP {status}") if failed else None)
        if stderr:
            meta["stderr"] = stderr
        return meta, body
    except (OSError, subprocess.TimeoutExpired) as exc:
        meta.update(status=None, headers={}, exit_code=None, error=str(exc))
        return meta, getattr(exc, "stdout", None) or b""


def records(data):
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for key in ("items", "tree"):
            if isinstance(data.get(key), list):
                return data[key]
        return [data]
    return [data] if data is not None else []


def present(record):
    """Select useful fields, without ranking results or shortening field values."""
    if not isinstance(record, dict):
        return record
    if "repository" in record and "path" in record:
        return {"repository": record["repository"].get("full_name"), "path": record["path"],
                "url": record.get("html_url"),
                "snippets": [m.get("fragment") for m in record.get("text_matches", [])]}
    if "full_name" in record:
        return {key: record.get(key) for key in ("full_name", "html_url", "description", "fork")}
    if "commit" in record and "sha" in record:
        return {"sha": record.get("sha"), "url": record.get("html_url"),
                "message": record["commit"].get("message")}
    if "encoding" in record or "download_url" in record:
        return {key: record.get(key) for key in
                ("name", "path", "type", "size", "sha", "html_url", "download_url", "encoding")}
    return record


def fetch(endpoint, params, run_dir=None):
    if run_dir is None:
        run_dir = Path(tempfile.mkdtemp(prefix="run-", dir=Path.cwd()))
    run_dir = Path(run_dir).expanduser().resolve()
    cache = run_dir / "cache"
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix="request-", suffix=".json", dir=cache, delete=False) as f:
        saved = Path(f.name)

    response, body = request(endpoint, params)
    record = {"request": {"method": "GET", "endpoint": endpoint, "params": params},
              "response": response}
    try:
        data = json.loads(body)
        record["body"] = data
    except (ValueError, UnicodeError) as exc:
        data = None
        record["body_text"] = body.decode("utf-8", "replace")
        response["error"] = response["error"] or f"Invalid JSON response: {exc}"

    downloaded = None
    file_error = None
    if not response["error"] and isinstance(data, dict):
        name = Path(data.get("name") or data.get("path") or endpoint.rstrip("/")).name
        destination = cache / f"{saved.stem}-{name or 'content'}"
        try:
            if data.get("encoding") == "base64":
                content = base64.b64decode("".join(data["content"].split()), validate=True)
                destination.write_bytes(content)
                downloaded = str(destination)
            elif data.get("type") == "file" and data.get("encoding") == "none":
                # The Contents API omits inline data for larger files. Fetch only this file.
                download, content = request(endpoint, params, "application/vnd.github.raw+json")
                record["download"] = download
                if download["error"]:
                    file_error = download["error"]
                else:
                    destination.write_bytes(content)
                    downloaded = str(destination)
        except (ValueError, KeyError, TypeError, OSError) as exc:
            file_error = f"Could not save file: {exc}"
    if downloaded:
        record["file"] = downloaded
    if file_error:
        record["file_error"] = file_error
    saved.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    info = data if isinstance(data, dict) else {}
    next_link = re.search(r'<([^>]+)>;\s*rel="next"', response["headers"].get("link", ""))
    summary = {"run_dir": str(run_dir), "cache": str(saved), "endpoint": endpoint,
               "params": params, "status": response["status"],
               "count": len(records(data)) if not response["error"] else 0,
               "total_count": info.get("total_count"),
               "incomplete_results": info.get("incomplete_results"),
               "tree_truncated": info.get("truncated"),
               "next_page": next_link.group(1) if next_link else None,
               "file": downloaded, "error": response["error"] or file_error}
    return summary, data


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("endpoint", help="Relative GitHub REST endpoint, e.g. search/code")
    parser.add_argument("--param", action="append", default=[], metavar="KEY=VALUE",
                        help="Literal gh -f parameter; repeat for query, page, ref, etc.")
    parser.add_argument("--run-dir", type=Path,
                        help="Reuse a run directory; omitted: create run-* in the current directory")
    args = parser.parse_args(argv)
    endpoint = args.endpoint.lstrip("/")
    if not endpoint or "://" in endpoint or endpoint.startswith("-") or endpoint.split("?")[0] == "graphql":
        parser.error("Use a relative REST endpoint; this helper only performs GET requests")
    if any("=" not in p or not p.split("=", 1)[0] for p in args.param):
        parser.error("Each --param must be KEY=VALUE")
    summary, data = fetch(endpoint, args.param, args.run_dir)
    # Paths and status precede potentially long result output. The cache remains complete.
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    if not summary["error"]:
        for i, item in enumerate(records(data), 1):
            print(f"[{i}] {json.dumps(present(item), ensure_ascii=False)}")
    return 1 if summary["error"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
