---
name: upload
description: Upload a user-provided local file through the macOS "Upload to S3" Shortcut when the user invokes /upload or asks to upload a file to S3 with that Shortcut.
---

# Upload

Use this skill when the user invokes `/upload {reference_to_file}` or explicitly asks to
upload a local file through the macOS Shortcut named `Upload to S3`.

## Workflow

1. Resolve the user's file reference to a single local file path.
2. If the reference is missing, ambiguous, or does not point to an existing regular file,
   ask for the file path instead of guessing.
3. Run:

   ```sh
   sh skills/upload/scripts/upload-to-s3-shortcut.sh "<file-path>"
   ```

4. Report the Shortcut output if it prints one. If the Shortcut fails, include the
   command's error output and exit status.

Do not use this skill for directory uploads or cloud-to-cloud transfers unless the user
has provided a local file that the Shortcut can receive as input.
