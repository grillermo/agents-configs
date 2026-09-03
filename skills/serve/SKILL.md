---
name: serve
description: Run the macOS Shortcut named "serve file" with a user-provided local file when the user invokes /serve.
---

# Serve

Use this skill when the user invokes `/serve {reference_to_file}` or explicitly asks
to run the macOS Shortcut named `serve file` with a local file.

## Workflow

1. Resolve the user's file reference to a single local file path.
2. If the reference is missing, ambiguous, or does not point to an existing regular file,
   ask for the file path instead of guessing.
3. Run:

   ```sh
   sh skills/serve/scripts/serve-shortcut.sh "<file-path>"
   ```

4. Report the Shortcut output if it prints one. If the Shortcut fails, include the
   command's error output and exit status.

Do not use this skill for directory serving unless the user later changes the Shortcut
contract.
