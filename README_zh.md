# ZTE W600D SE (RK3568) 解锁速览（中文）

这台"云笔记本"出厂锁死：没有键盘可达的设置入口、没有 Back 键，vendor U-Boot
只认自家 Android。最短路径：开 ADB → 改键 → 改 `uboot_a` 让它开机先扫
U 盘 → U 盘里放这个仓库编译出的 mainline U-Boot（可选带中文五笔输入的编辑器，见
[`howto-typewriter-uboot.md`](howto-typewriter-uboot.md)）。拔掉 U 盘照常进 Android，
全程没改过 Android 本身。完整试错记录在仓库外的 `research/`（索引：`research/memory.md`），
这里只给能照着抄的命令。

## 0. 打开开发者模式 / ADB（绕过锁死的设置入口）
系统只给配网/登录界面，没有设置入口。办法：在任意输入框（比如 WiFi 密码框）调出 Google
拼音 → 长按逗号 `,` 进输入法设置 → 自定义词库 → 右上角搜索 → 搜"设置"，就能进完整系统
设置 → "关于平板"连点版本号开开发者模式 → 打开 USB 调试。

## 1. 连上 ADB、拿 root
这台机型开发者模式下**数据线直连 ADB 没用**，只能走网络（局域网 WiFi，或接 USB 转网卡）：
```sh
adb connect 10.0.0.66:5555      # 换成设备实际 IP
adb shell su 0 id                # 这台机器的 su 只认 "su 0 <cmd>"，"su -c" 不行
```
bootloader 已经是解锁状态（`orange`），`su` 直接能用，不需要自己 fastboot flash 什么。

### 1a. 清理移动/ZTE 预装包（可选）
```sh
adb shell pm list packages | grep -i <关键字，如 zte/cmcc>
adb shell pm uninstall --user 0 <包名>     # 只删当前用户数据，系统分区不动，可恢复
```
具体删哪些包因机而异，先 `pm list packages` 看一遍再动手，没有固定清单。

### 1b. 没有 Back 键：把 Windows 键映射过去
```sh
../research/tools/map-winkey-back.sh            # ⊞ → BACK
../research/tools/map-winkey-back.sh --undo     # 改回去
```
原理（往 `/data/system/devices/keylayout/` 塞一份按键布局文件，不改 `/system`）和手工步骤见
`../research/docs/back-key.md`。核心一步：
```sh
adb shell su 0 sh -c '
  mkdir -p /data/system/devices/keylayout
  cp /data/local/tmp/Vendor_258a_Product_0001.kl /data/system/devices/keylayout/
  chown -R system:system /data/system/devices && restorecon -R /data/system/devices'
```

## 2. 改 vendor U-Boot：开机先扫 U 盘
机器有 A/B 两套 uboot+Android（`uboot_a`/`uboot_b`）。原装 `bootcmd` 是
`boot_fit; boot_android; run distro_bootcmd`——Android 总能启动，USB 扫描那句永远走不到。
改成先跑 USB/MMC 扫描再 `boot_android`：
```
bootcmd=run bootcmd_usb0;run bootcmd_mmc0;usb stop;boot_fit;boot_android ${devtype} ${devnum};run distro_bootcmd;
```
**用脚本（推荐）**，一条命令做完 备份→改→写回→校验→置位 A/B：
```sh
vendor-env/w600d-uboot-a.sh install      # 备份 uboot_a/uboot_b/misc 到 w600d-uboot-backup-<date>/，改好就写回
vendor-env/w600d-uboot-a.sh check        # 重启后确认状态
vendor-env/w600d-uboot-a.sh flash <备份目录>/uboot_a.img   # 后悔了就用这条写回原厂
```
手工等价操作（`uboot_a` 是 4 MiB 分区；`patch-uboot-env.py` 只改环境变量，不碰 FIT 签名）：
```sh
adb shell "su 0 dd if=/dev/block/by-name/uboot_a of=/data/local/tmp/uboot_a.img bs=1048576"
adb pull /data/local/tmp/uboot_a.img
python3 -I vendor-env/patch-uboot-env.py uboot_a.img uboot_a-usbfirst.img
adb push uboot_a-usbfirst.img /data/local/tmp/
adb shell "su 0 dd if=/data/local/tmp/uboot_a-usbfirst.img of=/dev/block/by-name/uboot_a bs=1048576 && sync"
adb shell "su 0 bootctl set-active-boot-slot 0"
adb reboot
```
⚠️ **只刷 `uboot_a`，`uboot_b` 保持原厂不动**——它是救砖用的。已验证的原厂行为：改坏的
slot A 连续开机失败约 **7–8 次**后，vendor U-Boot 自动切到 slot B（原厂 Android，正常开机）；
恢复就是把备份的 `uboot_a.img` 写回 + `bootctl set-active-boot-slot 0`。这个重试计数存在
`misc` 分区的 A/B 元数据里（libavb_ab 格式，机制细节见 `../research/docs/ab-tries.md`），不是
U-Boot 自己算的。**千万不要把 mainline/自编译的 U-Boot 直接写进 `uboot_a`**——vendor 的一级
引导（SPL）只有在 FIT **加载失败**时才切 slot B；一个能加载但跑不起来的 U-Boot，只剩
MaskROM 这条路能救。

## 3. 做一个能被 `uboot_a` 优先启动的 U 盘
插着 U 盘 → 进本仓库编译出的 mainline U-Boot（带五笔输入编辑器）；拔掉 U 盘 → 照常进 Android。
```sh
./build.sh                      # 产出 out/stick/{boot.scr, u-boot-w600d.bin, w600d-chain.bin}
# 或直接用已经编译好的 prebuilt/ 三个文件
diskutil eraseDisk FAT32 ZTE_TEST MBRFormat /dev/diskN   # U 盘必须是 MBR + 单个 FAT32 分区
cp out/stick/* /Volumes/ZTE_TEST/ && dot_clean /Volumes/ZTE_TEST && diskutil eject /Volumes/ZTE_TEST
```
插**右边**的 USB-A 口（左边是 OTG，没测通）。开机顺序：logo → 几秒原厂 USB 扫描 → 黑一下 →
mainline U-Boot 大字横幅 + `usb tree` + `=>`。输入 `typewriter` 进编辑器。更多细节/排错表见
[`README.md`](README.md)。

## 4. 手工编译 U-Boot、以及它是怎么跑起来的

### 4.1 不用 `build.sh`，一步步编
```sh
git clone https://source.denx.de/u-boot/u-boot.git u-boot
git -C u-boot checkout 709a97a0            # 2027.01-rc1，补丁是按这个基线做的
./patch-u-boot.sh u-boot                   # 套 patches/u-boot/0001-0005，并把 typewriter/ 拷进 cmd/typewriter/
cd u-boot
make CROSS_COMPILE=aarch64-linux-gnu- zte-w600d-chain-rk3568_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- NO_PYTHON=1 -j8 u-boot.bin
```
`u-boot.bin` 要小于 4 MiB（装载地址 `0x00800000`，紧接着 `w600d-chain.bin` 要占的
`0x10000000` 之前留的空间就这么多）。chain shim 是单独的裸汇编，不走 U-Boot 的构建系统，
自己编译、objcopy 成裸二进制，再用专门的脚本打包 `boot.scr`：
```sh
aarch64-linux-gnu-gcc -c chain/chain.S -o chain.o
aarch64-linux-gnu-ld -Ttext=0x10000000 chain.o -o chain.elf
aarch64-linux-gnu-objcopy -O binary chain.elf w600d-chain.bin
python3 -I chain/mkscr.py chain/boot-nc.cmd boot.scr
```
`build.sh` 就是把这几步串起来；拆开写的好处是改一样东西（比如只调 shim）不用重新编译一遍
整个 U-Boot。

### 4.2 定制了哪几处
mainline U-Boot 原生完全不认识这台笔记本，统共改/加了这几块（逐条对应
`patches/u-boot/0001`–`0005`）：

- **USB 键盘的 Ctrl 组合键**（`common/usb_kbd.c`）：原来不管按什么键，Ctrl 按住时都发
  `scancode-3`，字母碰巧算对了（终端控制码），其余键全错（Ctrl-Space 变成了 `)`）。改成按
  终端的规则映射。
- **32-bpp 像素的 alpha**（`drivers/video/video-uclass.c`）：RK3568 的 VOP2 只有 ARGB 格式，
  没有 XRGB，alpha=0 会被当成全透明，所以给纯色强制填 `0xff`。
- **一个新驱动 `rk3568_vop2_takeover.c`**：mainline 没有 RK3568 的 VOP2 驱动，干脆不写真正
  的初始化代码，而是找 vendor U-Boot 已经点亮的那扇 VOP2 窗口（这台机器上是
  Smart0 → VP1 → eDP），量出它的分辨率，把它改指向新分配的 ARGB8888 帧缓冲，关掉
  y-mirror/RB swap，再 `REG_CFG_DONE` 生效——面板、背光、eDP 时序全部不碰,避免重新点屏的
  风险。
- **接入 `typewriter` 编辑器**：本体来自
  [scateu/u-boot-typewriter](https://github.com/scateu/u-boot-typewriter)，补丁只在
  `cmd/Kconfig`/`cmd/Makefile` 挂个入口，源码由 `patch-u-boot.sh` 从仓库自带的 `typewriter/`
  目录拷进 `cmd/typewriter/`（这边还单独改了几行给这台板子用的默认参数，记录在
  `patches/typewriter/w600d-changes.patch`）。
- **板级文件（全新）**：`arch/arm/dts/rk3568-w600d.dts`（UART2、eMMC、USB 主机、键盘供电
  GPIO3_A3 的 `gpio-hog`、USB 5 V 供电、挂 VOP2 takeover 节点）和
  `configs/zte-w600d-chain-rk3568_defconfig`（装载地址、跳过 vendor logo 占用的内存区、开
  USB 键盘 + 面板终端、打开 typewriter）。

### 4.3 `boot.scr` 的门道
`boot.scr` 本来就是老版 uImage 的 `script` 类型：64 字节头，后面跟一张"每段脚本多长"的表，
再是脚本正文。标准 `mkimage` 用一个 `0` 收尾这张表，U-Boot 的 `source` 命令读到 `0` 就停。
**这台笔记本的 vendor U-Boot 不是这样**：它的 `source`（反汇编定位在 `uboot_a` 的
`0xa07f4c`）认的收尾值是 `0xFFFFFFFF`，不是 `0`。用标准 `mkimage` 打出来的 `boot.scr`，
它读到表尾那个 `0` 不会停，接着把后面的脚本正文/内存里的垃圾当指令往下跑——不报错，也
看不出异常，等于啥都没发生，直接照常进了 Android（最早几次试就是这么"诡异地无效"的）。

对策是仓库里的 `chain/mkscr.py`：自己拼头、自己拼一张只有一项、以 `0xFFFFFFFF` 收尾的表，
专给这台 vendor U-Boot 用，别的机器大概率不认。脚本正文也有条硬规矩：**不能在顶层写
`if`**（vendor 的 hush 解释器碰到某些 `if` 块之后再调 `boot_android` 会直接重启板子，没有
查到底是为什么，干脆绕开），所以 `chain/boot.cmd`/`boot-nc.cmd` 全写成一行一句、靠 `&&`
串起来的平铺脚本，每一步顺手把结果记进 `bootargs`（没有串口的情况下，这是唯一能从
Android 里 `cat /proc/cmdline` 读回来的调试信息）。

### 4.4 `uboot_a` 怎么把 U 盘上的 U-Boot chain-load 起来
完整链路：
```
BootROM → SPL → vendor U-Boot 2017.09（uboot_a，bootcmd 已改成 USB 优先）
  → usb start，扫到 U 盘分区1(FAT32)，source 按 4.3 的规则跑 boot.scr
  → boot.scr: load u-boot-w600d.bin → 0x00800000
              load w600d-chain.bin  → 0x10000000
              usb stop   (vendor 的 USB 控制器先停 DMA，别让 mainline 重新初始化它时冲突)
              go 0x10000000   (不直接跳 mainline 入口，先跳进 shim)
```
之所以要绕一个只有十几条指令、272 字节的 shim（`chain/chain.S`），是因为跳过来的时候 vendor
U-Boot 的 MMU、D-cache 一直是开着的，而 mainline U-Boot 的早期初始化假设自己是刚从
BootROM/TF-A 接手的裸机状态，两边对不上。`chain.S` 做的事：关中断 → 按 set/way 整个清理
并无效化 D-cache → 读当前在 EL2 还是 EL1（两种都要支持），把对应 `sctlr_elx` 里的 M/C 位
关掉 → 再清一次 D-cache → 无效化 I-cache 和 TLB → 把 x0–x3 清零（别让 mainline 看到 vendor
留下的参数）→ 跳到 `TARGET`（即 `0x00800000`）。全程只用寄存器，不搭栈、不碰全局变量，
因为这时候整块内存的状态都信不过。

跳进去之后才是真正的 mainline U-Boot 跑自己的早期初始化：`rk3568_vop2_takeover.c` 看到面板
已经是点亮的，直接接管现成的 VOP2 窗口而不重新初始化 eDP；键盘走正常的 xHCI 枚举 +
`usb_kbd`（供电 GPIO 由 DTS 里的 `gpio-hog` 保证常开）。于是屏幕上出现 `=>`，键盘能敲字。
拔掉 U 盘，`boot.scr` 里的 `load` 会失败，脚本直接返回，U-Boot 的 distro 扫描退回 eMMC，
照常进 Android——这条链路从头到尾没往 eMMC 写过一个字节。

---
以后接手的人：每一步背后的试错记录（哪个 `bootcmd` 版本会死机、为什么 `boot.scr` 要用自己
的 `chain/mkscr.py` 而不是 `mkimage` 等）在仓库外的 `research/`，入口是 `research/memory.md`。
这份文件只管"最快从锁死状态跑到自己的 U-Boot"。
