# GameSir G8 Plus (Bluetooth) firmware and iOS research: what exists

Research date 2026-11-25. CONFIRMED means I read it in the source, code or page. REPORTED means someone said it and I could not check it. No firmware was downloaded or run. Repo files were read through the GitHub API into a scratch folder.

## Bottom line

One project targets this exact controller and can already flash it: jun182/controller-mod-tool, three days old. It patches only the Android-mode Bluetooth path, which iOS does not use. Nothing found touches the DS4 or Switch Bluetooth paths an iPhone uses, except a one-day-old touchpad patch for DS4 mode. Nobody has patched the controller to look like an Xbox controller to iOS.

| Your want | Existing work | Status |
|---|---|---|
| Xbox glyphs and analog triggers on iOS | None. Reddit reports say Xbox-style input was dropped for licensing reasons. | Open |
| Lower Bluetooth latency | jun182 report-rate patch (27 to 115 reports/s), Android mode only | Does not apply to iOS paths |
| No random power-offs | Reported fixed by stock firmware 2.18 (users); jun182 builds on 2.20 | Likely already fixed |
| Home as Guide | Nothing | Open |
| Independent rear paddles | jun182 (L4 = BUTTON_C, R4 = BUTTON_Z), Android mode | iOS ignores Android mode (REPORTED) |
| Gyro | Nothing. Reports say DS4-mode gyro misbehaves on iOS; Switch mode gyro works | Open |

## 1. jun182/controller-mod-tool

- CONFIRMED: MIT license, created 2026-11-22, last commit 2026-11-24, one release (v0.2.0, 2026-11-22), 0 open issues, 1 star. https://github.com/jun182/controller-mod-tool
- CONFIRMED: supports G8+ Bluetooth firmware 2.20 only (app refuses any file that is not byte-identical to the official 2.20 zip; sha256 8e5d2d0c...) and G8+ MFi firmware 8900 (build-only).
- CONFIRMED: Linux only (curses, BlueZ `bluetoothctl`, Python 3.14+).
- CONFIRMED: firmware source. Optional download from `https://ota.xiaoji.com/download/g8-bluetooth-firmware-2.20.zip` (base64-hidden in `g8tui.py`; xiaoji.com is GameSir's parent company domain per the FCC grantee record). Or you supply the zip.
- CONFIRMED: format. Whole image is JieLi SFC-scrambled in 32-byte blocks (LFSR poly 0x1021, seed `0xA80F ^ (offset>>2)`). Decrypted offset 0 has three 32-byte entries (`app_area_head`, `app.bin`, `cfg_tool.bin`) with CRC16-XMODEM header and data CRCs. Runtime address = file offset + 0x1E00000. Image is 393,908 bytes.
- CONFIRMED: patching is by fixed offsets only. Each edit file is lines of `hex offset:hex bytes` into the decrypted image, verified against the exact stock hash. No signature search. Patches are hand-written pi32v2 machine code. The tool re-fixes CRCs, re-encrypts, and checks that nothing else changed.
- CONFIRMED: patches for G8+ BT (`mods/`): independent paddles (L4/R4 become Android BUTTON_C and BUTTON_Z), BLE report interval (`edits_interval.txt`, 18.75 ms to 7.5 ms), stick filter 1 off, stick filter 2 off (green/Android report builder only), screenshot button as Share, Android Back, or a keyboard key. MFi build adds Home-delay removal (and drops the Home+D-pad volume shortcut), stick averaging off.
- CONFIRMED: scope. The code comments say the second stick filter is for Android mode only and that the "BT Xbox" and "USB XInput" report builders have their own copies, untouched. Stick filter 1 sits in a shared function that runs every 8 ms for all four axes; whether DS4 and Switch modes share it is my inference, not stated. The interval patch is described by the Reddit author as BLE only, with DS4 mode being classic Bluetooth (REPORTED). The tool warns that faster input "can disturb DS4 mode if your phone is paired in both modes". Nothing patches Switch or DS4 report paths. No Guide, gyro or glyph work.
- CONFIRMED: flashing. Own ATT client on a raw L2CAP socket (BlueZ GATT breaks on the firmware's Service Changed). Service 0xFF10, control 0xFF11, data 0xFF12. Commands: 0x50 start (CRC16 + 24-bit size), 0x51 block size, 0x52 data blocks with offset acks, 0x53 finish. The code says no authentication. Flash takes about 2 minutes. Device name `GameSir-G8+` (Android mode); `GameSir-G8+_G` is the G-Touch/recovery mode.
- CONFIRMED: recovery. README says hold screenshot + Start about 1 s (blinking light blue) and re-flash with the GameSir phone app. The code says "Recovery is unknown; testing found the phone app can update a bad build via G-Touch". Author's testing was on a spare unit; 3 controllers total (2 G8+ BT, 1 MFi). No hardware-level (UBOOT) recovery documented for the G8+.
- CONFIRMED: warning in code that GameSir firmware "5.x" removes DS4 mode "for good". Source is the author's note only. I found no GameSir release note for it.
- Phone-home: CONFIRMED none beyond two user-triggered requests: the firmware download above, and one `api.github.com` release check. No accounts, no telemetry. Code is LLM-assisted (commit trailers name Claude); the author says so in the Reddit post.
- Reddit thread (r/EmulationOnAndroid, posted about 2026-11-23, 5 comments) read in full: https://old.reddit.com/r/EmulationOnAndroid/comments/1y33ywb/ . CONFIRMED author claims: latency comes from a 37.5 ms BLE interval plus two stick smoothing passes (24 ms + 8 ms); DS4 mode is classic Bluetooth at 6-10 ms. Comments: one offers a Windows port, one asks about X4. No one else reports flashing.
- Lineage: built on https://github.com/enij90/legion-g9-firmware (Lenovo G9, JieLi AC695X; no license file; patch bytes plus tools, no firmware).

## 2. xsyetopz/gamesir-fw and OpenJoystickDriver

- CONFIRMED: gamesir-fw (Unlicense, created 2026-09-29, pushed 2026-11-17) targets "JieLi AC695X" pads. Its catalog lists G7 SE, G7 HE, Cyclone 2 (and dongle), K1 Flux, Cyclone Pro dongle, universal dongle, Tarantula Pro dongle. No G8 or G8+. https://github.com/xsyetopz/gamesir-fw
- CONFIRMED: it flashes over USB using the JieLi GIP upgrade protocol (JSUD packets, XORed with JieLi keystream, commands C0 to CB, fragments of 52 bytes), read from `JL_Upgrade_Gip.dll`. It needs the pad to enumerate as an Xbox GIP interface (USB class ff/47/d0). Only a G7 SE has been flashed (recovered from a bad Nexus update on macOS). No flash-read command exists, so no backup this way. `docs/jieli-gip-protocol.md`.
- Relevance to the G8+: low. The G8+ BT is not in the catalog, its USB "Xbox" mode appears to be XInput rather than GIP (the code names "USB XInput"), and it is already flashable over BLE. Image decode there is chip-key based; the G8+ key is 0xA80F in jun182's code and in hieutran0413's script (two independent files agree).
- Phone-home: gamesir-fw downloads GameSir Flash Tool installers from `cdn.shopify.com` URLs and checks SHA-256 (CONFIRMED in catalog). I did not read the Nexus-extraction code path in depth.
- OpenJoystickDriver (MPL-2.0, macOS virtual gamepad driver) has VID 3537 records for other GameSir PIDs but nothing G8-specific. https://github.com/xsyetopz/OpenJoystickDriver

## 3. Chip in the original G8 Plus

- CONFIRMED: FCC ID 2AF9S-G8W covers "GameSir-G8+", "G8 Pro for Xbox" and "G8 Wireless". Applicant states they are electrically identical (same hardware and software). Granted 2024-07-02; BLE only (2402-2480 MHz), PCB antenna; manufacturer Dashine Electronics, Shenzhen. https://fccid.io/2AF9S-G8W
- CONFIRMED: I rendered the internal photos PDF (3 pages): two half-boards, a small USB-C board, and a thumbstick board. Chip markings are not readable at the filed resolution. Block diagram, schematic and parts list are filed confidential. https://fccid.io/2AF9S-G8W/Internal-Photos/Internal-photos-7448308.pdf
- Inference: the firmware uses the JieLi SFC scheme, `0x1E00000` XIP addresses and pi32v2 code (hieutran0413 calls its disassembler "PI32v2"), so the chip is a JieLi pi32v2 part, probably the BR23/AC695N family. The exact part number is not confirmed anywhere I found. The `G6470` in jun182's file header looks like a product code, not a chip.

## 4. Why wired Xbox mode fails on iOS, and what iOS accepts

- CONFIRMED: iOS 18 added native wired Xbox support through a driver that speaks Microsoft's GIP USB protocol (MacRumors, 2024-10-07; heise, 2024-10-14). https://www.macrumors.com/2024/10/07/ios-18-wired-xbox-controllers/
- REPORTED: wired Xbox 360 (XInput) pads work on macOS 15 (MacGeneration), and a MacRumors commenter says on iPad. A GP2040-CE maintainer said XInput on iPadOS 17.5 was not recognized while PS4 and Switch modes were (GitHub issue 1076; pre-iOS 18). So "XInput not supported" is not settled for iOS 18+. https://github.com/OpenStickCommunity/GP2040-CE/issues/1076
- REPORTED: a GameSir representative on Reddit says G8+ has no Xbox/XInput over Bluetooth because of a Microsoft partnership; unlicensed products cannot use it. GameSir's own FAQ says Bluetooth XInput is restricted by Microsoft. https://old.reddit.com/r/Gamesir/comments/1jun7py/ and https://gamesir.com/support/faq
- CONFIRMED (Reddit post, 2025): on iPhone 15 Pro Max the G8+ in USB-C wired mode defaulted to Switch mode, which worked. The post does not describe the wired Xbox mode failing; I found no source that explains it. https://old.reddit.com/r/Gamesir/comments/1j3rkiw/
- CONFIRMED: GameSir's iOS pairing instructions use DS4 mode ("DUOLSHOK 4 Wireless Controller"); iOS shows PlayStation glyphs (TechRadar, 2026-07-26). https://www.techradar.com/gaming/gamesir-g8-plus-bluetooth-review
- Glyph rules: CONFIRMED Apple's docs list profiles for Extended, DualShock, DualSense and Xbox, and iOS decides glyphs from the recognized controller identity (WWDC20 and WWDC21 videos). CONFIRMED in SDL source that identity comes from `GCController.productCategory` ("DualShock 4", "DualSense", "Xbox One"). A generic HID gamepad gets none of these: CONFIRMED in an Apple Developer Forums post (Sep 2026, iOS 27.0) where a generic BLE HID gamepad logs "Un-authenticated game controller device attached" and `GCController.controllers()` stays empty (no Apple answer). https://developer.apple.com/forums/tags/game-controller . Macs show the same filter for non-Xbox/PlayStation/Switch pads (steamac issue 68).
- REPORTED: Switch mode on iOS shows Nintendo glyphs; a blog post says the GameSir app can swap to an Xbox (BAXY) layout there, but TechRadar says the iOS app does not recognize the BT model. Contradiction, untested. Switch mode has no analog triggers or rumble (GameSir rep, Reddit). https://note.com/cia_note/n/n6d676a7763da
- REPORTED, unverified: one Reddit commenter says the controller paired in Android mode (name `GameSir-G8+`) gets an Xbox layout on iOS; another says Android mode connects but sends no input. Another mentions a hidden Xbox mode. Worth a test with a controller test app, not a basis for a plan.

## 5. MFi

- CONFIRMED: Apple's security guide says MFi accessories prove themselves with an Apple-supplied authentication IC (certificate plus signed challenge), invisible to the accessory's own code. https://support.apple.com/guide/security/verifying-accessories-sec70a4f377d/web . A 2022 teardown showed the coprocessor on an I2C bus next to the accessory CPU. So firmware alone cannot create MFi identity; it needs the chip's private key.
- REPORTED (YouTuber Game Tech Talk, 2025-12-21, transcript read): G8+ MFi detects an Apple host and uses the certified protocol only; the Bluetooth G8+ "spoofs" a first-party PlayStation or Xbox identity to get rumble. Single source. https://www.youtube.com/watch?v=HNRs-M3MPuc
- CONFIRMED: the MFi version has no battery, no Bluetooth, no gyro (Notebookcheck). jun182's MFi patches are for its Android/HID mode (USB 3537:0112), not what an iPhone sees. I found no Backbone One firmware or protocol reverse engineering.

## 6. Community reports

- Random shutdowns: Android 15 tablets/phones turned the controller off seconds after reconnecting; workaround was unpair/re-pair. Two users report firmware 2.18 fixed it (one thread edited 2026-03); one commenter said "same problem" about a month ago. https://www.reddit.com/r/Gamesir/comments/1k37v8j/ and https://www.reddit.com/r/Gamesir/comments/1s95idl/ (REPORTED). Mostly Android; I found no iPhone-specific shutdown thread.
- Latency: DS4 mode on iOS has noticeably more lag than an Xbox controller, Switch mode less lag but a low stick polling rate; a French comment mentions button flicker on iPhone 17 in Xbox Cloud Gaming. https://old.reddit.com/r/Gamesir/comments/1j3rkiw/ (REPORTED).
- Gyro: gyro "goes crazy" in DS4 mode under PS Remote Play on iPhone; fine in Switch mode on a Switch and in Moonlight. https://old.reddit.com/r/Gamesir/comments/1f6lw42/ . Another says gyro mostly works over USB-C but not Bluetooth on iOS. https://old.reddit.com/r/Gamesir/comments/1fp754u/ (REPORTED, 2024).
- Paddles and mode problems: DS4-mode Minus button acts like Capture on firmware 2.8 and 2.11 (thread 1j3rkiw).

## 7. Other projects

- hieutran0413/gamesir-g8-plus-touchpad-mod (no license, created 2026-11-22, one day of history): CONFIRMED patches DS4-mode firmware 2.20 so Capture or M or paddles send a touchpad click, for PS Remote Play on iPhone; claims iOS needs the 0x11 extended report with an active touch packet (REPORTED, LLM-assisted, untested by me). It is the only found work on the DS4 report path and lists exact patch addresses. Concerns: the repo commits GameSir firmware images, the decompiled GameSir Android app (dex and native libraries, including `libjl_ota_auth.so`), and a JieLi tools directory. It has no license. Its script makes no network calls (CONFIRMED). https://github.com/hieutran0413/gamesir-g8-plus-touchpad-mod
- quarkslab/ghidra-jieli (Ghidra pi32v2 processor, Apache-2.0 lineage from kagaimiq), jvitkauskas/pi32v2-isa (instruction table, CC0), Quarkslab blog 2026-03-12 on SFC key recovery, JieLi's public SDK (github.com/Jieli-Tech/fw-AC63_BT_SDK; toolchain emits readable objdump). https://github.com/quarkslab/ghidra-jieli
- kagaimiq/jl-uboot-tool (MIT; last push 2025-03): flash dump and write for JieLi chips through mask-ROM UBOOT. enij90 had to use an FTDI on the USB lines once. Padsquire (AGPL, Nova 2 Lite) triggers UBOOT through a HID command on its own pad; no equivalent known for the G8+. https://github.com/kagaimiq/jl-uboot-tool
- BlueRetro and GP2040-CE: not firmware for this pad. GP2040-CE shows PS4 and Switch USB modes work on iPad while XInput did not (2024).

## Open questions

1. Which exact JieLi part is in the G8+ (needs a physical teardown; FCC photos are too small).
2. What VID/PID and descriptor the G8+ presents in wired Xbox, Switch and DS4 modes, and what iOS does with each. A USB or Bluetooth identity capture would settle this and decide whether an Xbox-identity patch is plausible.
3. Whether iOS 27 recognizes an Xbox One S/Series Bluetooth identity (VID 045e) from a non-Microsoft device, and whether Microsoft's licensing terms apply to a personal patch.
4. Whether DS4/Switch modes share jun182's stick filter, and whether the interval patch has any effect outside Android mode.
5. Which firmware version the owner's unit runs; 2.18 reportedly fixes shutdowns, jun182 needs exactly 2.20.
6. Whether the GameSir iOS app can flash a local file (the touchpad repo assumes the Android app does).

## Search log (condensed)

GitHub API for the four repos plus tree and file reads; old.reddit.com threads 1y33ywb, 1j3rkiw, 1f6lw42, 1fp754u, 1jun7py; Google (via browser) for site:reddit.com shutdown threads, then threads 1k37v8j and 1s95idl; Exa searches on teardown/FCC, iOS wired Xbox, GP2040-CE, GameController identity, MFi, JieLi Ghidra, firmware changelogs; WebSearch on FCC ID, iOS wired Xbox, firmware 5.x; DuckDuckGo returned nothing (bot check); fccid.io PDF downloaded and rendered; GameSir FAQ and blog pages blocked by Cloudflare (read through Exa highlights instead); one YouTube transcript read. Not reached: GameSir Discord, X.com, the dated GameSir firmware changelog pages, the Reddit thread `Gamesir G8+ keeps disconnecting` and others in the Google list (only opened two).
