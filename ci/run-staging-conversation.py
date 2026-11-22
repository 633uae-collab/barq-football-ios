"""Run ten private questions against PR 7 staging after confirming provider availability."""
import argparse
import json
import http.client
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

STAGING_CHAT = "https://fotiq-analyst-pr7-staging-k276.onrender.com/api/analyst/chat"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def wire_history(turns):
    messages = []
    for question, answer in turns[-4:]:
        for role, value in (("user", question), ("assistant", answer)):
            prefix = value.encode("utf-16-le")[:2000].decode("utf-16-le", errors="ignore")
            messages.append({"role": role, "content": prefix})
    while len(json.dumps(messages, ensure_ascii=False, separators=(",", ":")).encode()) > 18000:
        del messages[:2]
    return messages


def record_run(questions, log, opener, sleep=time.sleep):
    turns, context = [], {}
    for index, question in enumerate(questions, 1):
        if index > 1:
            # The server starts its clock at admission. A previous client's send
            # timestamp may precede that admission by several seconds.
            sleep(66)
        body = {"question": question, "history": wire_history(turns), "context": context}
        request = urllib.request.Request(STAGING_CHAT, data=json.dumps(body, ensure_ascii=False).encode(),
                                         headers={"Content-Type": "application/json"}, method="POST")
        started = datetime.now(timezone.utc).isoformat()
        entry = {"index": index, "started": started, "request": body}
        try:
            try:
                response = opener.open(request, timeout=180)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                status = response.status
                raw = response.read()
                try:
                    reply = json.loads(raw)
                except (ValueError, UnicodeDecodeError):
                    reply = None
                entry.update(status=status, limitOrigin=response.headers.get("FOTIQ-Rate-Limit-Origin"),
                             retryAfter=response.headers.get("Retry-After"), response=reply)
        except (OSError, http.client.HTTPException) as error:
            status, reply = None, None
            entry.update(status=status, transportError=type(error).__name__)
        entry["finished"] = datetime.now(timezone.utc).isoformat()
        log.write(json.dumps(entry, ensure_ascii=False) + "\n")
        log.flush()
        if status != 200 or not isinstance(reply, dict) or not isinstance(reply.get("answer"), str) or not reply["answer"].strip():
            return False
        turns.append((question, reply["answer"]))
        context = reply.get("context") or {}
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("questions", type=Path, help="Private JSON array with five Arabic and five English questions")
    parser.add_argument("results", type=Path, help="New private JSONL file outside the checkout")
    args = parser.parse_args()
    questions = json.loads(args.questions.read_text())
    if not isinstance(questions, list) or len(questions) != 10 or not all(isinstance(q, str) and q.strip() and len(q.encode('utf-16-le')) <= 2000 for q in questions):
        parser.error("Expected ten non-empty questions of at most 1000 UTF-16 units each.")
    if args.results.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        parser.error("Choose a private results path outside the repository.")
    with os.fdopen(os.open(args.results, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w", encoding="utf-8") as log:
        complete = record_run(questions, log, urllib.request.build_opener(NoRedirect()))
    return 0 if complete else 1


if __name__ == "__main__":
    sys.exit(main())
