# GodotMultiplayerDemo

This is a simple 3D multiplayer game developed in Godot Engine 4.3. It provides a basic structure for a multiplayer setup, where each player has a nickname displayed above their character and the option to choose from four different skins: red, green, blue, or yellow.

It uses HearMeCheer REST API to create participants and join the game event.

## How to run the project

1. Download or clone this GitHub repository.
2. Open the project in [Godot Engine](https://godotengine.org).
3. Press <kbd>F5</kbd> or `Run Project`.

<br>

Note: To test multiplayer locally, follow these steps:
Go to `Debug` > `Customize Run Instances`, then enable `Enable Multiple Instances` and set the number of instances to run simultaneously. In this template, the host is not treated as a player.

## HearMeCheer Settings

Game server tries to load settings from `user://hmc_settings.json` by default. It can be overriden by passing `--config <path>` argument to the game server executable.

Config file should contain the following JSON structure:

```json
{
  "key": "hmc_api_key",
  "property": "your_hmc_name",
  "site": "https://api.hearmecheer.com",
}
```

## Controls

* <kbd>W</kbd> <kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd> to move.
* <kbd>Shift</kbd> to run.
* <kbd>Space</kbd> to jump.
* <kbd>`</kbd> to toggle dev console.
* <kbd>Esc</kbd> to quit.

GUI controls:

* `Mute` button to toggle recording.
* `Speaker` button to toggle speaker (audio output).
* `Debug` button to toggle debug mode.

## Known Issues

### MacOS

* Godot's microphone recording deosn't work with Bluetooth devices on MacOS. Use a wired headpones and built-in microphine instead.

## Credits

* 3D-Godot-Robot-Platformer-Character - https://github.com/AGChow/3D-Godot-Robot-Platformer-Character (CC0)
* Godot Multiplayer Template - https://github.com/devmoreir4/godot-3d-multiplayer-template