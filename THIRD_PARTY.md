# 第三方素材与代码

## 触屏虚拟按键（Resources/Sprites/UI/vk/、Scripts/Libraries/Controller/VirtualKeyboard.lua）

- **原始美术素材与原始 LÖVE 触控实现**：zzy（Bilibili UID `3546380257724712`），随
  `virtualkeyboardV3.5.7z` 提供。原始说明允许修改与再分发，并要求尽可能署名。
- **Kristal 适配版**（改变布局、坐标换算、输入分发、生命周期与绘制接入，目标
  Kristal `0.11.0-dev` `f62afea63ccab02f468c24ac0d096bd8a2c9aa81`）：
  见 Bli-AIk/thrash-machine 的 `libraries/virtualkeyboard`。
- **本仓库的 SoulEngine 适配**：沿用同一套素材与坐标约定，改为接入 SoulEngine 的
  `Keyboard.SimulatePress` / `SimulateRelease`、640x480 画布与 `ScreenScale` 缩放，
  并增加 F9 开关与触摸自动启用。

素材文件：`Resources/Sprites/UI/vk/buttons/*.png`（方向箭头与 Z/X/C，含按下帧 `*1.png`）、
`Resources/Sprites/UI/vk/joystick/*.png`（摇杆底盘与手柄）。使用时请保留本文件中的署名。
