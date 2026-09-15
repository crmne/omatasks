# OmaTasks for Todoist

A native QML plugin for the Omarchy Quattro shell. Read README.md before changing behavior.

- Keep the panel compact and use Omarchy's fonts, colors, spacing, and controls. Today/Inbox/Upcoming are the header; Add task belongs at the bottom. List and Quick Add share Composer.qml.
- Use Todoist's API directly. Do not add a Todoist CLI, runtime Node/Python service, or web view.
- Treat task content, descriptions, labels, projects, and API responses as untrusted plain text. Never evaluate them or interpolate them into shell commands.
- Never log, commit, or include API tokens or real account data in screenshots. Generate preview assets with tools/render-preview and its sample service.
- Preserve request generation guards, command status checks, stable retry UUIDs, and per-field rollback. Completing recurring tasks must advance them through Todoist's close endpoint.
- Keep edits minimal: send only changed task fields and preserve recurring due dates. Day order and project sibling order are different; reordering must not move a task to another project, section, parent, or date.
- Shortcut changes must check conflicts and remove only this plugin's owned binding. Keep credentials in the private config directory and pass them through stdin when saving.
- Run node --test tests/*.test.cjs and omarchy plugin validate . for releases. Run ./tests/check-drag when list interaction changes, and inspect relevant views in Quickshell.
- Public releases must match manifest.json and immutable v<version> tags. Never move or replace a published tag.
