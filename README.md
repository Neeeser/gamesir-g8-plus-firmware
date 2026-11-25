# GameSir G8 Plus firmware

Research toward custom firmware for the original GameSir G8 Plus Bluetooth controller (not the G8 Plus MFi or G8 Galileo), so it works on iPhone with Xbox-style button prompts, analog triggers and lower latency over both USB-C and Bluetooth.

## Status

| Area | State |
|---|---|
| Wired modes on a Mac | Measured for all three modes; table below |
| Bluetooth modes | DualShock 4 mode measured; Android mode inspected but macOS creates no controller for it; Switch mode could not be paired: in red pairing mode (firmware 2.12) neither this Mac nor an iPhone found it in classic or LE scans |
| Firmware image and chip | JieLi pi32v2-family chip, exact part unknown. A community patcher decrypts firmware 2.20 and reflashes it over Bluetooth; only its author reports flashing a controller (see research). This unit ran 2.12 and now runs official 2.20 (confirmed over Bluetooth) |
| Changes to the controller | Official GameSir firmware 2.20 flashed from a Mac with `tools/flash.sh` (53 seconds over Bluetooth LE). No modified firmware yet |

## Wired modes as Apple's GameController framework sees them

Measured on macOS with `tools/controller-probe.swift`. iOS uses the same framework, so it is expected to classify each mode the same way; not yet checked on the phone.

| | Switch mode (red) | DualShock 4 mode (blue) | Xbox mode (green) |
|---|---|---|---|
| USB vendor:product | 057e:2009 (Nintendo Pro Controller) | 054c:09cc (Sony DualShock 4, second version) | 3537:1014 (GameSir's own vendor ID) |
| Name it reports | Pro Controller | Wireless Controller | Xbox 360 for Windows Controller |
| Protocol | HID, Nintendo Pro Controller report layout | HID, DualShock 4 report layout | Xbox 360 wired protocol (USB interface class FF, subclass 5D, protocol 01), plus a separate USB keyboard interface |
| Apple framework category | Switch Pro Controller | DualShock 4 | Not recognized: no driver loads and no controller appears |
| Button glyphs | Nintendo A/B/X/Y, ZL/ZR | PlayStation cross, circle, square, triangle | None |
| Analog triggers | No (ZL and ZR are buttons) | Yes | Not usable on Apple devices |
| Gyro (rotation rate) | Yes | Yes | Not usable on Apple devices |
| Rumble | Yes | Yes | Not usable on Apple devices |
| Input reports per second | 125 (every 8 ms) | 250 (every 4 ms) | Not measured |

DualShock 4 mode already gives analog triggers, gyro, rumble and twice the report rate of Switch mode. Its gap for this project is the PlayStation identity and glyphs.

Xbox mode uses the Xbox 360 wired protocol. Apple's framework supports Xbox One and Series controllers, which use a different protocol (GIP, interface subclass 47), so the existing Xbox mode does not work on iPhone.

## Bluetooth, DualShock 4 mode (blue)

Measured on macOS with `tools/controller-probe.swift`, `tools/ds4-extended-check.swift` and `tools/ds4-bt-interval-test.swift`.

| Item | Value |
|---|---|
| Identity | Sony 054c:05c4 (first DualShock 4), "DUALSHOCK 4 Wireless Controller", classic Bluetooth. Over USB the same mode claims the second DualShock 4 (054c:09cc) |
| Apple framework view | Same as USB: DualShock 4, PlayStation glyphs, analog triggers, motion, rumble |
| Report format | Short 10-byte reports (no motion data) until the host reads feature report 0x02; then full 78-byte reports with motion, like a real DualShock 4 |
| Report interval | One report every 15 ms (about 65 per second), with occasional 45 ms gaps. USB in the same mode: every 4 ms |
| Host-requested interval | Ignored. Requesting 1, 4 or 8 ms in output report 0x11 (the DualShock 4 setting Linux uses) left the interval at 15 ms |

Not yet known: whether the 15 ms comes from the controller's firmware or from the Bluetooth link this Mac negotiates, and what an iPhone gets.

## Bluetooth, Android mode (yellow)

Read with `tools/ble-inspect.swift` (read-only; built as an app by `tools/build-bt-app.sh` because macOS grants Bluetooth only to app bundles).

| Item | Value |
|---|---|
| Name | GameSir-G8+ |
| Transport | Bluetooth LE, advertises the HID service |
| Firmware revision | 02.0C (2.12) before the update; 02.14 (2.20) after it. The digits after the dot are hexadecimal |
| PnP ID | USB vendor 3537, product 1108, version 07db |
| Services | Device Information; HID (hidden by macOS); FF10 with FF11 and FF12, which the community patcher uses for firmware updates; 8650 with 865F and 8655, purpose unknown |

## Tools

The tools run on macOS with the Xcode command line tools. Bluetooth pairing uses `blueutil` from Homebrew.


- `tools/controller-probe.swift` prints how Apple's GameController framework classifies each connected controller, the glyph each button gets, and raw HID input reports per second: `swift tools/controller-probe.swift [seconds]`
- `tools/flash.sh <ota.bin>` checks a G8 Plus Bluetooth image's structure and checksums, then flashes it over Bluetooth LE from the Mac with `tools/g8-flash.swift` (the controller's own update protocol, ported from jun182/controller-mod-tool). Put the controller in Android mode (pairing button + A, yellow light) first. `tools/flash.sh --dry-run` connects and checks the update service without sending anything.
- `tools/build-bt-app.sh` and `tools/run-app.sh` build and run the Bluetooth tools as small apps, since macOS grants Bluetooth only to app bundles.
- `tools/ble-inspect.swift` lists a Bluetooth LE device's advertisement, services and readable values, without writing anything.
- `tools/ds4-extended-check.swift` reads DualShock 4 feature report 0x02 and shows whether the controller switches to full reports with motion.
- `tools/ds4-bt-interval-test.swift` requests DualShock 4 Bluetooth report intervals and measures the gaps between reports. The request lasts only for the current connection.
- `tools/build-blueutil-app.sh`, `tools/bt.sh` and `tools/pair-and-probe.sh` pair a controller with this Mac (macOS allows Bluetooth only to app bundles here, so `blueutil` runs inside one) and save a probe run.
- `tools/capture-usb-mode.sh` waits for the controller to reappear on USB under a new identity (each mode has its own) and saves its USB registry entry, report descriptors and a probe run to `captures/`. Captures stay out of Git because they contain serial numbers.

## Research

- [research/community-projects.md](research/community-projects.md): existing firmware patchers, chip and protocol research

## Legal

This repository holds original scripts and notes only. It does not contain GameSir firmware; scripts download it from GameSir's update server. GameSir, Xbox, PlayStation, Nintendo Switch and Steam are trademarks of their owners, and this project is not affiliated with or endorsed by them. Modifying controller firmware can leave the controller unusable.
