# 自定义软件名称和图标

Orange 提供品牌替换脚本，方便二次打包时替换软件名称和各平台图标。

## 1. 准备图标

把你的图标放到项目内，例如：

```text
assets/brand/logo.png
```

建议使用：

- PNG/JPG/WebP/ICO 均可
- 推荐 1024×1024 正方形 PNG
- 透明背景也支持
- 脚本会自动裁剪为正方形，并生成所有平台需要的尺寸

## 2. 执行替换

```bash
python3 scripts/brand.py --name YourApp --icon assets/brand/logo.png
```

脚本会替换：

- Android 应用名、通知名、传统启动图标、adaptive icon 前景/背景
- Linux 窗口名、包名配置、图标
- macOS `PRODUCT_NAME`、DMG 标题、AppIcon
- 应用内左上角标题（`lib/common/constant.dart`）
- Windows 窗口名、EXE 名称配置、资源图标
- 通用资源 `assets/images/icon.*`

## 3. 只替换名称或图标

只替换名称：

```bash
python3 scripts/brand.py --name YourApp --name-only
```

只替换图标：

```bash
python3 scripts/brand.py --name YourApp --icon assets/brand/logo.png --icon-only
```

> `--icon-only` 仍需要传 `--name`，用于保持命令格式一致。

## 4. 注意事项

- 脚本不会改 Kotlin 类名、包名、CMake target、`Flclash` 可执行 target、`FlClashCore` 等内部代码标识，只改用户可见名称、安装包配置和图标。
- 执行前建议先提交或备份当前仓库，方便 `git checkout -- <file>` 回滚。
- 替换后再执行正常打包命令，例如：

```bash
dart setup.dart android --arch arm64
```


## 5. Windows debug 注意

脚本不会修改 `windows/CMakeLists.txt`。Flutter Windows 的 CMake target 需要保持 `Flclash`，否则 `flutter run -d windows` 可能出现：

```text
No target "Flclash"
```

如果之前执行过旧版脚本导致这个错误，恢复一次即可：

```powershell
git checkout -- windows\CMakeLists.txt
rmdir /s /q build
flutter run -d windows
```

## 6. 验证 Windows 名称是否已替换

执行品牌替换后，可以检查这些文件：

```powershell
Select-String -Path windows\runner\main.cpp,windows\runner\Runner.rc,windows\packaging\exe\make_config.yaml -Pattern "YourApp"
```

如果没有搜到你的名字，先更新源码再重新执行脚本：

```powershell
git pull
python scripts\brand.py --name "YourApp" --icon assets\brand\logo.png
flutter clean
flutter run -d windows
```

注意：`windows\CMakeLists.txt` 里的 `Flclash` 是内部 CMake target，必须保留，不代表最终显示名称。

## 7. 左上角标题仍是 Flclash 怎么办

左上角标题来自 Flutter 内部常量 `lib/common/constant.dart`，不是 Windows CMake target。
更新源码后重新执行：

```powershell
git pull
python scripts\brand.py --name "YourApp" --icon assets\brand\logo.png
flutter clean
flutter run -d windows
```

如果只想快速验证标题是否已改：

```powershell
Select-String -Path lib\common\constant.dart -Pattern "const appName"
```
