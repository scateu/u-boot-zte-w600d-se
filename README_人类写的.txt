这个笔记本我基本摸清楚了，现在最稳妥的办法: 

0) 按教程"已经找到办法了，在输入账号或者WIFI界面添加WIFI，就是找一个输入框，然后摁键盘的ALT键，长摁逗号，设置谷歌输入法，然后自定义词典，右上角搜索，然后搜索设置，关于平板，自行打开ADB就行了。" 按出Google拼音，然后进入设置-开发者模式开ADB    

1) 拿到adb (之后只能wifi或USB网卡来adb connect;adb shell, USB不行)

1a) 把安卓里的一众中国移动的包清理掉

1b) 由于没有返回键，重新改一下键位，把Windows键映射为返回键

2) 把 uboot_a 分区dump出来，patch掉固件里的BOOTCMD，
   工厂初始: `bootcmd=boot_fit;boot_android ${devtype} ${devnum};run distro_bootcmd;` 而`distro_bootcmd=for target in ${boot_targets}; do run bootcmd_${target}; done`
   Patch之后: `bootcmd=run bootcmd_usb0;run bootcmd_mmc0;usb stop;boot_fit;boot_android ${devtype} ${devnum};run distro_bootcmd;`
   使得可以从U盘引导
   (它有两套uboot和android，第1套出问题之后，反复重启8次会进入uboot_b，引导另一套Android救砖; 但不确定把uboot_a搞坏之后的行为。即这个反复重启的8次记数的指标是哪里)
3) 搞个U盘 boot.scr 然后用uboot_a来引导U盘里的uboot；拔了U盘则引导原系统


