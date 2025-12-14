# Building the LaunchBar Action

This project uses Swift Package Manager to build the LaunchBar action bundle.

## Prerequisites

- macOS 13 or later
- Swift 5.9 or later
- LaunchBar 6.x

## Building

To build the LaunchBar action:

```bash
make build
```

This will:
1. Compile `main.swift` using Swift Package Manager in release mode
2. Assemble the LaunchBar action bundle at `.build/action/Swift Evolution.lbaction/`
3. Copy the compiled executable as `Contents/Scripts/main`
4. Copy `icon.png` to `Contents/Resources/`
5. Copy `Info.plist` to `Contents/`

The bundle structure will be:
```
.build/action/Swift Evolution.lbaction/
  Contents/
    Info.plist
    Scripts/
      main (compiled executable)
    Resources/
      icon.png
```

## Installing

To install the action to LaunchBar:

```bash
make install
```

This builds the action and copies it to `~/Library/Application Support/LaunchBar/Actions/`. You may need to restart LaunchBar or rescan actions for it to appear.

## Cleaning

To clean build artifacts:

```bash
make clean
```
