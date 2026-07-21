# Privacy and permissions

Syncorda requests **System Audio Recording** permission only when a user starts a process tap. That permission is required by macOS for any app-specific audio capture; it cannot be pre-granted by a CLI command.

Audio is kept in a short, in-memory ring buffer and rendered to the user-selected local Core Audio devices. Syncorda does not record to disk, send audio to a server, expose a network listener, or use analytics.

Profiles are stored as JSON in `~/Library/Application Support/Syncorda/profiles.json`. The local control service uses `/tmp/syncorda-<uid>.sock` and is scoped to the current macOS user.
