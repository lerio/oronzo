#!/usr/bin/env python3
"""UserPromptSubmit hook — ask Jev whether the submitted message is underspecified.

This is the "every message goes through Jev first" request, wired the way the
System One API actually works: one typed Noul per message, judged by `jev-latest`,
with criteria spelled out — exp3's lesson is that a bare Noul without criteria is
a coin flip.

Contract, mirrored from secret-scan.sh's spirit but inverted in effect: this hook
must NEVER block or break a prompt. Every failure path (no key, network error,
unparseable response, API 4xx/5xx) exits 0 with no output at all. The prompt goes
through untouched; only a successful judgment adds anything.

The API key is read from TYPESAFE_API_KEY at run time and is never printed, logged,
or written anywhere — the same rule experiments/typesafe/ts.py follows.

Output (success only): hook JSON on stdout — a one-line systemMessage for the
user, and the same judgment as additionalContext for the model.

Test by hand (spends one real call):
    echo '{"prompt": "fix it"}' | /usr/bin/python3 .claude/hooks/jev-prompt.py
"""

import json
import os
import sys
import time
import urllib.request

API = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"
TIMEOUT = 8          # seconds; settings.local.json budgets the hook 10s
MAX_PROMPT = 8000    # keeps any single call's cost bounded on a huge paste

CONTEXT = (
    "The message was sent by the user to their coding agent (Claude Code), which "
    "is working in their software repository and can read files, run commands, "
    "and ask a clarifying question before acting."
)
INSTRUCTIONS = (
    "Does this message leave the coding agent without something it needs to act "
    "correctly — an ambiguous goal, a missing reference to a file, feature or "
    "value, unclear scope, or a decision that is really the user's to make?"
)
CRITERIA = {
    "true": "Acting on it correctly would require a guess about intent, scope, or "
            "a user-level choice, or it refers to something the agent cannot "
            "identify from the message or repository.",
    "false": "There is enough direction to proceed without asking. The work may "
             "be hard, but what is wanted is not ambiguous.",
}


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return

    prompt = payload.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        return
    prompt = prompt[:MAX_PROMPT]

    key = os.environ.get("TYPESAFE_API_KEY")
    if not key:
        return

    body = json.dumps({
        "state": {"message": prompt, "context": CONTEXT},
        "model": MODEL,
        "questions": {
            "underspecified": {
                "type": "noul",
                "instructions": INSTRUCTIONS,
                "criteria": CRITERIA,
            },
        },
    }).encode()

    started = time.perf_counter()
    try:
        request = urllib.request.Request(
            API,
            data=body,
            headers={
                "Authorization": "Bearer " + key,
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            probability = json.loads(response.read())["answers"]["underspecified"]["noul"]
        probability = min(1.0, max(0.0, float(probability)))
    except Exception:
        return

    elapsed_ms = round((time.perf_counter() - started) * 1000)

    json.dump({
        "systemMessage": f"Jev · p(underspecified) = {probability:.2f} · {elapsed_ms}ms",
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": (
                "Jev's judgment on the user's latest message (System One Noul, "
                f"underspecification check): p = {probability:.2f} on a 0-1 scale, "
                "where higher means the message more likely leaves the agent "
                "without something it needs to act correctly."
            ),
        },
    }, sys.stdout)
    print()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
