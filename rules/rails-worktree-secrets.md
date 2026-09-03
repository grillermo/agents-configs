In a Ruby on Rails repo, when a command fails because an untracked secret file is missing —
`config/master.key`, `config/credentials/*.key`, `.env`, `.env.local`, `.env.*.local` — and that
failure is what blocks the test suite or the server, check whether you are in a linked git worktree
and copy the file from the main worktree instead of asking the user for it.

Typical failing signals: `ActiveSupport::MessageEncryptor::InvalidMessage`, `Missing encryption key
to decrypt file with`, `Rails master key is missing`, or a `KeyError`/`nil` on an `ENV` lookup that
the main checkout resolves fine.

## Steps

1. Confirm it is a linked worktree — in one, the two paths differ:
   `[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]`
2. Find the main worktree root: `git worktree list | head -1 | awk '{print $1}'`
3. Copy only the specific files that are missing here and that exist there. Preserve the relative
   path (`config/master.key` → `config/master.key`).
4. Re-run the command that failed to confirm it was the actual blocker.

## Rules

- Only copy files that are **missing** locally. Never overwrite an existing key or `.env` — a
  worktree may intentionally carry different values.
- Only copy files git ignores. If the file is tracked, something else is wrong; investigate instead.
- Never `git add` or commit a copied secret.
- Never generate, guess, or reconstruct a key. If it is not a worktree, or the main worktree does
  not have the file either, stop and tell the user which file is missing and where you looked.
- Say which files you copied and from where.
