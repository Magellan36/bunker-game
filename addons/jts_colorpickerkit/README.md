# JT's Color Picker Kit (Godot Plugin)

<div align="center">
	<img src="./addons/jts_colorpickerkit/icon.png" width="25%"/>
</div>

<div align=center>
    <img src="https://img.shields.io/badge/version-%30%2E%31-green">
    <a href="./LICENSE">
        <img src="https://img.shields.io/badge/LICENSE-Apache2%2E0-blue">
    </a>
    <br>
    <img src="https://img.shields.io/badge/GD_Script-468cbf">
    <img src="https://img.shields.io/badge/4.3-468cbf">
</div>

> A complete runtime support user-interface-based RGBA and HSV Color Picker.

---

## How to Install?

You can either download via Asset Library available in Godot Engine, or Download from Releases [here] and follow these steps:

1. Download the ZIP file.
2. Extract the named plugin folder.
3. Copy the folder into your Godot Project `addons` folder. (If you haven't added the addons folder under the `res://` folder, then manually create the folder)

## All Useful Events and Functions
---

> For a quick way to use it in runtime, look for `UI_ColorPickerInstance` script that attached to `color-picker.tscn`. These are the most useful events and functions:

|Named|Type|Usage|
|-----|----|-----|
|```on_color_picked(c: Color)```|**Event**|Called when confirm selected color. Signal used to receive the color value.|
|```get_picked_color() -> Color```|**Function**|Get current cached picked color.|
|```set_targeted_control(target: Control)```|Function|Setting the target control node for color instance to live send the color.|

---

# Showcase & Screenshots

| <img src="./addons/jts_colorpickerkit/screenshots/rgba-sample.png" width="100%" alt="rgba-sample"/> | <img src="./addons/jts_colorpickerkit/screenshots/hsv-sample.png" width="100%"> |
|:--:|:--:|

<br>

![showcase-gif](./addons/jts_colorpickerkit/screenshots/showcase.gif)

---

# PATCH LOGS
---
```  
  ### Version 0.1.0 ###
- Initial Released for Godot 4.3
```