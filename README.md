# Tue

`Tue` is a lightweight local host memo for individual developers on iOS/iPadOS 17+. It helps save, search, view, and copy server or host login details.

## V1 Scope

- Uses a host record model: hostname, IP address, port, host group, multiple login accounts, and notes.
- Supports multiple Profiles with create, rename, and switch flows.
- Supports exporting the current Profile as JSON and importing a Profile from JSON.
- Each Profile has independent host groups. Defaults are Development, Testing, Staging, Production, and Other. Groups can be added, renamed, and deleted within the current Profile.
- Supports filtering by host group and searching by hostname, IP, username, group, and notes.
- Shows same-name hosts across all groups in the current Profile from the host detail page.
- Supports adding, editing, and deleting hosts. Hostname, IP, and at least one account username are required; port defaults to `22`.
- Shows detail fields directly, and tapping a field copies it to the clipboard.
- Stores data in `hosts.json` under the app sandbox's Application Support directory. Example data is created on first launch.

## Explicit Non-Goals

- No Keychain, Face ID/Touch ID, encrypted storage, or security audit in v1.
- No full backup/restore, iCloud, or server sync. Import/export is limited to one Profile JSON at a time.
- No real SSH, database, or web console launchers.
- No team sharing, permissions, audit history, or multi-user system.
- Not intended to become a general-purpose password manager.

## Security Note

V1 intentionally stays lightweight and local. Passwords are stored as plain text in the local JSON file, so this is suitable for prototypes and low-risk personal use, not real high-sensitivity credentials.

## Verification

- After adding, editing, or deleting a host, the list, detail page, and persisted JSON should stay consistent.
- After restarting the app, Profiles, the selected Profile, and host data should be restored.
- The current Profile can be exported as JSON; importing Profile JSON should add a new Profile while preserving groups, hosts, and accounts.
- Search should match hostname, IP, any account username, host group, and notes.
- Host group filtering and sorting should prefer the current Profile's group order.
- Deleting a host group that is used by hosts should move those hosts to the fallback group.
- Required fields should block saving when empty; empty ports should be hidden on the detail page; one host can store multiple accounts.
- When a Profile contains multiple hosts with the same hostname, the detail page should show the same-name host list across groups and allow jumping to another matching host.
- Tapping a detail field should copy its value and show copy success feedback.
