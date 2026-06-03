# Security Policy

## Supported code

Security fixes are made on the latest `main` branch.

## Reporting vulnerabilities

Please report security issues privately first (GitHub private advisory preferred).

Do not open a public issue for vulnerabilities that could expose users.

## Security boundaries in this project

- Privileged operations are required for network service ordering (`networksetup`).
- Service names are shell-quoted before they are passed to command execution.
- Optional credential storage uses macOS Keychain.

## Keychain details

When password saving is enabled, credentials are stored with these constraints:

- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- `kSecAttrSynchronizable = false`

This means the saved password is local to the current device and available only while unlocked.

## Known tradeoff

Saving an admin password is a convenience/security tradeoff. If your environment has stricter requirements, do not enable password saving.

## Operational recommendations

- Run the app from `/Applications`.
- Clear saved credentials when using shared machines.
- Keep macOS updated.
