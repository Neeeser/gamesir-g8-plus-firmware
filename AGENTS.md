# Working in this repo

Research and patch tooling for the original GameSir G8 Plus Bluetooth controller (not the G8 Plus MFi or G8 Galileo). The aim is firmware that iPhone and Mac recognize as an Xbox-style controller with analog triggers over USB and Bluetooth, with lower latency and fewer power-offs.

## Where things are

| Path | What it holds |
|---|---|
| `README.md` | What works, measured results, how to run the tools |
| `tools/` | Measurement, Bluetooth and firmware scripts |
| `research/` | Notes on community projects, protocols and Apple's controller support, with sources |
| `firmware/` | Downloaded GameSir images and anything built from them. Ignored by Git |
| `captures/` | Raw USB and Bluetooth captures. Ignored by Git |
| `third_party/` | Checkouts of other projects. Ignored by Git |
| `work/` | Built helper apps. Ignored by Git |

## Constraints

- GameSir's firmware is GameSir's copyright. Scripts download it from GameSir's update server and patch it locally; the images and patched builds never go into Git.
- Captures contain controller serial numbers and the host's registry, so they stay in `captures/`.
- macOS denies Bluetooth to command-line tools started from an agent session. Bluetooth tools run inside small app bundles built by `tools/build-bt-app.sh` and started with `tools/run-app.sh`.
- Separate measured results from guesses in the README and research notes, and say which Mac, iOS and firmware version a result came from.
- Read the source of community tools before running them, since some talk to the controller's update service.
- Flashing changes the controller. Each flash needs a known way back: the original GameSir image for this firmware version and a tested reflash path.
