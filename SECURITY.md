# Security Policy

## Scope

This repository contains:
- Benchmark scripts (shell, Python)
- Static dashboard HTML/JS
- Benchmark result data (CSV, JSON, JSONL)
- Model registry metadata

There is no server, no authentication, no user data, and no network calls in the benchmark runtime.

## Reporting a vulnerability

If you find a security issue in the benchmark scripts or dashboard:

1. **Do not** open a public GitHub issue.
2. Contact the maintainer directly via GitHub.
3. Include a description of the issue and steps to reproduce.

We will respond within 7 days and issue a fix or workaround as appropriate.

## What is NOT in scope

- The Android application that uses these benchmarks is maintained separately in a private repository.
- Model weights are not stored in this repository.
- No user financial data is ever stored, transmitted, or referenced in this repo.
