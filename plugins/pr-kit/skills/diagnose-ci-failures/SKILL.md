---
name: diagnose-ci-failures
description: Diagnose CI failures for a PR using the GitHub CLI, extract error logs, and generate a plan to fix them. Use when the user asks to check CI status, pull CI issues, triage test failures, or investigate PR build failures.
---

# diagnose-ci-failures

Programmatically diagnose CI failures for a PR and generate a plan to fix them.

## Overview

This skill provides a deterministic workflow to check CI status for a PR, extract failure logs, analyze errors, and create a plan (not code changes) to resolve issues. The output is always a plan that can be reviewed before execution.

## Workflow

### 1. Verify PR exists for current branch

Get the current branch and check if a PR exists:

```bash
# Get current branch
git branch --show-current

# Check for PR
GH_PAGER=cat gh pr view <branch-name> --json number,title,url,state
```

If no PR exists, inform the user and stop. Do not create one from this skill.

### 2. Check CI status

Fetch the status of all CI checks:

```bash
GH_PAGER=cat gh pr view <branch-name> --json statusCheckRollup
```

Parse the output to identify:
- Completed checks vs. in-progress checks
- Successful checks
- Failed checks with their names and details URLs

If CI is still running, inform the user which checks have already failed or passed, highlight the checks that are still running, and suggest waiting for completion before diagnosis.

### 3. Extract failure logs

For each failed check, pull the logs using the run ID from the status check:

```bash
GH_PAGER=cat gh run view <run-id> --log-failed
```

Focus on extracting:
- Error messages and their locations (file paths, line numbers)
- Compilation errors (unused imports, type mismatches, etc.)
- Linting errors with specific rule names
- Test failure messages and stack traces
- Build failures and their root causes

### 4. Categorize errors

Group errors by type:
- **Formatting issues**: Formatter check failures
- **Linting issues**: Linter warnings/errors
- **Compilation errors**: Type errors, missing imports, signature mismatches
- **Test failures**: Failing tests with their names and failure reasons
- **Platform-specific issues**: Failures that occur on only one OS or runtime

### 5. Generate fix plan

Write a plan with:
- **Problem Statement**: Summary of failing checks
- **Current State**: What errors were found and where
- **Proposed Changes**: Specific fixes needed for each error category
- **Validation Steps**: Commands to verify fixes (the repository's own format, lint, and test commands)

## Important Notes

- **GitHub CLI paging**: Set `GH_PAGER=cat` on every `gh` invocation. The GitHub CLI does not support `--no-pager` as a global option; `GH_PAGER` and `PAGER` are its documented paging controls
- **Always create a plan first**: Never make code changes directly. Generate a plan for user review
- **Check test status in CI**: Even if tests fail locally, verify they passed in CI before flagging as issues
- **Unrelated test failures**: If tests passed in CI but fail locally, they may be environment-specific or flaky
- **Multiple error types**: Plan one category at a time (e.g., all lint errors before tests)

## Example Commands

**Get PR status with details:**
```bash
GH_PAGER=cat gh pr view --json number,title,state,statusCheckRollup
```

**Get logs from specific failed run:**
```bash
GH_PAGER=cat gh run view 12345678 --log-failed
```

**Check for specific error in logs:**
```bash
GH_PAGER=cat gh run view 12345678 --log-failed 2>&1 | grep -F -A 5 "<text of the error message>"
```
