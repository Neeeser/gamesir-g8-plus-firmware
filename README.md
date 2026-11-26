# GameSir G8 Plus firmware

Research toward custom firmware for the original GameSir G8 Plus Bluetooth controller (not the G8 Plus MFi or G8 Galileo), so it works on iPhone with Xbox-style button prompts, analog triggers and lower latency over both USB-C and Bluetooth.

## Status

| Area | State |
|---|---|
| Wired modes on a Mac | Measured for all three modes. With a 4-byte patch, the wired Xbox mode works as an Xbox controller on Mac and iPhone |
| Bluetooth modes | DualShock 4 mode measured; Android mode inspected but macOS creates no controller for it; Switch mode could not be paired: in red pairing mode (firmware 2.12) neither this Mac nor an iPhone found it in classic or LE scans |
| Firmware image and chip | JieLi pi32v2-family chip, exact part unknown. A community patcher decrypts firmware 2.20 and reflashes it over Bluetooth; only its author reports flashing a controller (see research). This unit ran 2.12 and now runs official 2.20 (confirmed over Bluetooth) |
| Changes to the controller | Official GameSir firmware 2.20 flashed from a Mac with `tools/flash.sh` (about 55 seconds over Bluetooth LE), then 2.20 with `patches/usb-xbox360-id.txt` and `patches/bt-xbox-type4.txt` |

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

Xbox mode uses the Xbox 360 wired protocol. Apple's Xbox driver accepts that protocol only from Microsoft's Xbox 360 controller ID (045e:028e), so with GameSir's own ID the mode is not recognized.

## Patched wired Xbox mode (green)

`patches/usb-xbox360-id.txt` changes only the USB vendor and product ID that the wired Xbox mode announces, from GameSir's 3537:1014 to Microsoft's Xbox 360 controller, 045e:028e. Apple's built-in Xbox driver (`XboxGamepad.dext`, which matches the Xbox 360 wired protocol only for that ID) then takes the controller. Measured on macOS 27.2 with firmware 2.20 plus this patch:

| Item | Result |
|---|---|
| Driver | Apple `Xbox360Gamepad` |
| Apple framework category | Xbox One |
| Glyphs | A/B/X/Y, LB/RB, LT/RT, Menu, View, Xbox button |
| Analog triggers | Yes, 0 to 1.00 measured on both |
| Rumble | Yes: left, right and both sides felt with `tools/rumble-check.swift` |
| Gyro | No (the Xbox profile has none) |
| Reports per second | 500 (every 2 ms) |
| Button check (`tools/input-check.swift`) | Face buttons, bumpers, triggers, Menu, View, stick clicks and D-pad all arrive under the right names. Home opens the Games app |

On an iPhone (iOS 27) over USB-C it shows as an Xbox controller and works in games.

The Home button reaches the system: on macOS 27 it opens the Games app by default, which is why the test app did not see it. Apps can take it over through `GCControllerHomeButtonSettingsManager` (macOS 27, iOS 27), and macOS 27 adds a setting that turns the system action off.

Not yet checked: Windows (where the ID change makes Windows use its own Xbox 360 driver instead of GameSir's).

## Bluetooth Xbox mode

Firmware 2.20 contains classic-Bluetooth Xbox One S identities that no button combo selects (Bluetooth gamepad types 4 and 7). `patches/bt-xbox-type4.txt` points Home + Y (stock: Switch) at type 4, makes it claim the product ID that matches the reports it sends (045e:02e0), gives it a green light, gives it a Bluetooth address of its own, and gives it the same connect timeout as the DualShock 4 mode. Measured on macOS 27.2 with firmware 2.20 plus both patches:

| Item | Result |
|---|---|
| Identity | Microsoft 045e:02e0 over classic Bluetooth, named "Xbox Wireless Controller" |
| Apple framework category | Xbox One |
| Glyphs | A/B/X/Y, LB/RB, LT/RT, Menu, View, Xbox button |
| Button check (`tools/input-check.swift`) | Face buttons, bumpers, Menu, View, stick clicks and D-pad arrive under the right names. The rear paddles arrive as the stick clicks |
| Analog triggers | Yes, 0 to 1.00 on both |
| Sticks | Full range on both axes |
| Reports per second | About 63 (16-byte report 0x01) |
| Connection | Stayed connected through the button check |

To start it, turn the controller on and press Home + Y. A fast green blink means it is waiting to pair; a slow green blink means it is reconnecting to the last host it paired with. Holding the small button under the USB port for 2 seconds switches a slow blink to pairing. Once connected the light stays green.

Each Bluetooth mode has its own address, so a host keeps a separate pairing for each mode. The patch also changes the DualShock 4 mode's address (stock firmware gave it the same address as type 4), so a host that paired the DualShock 4 mode before this patch needs to pair it again.

Pair it from the host's Bluetooth settings. Pairing with `blueutil --pair` makes macOS drop the link just as the controller opens its input channel, and the controller then turns itself off.

Known gaps: not yet checked on iPhone, and no gyro, since the Xbox profile has none.

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
- `tools/flash.sh <ota.bin>` checks a G8 Plus Bluetooth image's structure and checksums, then flashes it over Bluetooth LE from the Mac with `tools/g8-flash.swift` (the controller's own update protocol, ported from jun182/controller-mod-tool). Put the controller in Android mode (Home + A, yellow light) first. `tools/flash.sh --dry-run` connects and checks the update service without sending anything.
- `tools/build-bt-app.sh` and `tools/run-app.sh` build and run the Bluetooth tools as small apps, since macOS grants Bluetooth only to app bundles.
- `tools/input-check.swift` prints every button press and the range each trigger and stick reaches, as Apple's framework reports them.
- `tools/hid-dump.swift <vendor-hex> [seconds]` prints the HID report descriptor and every distinct raw input report, for working out a report layout.
- `tools/ble-inspect.swift` lists a Bluetooth LE device's advertisement, services and readable values, without writing anything.
- `tools/ds4-extended-check.swift` reads DualShock 4 feature report 0x02 and shows whether the controller switches to full reports with motion.
- `tools/ds4-bt-interval-test.swift` requests DualShock 4 Bluetooth report intervals and measures the gaps between reports. The request lasts only for the current connection.
- `tools/build-blueutil-app.sh`, `tools/bt.sh` and `tools/pair-and-probe.sh` pair a controller with this Mac (macOS allows Bluetooth only to app bundles here, so `blueutil` runs inside one) and save a probe run.
- `tools/capture-usb-mode.sh` waits for the controller to reappear on USB under a new identity (each mode has its own) and saves its USB registry entry, report descriptors and a probe run to `captures/`. Captures stay out of Git because they contain serial numbers.

## Research

- [research/community-projects.md](research/community-projects.md): existing firmware patchers, chip and protocol research

## Legal

This repository holds original scripts and notes only. It does not contain GameSir firmware; scripts download it from GameSir's update server. GameSir, Xbox, PlayStation, Nintendo Switch and Steam are trademarks of their owners, and this project is not affiliated with or endorsed by them. Modifying controller firmware can leave the controller unusable.
