# NetworkInterfaceMenu

NetworkInterfaceMenu is a small macOS menu bar app for quickly changing network service priority.

It is useful when you frequently switch between Wi-Fi, iPhone USB tethering, Thunderbolt, or other adapters and do not want to open Network Settings each time.

## What It Does

- Shows the current default interface and gateway in the menu bar.
- Lists available macOS network services (device, status, IPv4).
- Moves the selected service to the top of service order.
- Nudges the selected service (off/on) so macOS re-evaluates routes.
- Optionally remembers your admin password in Keychain.

## Requirements

- macOS 13.0 or later
- Xcode Command Line Tools (`swiftc`)
- Admin privileges (required by `networksetup`)

Install command line tools if needed:

```bash
xcode-select --install
```

## Clone

```bash
git clone https://github.com/sayakghorai34/NetworkInterfaceMenu.git
cd NetworkInterfaceMenu
```

## Build And Run

```bash
chmod +x build.sh
./build.sh
```

Optional custom bundle identifier:

```bash
BUNDLE_ID=com.sayakghorai.NetworkInterfaceMenu ./build.sh
```

Build output:

- `build/NetworkInterfaceMenu.app`

## Install

Copy the app bundle to `/Applications` for a stable app path:

```bash
cp -R build/NetworkInterfaceMenu.app /Applications/
open /Applications/NetworkInterfaceMenu.app
```

## Usage

1. Click the menu bar icon.
2. Choose the interface you want to prioritize.
3. Enter admin password when prompted.
4. Optional: keep **Remember in Keychain** enabled to reduce repeated prompts.

Notes:

- Interfaces marked `No Gateway` are still selectable.
- If there is no usable route, macOS may keep another interface as default.
- You can check the ultimate route by running `route get default` in Terminal. The output should reflect the interface name
  ```bash
    route to: default
  destination: default
        mask: default
      gateway: 192.0.0.1
    interface: en7
        flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
  recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
        0         0         0         0         0         0      1280         0 
  ```

## Add At Login (macOS Settings)

This project does not manage login items in-app.

Add it manually in macOS:

1. Open **System Settings**.
2. Go to **General > Login Items**.
3. Under **Open at Login**, click `+` and select `/Applications/NetworkInterfaceMenu.app`.

## Project Governance

- Direct pushes to `main` are blocked by branch protection.
- Changes should come through pull requests.
- CI must pass before merge.
- Code owner approval is required.

## Security Model

- Privileged changes are executed through `sudo`.
- If enabled, the password is stored in Keychain as a generic password item.
- Current keychain constraints:
  - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  - `kSecAttrSynchronizable = false`
- You can remove stored credentials via **Forget Saved Admin Password** in the app menu.

For full security notes, see [SECURITY.md](./SECURITY.md).

## Troubleshooting

- **Selected interface is not becoming default**:
  - The interface may not have a valid route yet.
  - VPN, MDM policy, or routing rules can override service order.

- **Repeated password prompts**:
  - Re-save Keychain credentials, or clear them and retry.

## Project Files

- `main.swift`: app source
- `build.sh`: compile and bundle script
- `NetworkInterfaceMenu.icns`: app icon

## License

MIT License. See [LICENSE](./LICENSE).
