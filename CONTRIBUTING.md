# Contributing to Macness

Macness should remain a small local verification tool with clear evidence and explicit failure modes. It is not a replacement for UI test frameworks or a general automation platform.

1. Keep process targeting explicit: accept a bundle identifier or PID.
2. Keep snapshot artifacts structured and useful outside the current terminal.
3. Bound long-running work such as logs, monitoring, and captures.
4. Treat accessibility and screen-capture permissions as runtime dependencies, not assumptions.
5. Add focused Swift tests for parsing, models, or runtime behavior you change.

Run:

```sh
swift test
```

Do not commit `.build/` or `.macness/` output. If a change needs manual macOS verification, include the command and a concise description of the generated evidence in the pull request.
