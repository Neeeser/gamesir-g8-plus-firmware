# Can the GameSir G8 Plus pose as Valve's 2026 Steam Controller?

Research date 2026-11-25. CONFIRMED means I read it in source, local files or a primary page. REPORTED means a person or secondary site said it and I could not check it. No firmware or binaries were downloaded or run. Valve's own docs for the 2026 controller were not reachable (Steam pages returned empty shells), so hardware facts come from SDL source, the Linux kernel patch and reviews.

## Answer

Probably not worth it, and it would not deliver what you want on its own.

- The protocol has no cryptographic lock that I could find, so a fake is possible in principle. Three projects already fake the USB identity from software or a microcontroller.
- Apple's GameController framework only knows the 2026 controller by USB (wired 0x1302 and the two dongles). It has no Bluetooth entry for it. Over Bluetooth, the controller is only usable by apps that talk to Valve's own Bluetooth service directly (Steam Link, SDL apps).
- Moonlight cannot see a Steam Controller at all, only what Apple's framework hands it.
- Your G8 Plus tooling patches fixed offsets in JieLi machine code. Adding a Valve Bluetooth service and answering Steam's handshake is a different class of work (my judgment, not sourced).

## 1. Hardware and connectivity

- CONFIRMED (SDL controller_list.h, usb_ids.h): vendor 0x28DE. Codename Triton (SDL name) / Ibex (Linux kernel name). PIDs: 0x1302 wired USB, 0x1303 Bluetooth LE, 0x1304 Proteus dongle (the "Puck"), 0x1305 Nereid dongle (Steam Machine). https://github.com/libsdl-org/SDL/blob/main/src/joystick/SDL_joystick.c ; Linux patch https://lore-kernel.gnuweeb.org/linux-input/20260807013334.2109386-3-vi@endrift.com/
- CONFIRMED: connects over USB-C, Bluetooth LE and the Puck. Bluetooth has the highest latency and Engadget calls it the phone and Steam Link route. https://www.engadget.com/gaming/valve-steam-controller-review-a-gamepad-in-search-of-a-console-170054068.html (2026-04-27)
- REPORTED: measured transport latency 7.3 ms button over Bluetooth vs 4.1 ms USB. https://controllergearhq.com/blog/bluetooth-controller-for-steam-link

## 2. Protocol

- CONFIRMED (SDL_hidapi_steam_triton.c, controller_structs.h): input report ID 0x42 (USB), 0x45 (Bluetooth), 0x47 (newer, with trackpad timestamp). Layout: seq byte, 32-bit button mask, two 16-bit triggers, two sticks (16-bit), two trackpads with pressure, IMU (accel and gyro, 16-bit each).
- Button bits: A,B,X,Y, QAM(...) button, View, Menu, Steam, L3, R3, L/R bumpers, d-pad, four back buttons (L4, R4, L5, R5), trackpad clicks, trigger click bits, stick and grip touch bits. SDL maps A to South, so layout is Xbox-like.
- Host sends a feature report every 3 s (lizard mode off, plus IMU on). If it stops, the controller falls back to keyboard and mouse. Rumble and haptics are output reports 0x80 to 0x85.
- CONFIRMED: no authentication in SDL's driver. There is a feature-report identity exchange (attributes, serial strings) that Steam performs before claiming a device. https://hidmaestro.org/specs.html (REPORTED, says Steam does a GET_REPORT interrogation first); https://github.com/Evimore/InputLine/blob/main/docs/architecture.md (REPORTED, says Steam identifies it by USB identity plus that handshake). Whether Steam's closed client checks anything more is unknown.
- Bluetooth, CONFIRMED (SDL src/hidapi/ios/hid.m): device name must start with "Steam"; service 100F6C32-1735-4313-B402-38567131E5F3; input notifications on 100F6C7A (0x45) and 100F6C7C (0x47); feature channel 100F6C34; each output report has its own characteristic whose UUID is 100F6C plus a number derived from the report ID. Valve's own Bluetooth HID (keyboard and mouse) profile sits alongside it.

## 3. Apple GameController

- CONFIRMED on this Mac (macOS 27.2, AppleGameControllerPersonality.kext Info.plist): "Steam Controller 2 Wired" 0x28DE:0x1302 and two dongle entries, all with GameControllerCategory "steamcontroller2". No entry for Bluetooth PID 0x1303. The Xbox 360 entry uses category "xbox".
- REPORTED: this support appeared in OS 27 beta 5 (2026-08-10) with a Steam2ControllerHIDServicePlugin; Apple published no release note. https://pdfu.dev/steam-controller ; https://9h41.fr/macos-27-steam-controller/
- REPORTED: on macOS 27 Steam lists a second, OS-made "Bluetooth" controller with an Xbox icon next to the real one. https://steamcommunity.com/discussions/forum/2/589561330618464280/
- Not found: which GameController buttons, glyphs, GCMotion, paddles or trackpads Apple exposes for it. Search of the dyld cache for the category string found nothing.
- REPORTED (The Verge, 2026-04-30, before iOS 27): over Bluetooth, most native iPhone games did not recognise it; Steam Link worked. https://www.theverge.com/games/921838/steam-controller-ios-together
- REPORTED (developer forum, iOS 27.0, unanswered): a generic Bluetooth gamepad was rejected with "Un-authenticated game controller device attached" and never reached GCController. One report, no Apple reply. https://developer.apple.com/forums/tags/game-controller

## 4. Steam Link and Moonlight

- Moonlight iOS, CONFIRMED in source: it only reads GCController. Type is Xbox if the profile is GCXboxGamepad, PlayStation if DualShock or DualSense, otherwise unknown. Paddles only via GCInputXboxPaddleOne to Four. Motion only if GCController.motion exists. https://github.com/moonlight-stream/moonlight-ios/blob/master/Limelight/Input/ControllerSupport.m
- Sunshine, CONFIRMED docs: gamepad = auto picks the virtual pad from the client's report; with motion_as_ds4 and touchpad_as_ds4 on (both default), a client with motion becomes a PlayStation pad, so PlayStation glyphs. Forced types: x360, xone, xseries, ds4, ds5, switch, generic. Forcing Xbox drops motion from selection. https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html . That Apollo behaves the same is an assumption (it is a Sunshine fork).
- Steam Link iOS: gyro added only for DualShock and DualSense (version 1.3.30, 2026-05-29). https://apps.apple.com/us/app/steam-link/id1246969117 . A Valve developer said the OS does not pass Xbox Elite 2 paddles to apps (tvOS, 2026-06-23). https://steamcommunity.com/app/353380/discussions/7/570415649310071130/
- Steam Link reads the real Steam Controller itself over Bluetooth (needs the Bluetooth permission, same Valve developer, 2026-07-09). Per InputLine's docs it tunnels raw reports to the host, so the host sees a real Steam Controller (REPORTED; mechanism named k_EStreamControlRemoteHID). Moonlight gets none of this.
- Existing workaround, REPORTED: InputLine (public beta, 2026-09) reads the controller over Bluetooth on the iPhone and presents a virtual 28DE:1302 to host Steam, next to unmodified Moonlight. https://github.com/Evimore/InputLine

## 5. Steam Input on the host

- CONFIRMED (Valve docs): Steam Input emulates an Xbox pad to games and can bind Switch, PlayStation and Steam Controller gyro to mouse. https://partner.steamgames.com/doc/features/steam_controller/steam_input_gamepad_emulation_bestpractices
- Secondary sources agree that an Xbox identity gives no gyro, and that paddles on Xbox pads usually mirror face buttons so Steam does not see them as separate inputs; only Steam Controller identity exposes all four back buttons independently (REPORTED). https://controllergearhq.com/blog/controller-on-steam-setup

## 6. Prior art

- CONFIRMED: OpenPuck, nRF52840 firmware posing as the Puck (28DE:1142 or 1304); the same board can instead pose as Xbox 360, Switch Pro, DualSense or DS4, with back buttons mappable. Heavily LLM-written by its own README. https://github.com/safijari/openpuck
- CONFIRMED: HIDMaestro and PadForge create software USB personas of 28DE:1302 that live Steam claimed (PadForge's own bench claim). https://hidmaestro.org/specs.html ; https://padforge.org/docs/features/controller-slots/
- CONFIRMED: InputLine exports a virtual 28DE:1302 over USB/IP. Deck as Controller makes a Steam Deck pose as a Steam Controller (2026) over Bluetooth Classic, working in Steam on Mac and Linux (REPORTED by its README, 1 author). https://github.com/jmedina21/deck-as-controller
- Opposite direction: lilphil's 2015 Steam Controller radio firmware that poses as Xbox; sc26re open firmware for the real 2026 controller. No GP2040-CE or BlueRetro project fakes a Steam Controller (searched; absence is not proof).
- Not found: any cheap Bluetooth gamepad running Valve's GATT service.

## Open questions

1. What GameController profile (glyphs, GCMotion, paddles) does Apple's steamcontroller2 category give on iOS 27? Needs a real controller on an iPhone.
2. Does iOS 27 admit the Bluetooth controller (PID 0x1303) natively? macOS 27.2 shows no entry.
3. Does Steam's closed client check anything beyond the handshake?
4. Does GameSir's Bluetooth chip have room for a second GATT service?

## Recommendation

| Identity | iOS native games | Steam Link | Moonlight + Sunshine/Apollo |
|---|---|---|---|
| Xbox 360 USB (045e:028e) | Xbox glyphs, analog triggers. No gyro, no back buttons. USB only. | Xbox pad, no gyro or paddles | Xbox pad, no gyro or paddles |
| Xbox Series or Elite, Bluetooth | Xbox glyphs, analog triggers, paddles via GCInputXboxPaddle. No gyro (no sensor in the real pad) | Gyro none. Paddles not passed by iOS or tvOS (Valve dev) | Paddle flags sent, host paddle support depends on forced type (unverified). No gyro |
| DualSense or DS4 | PlayStation glyphs, gyro, triggers, touchpad. No back buttons | Gyro yes (1.3.30). PlayStation glyphs | Gyro yes, host becomes PlayStation pad, PlayStation glyphs |
| Steam Controller 2, USB | Apple has an entry; feature set unknown | Unknown through GCController. Steam Link only passes raw reports for its own Bluetooth path | Only what Apple exposes; unknown |
| Steam Controller 2, Bluetooth | Not admitted by Apple (macOS shows no entry; Verge) | Full Steam Input, but needs Valve's GATT service and handshake | Nothing, unless InputLine runs beside it |

Best realistic target without reverse-engineering Valve: pick DS4 or DualSense identity for gyro and accept PlayStation glyphs, or Xbox identity for glyphs and accept no gyro. Getting all four wants the Valve identity plus InputLine or Steam Link, which is a much bigger firmware job than anything done on the G8 Plus so far.
