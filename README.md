# GearLever AppImage

Automated CI to build GearLever as a standalone AppImage.

## Why this AppImage?
GearLever is normally distributed as a Flatpak. This version allows you to run it as a standalone executable that can **manage and integrate other AppImages**, including itself!

## Usage
Download the AppImage, give it execution permissions, and run it.

### Self-Integration
One unique feature of this AppImage is that it can integrate itself into your system:
```bash
./GearLever-x86_64.AppImage --integrate-self
```
This will move the AppImage to your default folder and create a desktop entry using GearLever's internal logic.
