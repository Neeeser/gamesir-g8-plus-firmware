# G8 Companion

An iPhone and Mac app for testing a G8 Plus running this project's firmware. It shows what games see from the controller and saves each test as a JSON log, so builds can be compared.

| Screen | What it does |
|---|---|
| Test | A live drawing of the controller: every button lights up where it sits, the sticks move, the triggers fill. Lists inputs never pressed and presses that sent two inputs at once. Measures stick noise at rest, smallest movement and reach. |
| Measure | Time between updates (with every raw report on the Mac), stick return time, a full-screen flash for slow-motion button-to-screen video, and an idle power-off timer. |
| Logs | Saved results, with side-by-side comparison of two runs and sharing. |

From the controller, hold View and press LB or RB to switch screens.

## Build and install

Needs Xcode 27 and XcodeGen (`brew install xcodegen`).

1. `cp config.example.sh config.local.sh` at the repository root, and fill in your team ID, bundle ID prefix and iPhone ID.
2. Run one of:

```bash
app/scripts/build.sh test
```

```bash
app/scripts/build.sh mac
```

```bash
app/scripts/build.sh phone
```

`phone` installs the app on the iPhone in `config.local.sh` without opening it.

## Getting logs off the phone

Logs are in the app's Documents folder, visible in the Files app under G8 Companion. From a Mac:

```bash
xcrun devicectl device copy from --device <iPhone ID> --domain-type appDataContainer --domain-identifier <bundle ID> --source Documents/Logs --destination logs/
```
