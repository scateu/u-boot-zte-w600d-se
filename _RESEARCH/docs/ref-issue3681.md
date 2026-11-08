# Reference: ophub/amlogic-s9xxx-armbian issue #3681 (ZTE W6XX / W600D2)

Source: `ref/请求增加中兴云笔电 W6XX(W601E_W600D2等) 系列支持 … Issue #3681 … .html` (saved page).
The issue was opened 2026-09-24 by xRetia. It's an **AI-generated feasibility report** for a
`rk3568_r_w600d2` (same board family as ours), plus two comments. Read 2026-11-05.

## 1. The most useful parts

1. **Official ZTE firmware download** (full factory image, includes Android `super`):
   `http://ctmcdn.zx.zte.com.cn/vops-autoops-cpe/download/images/W6XX_W52X-RK3568-T-ALLV2.25.20P06-Firmware.zip`
   - This could be a full way back to Android without our own `super` dump. Version `V2.25.20P06`
     ≠ ours (`FactoryV1.24.20P2-20240529`), so it's probably newer and might bring a different
     U-Boot/DTB. Download it and **inspect it on the Mac first**; don't flash it blindly. It probably
     also contains a Rockchip loader (`MiniLoaderAll.bin`), which would be the matching MaskROM
     loader for `debrick.md` §4.1.
   - Not downloaded yet (size unknown, plain HTTP: check what's inside).
2. **Their DTS dump**: `https://dfc643.lanzouv.com/ialYP49qljoj` (lanzou file share). We already have
   our own (`w600d-backup/device_slot_b.dts`, `resource_a/`), so this is only for comparison.
3. **MT7663 Wi-Fi: the comment by pigeon2049 (2026-11-03) is the important technical part**:
   - Mainline **does** have `mt7663s` (`mt76/mt7615/sdio.c`). `morrownr/mt76` is the same code.
     The problem is **stability**, not a missing driver.
   - Layer 1, SDIO host: an Amlogic-specific DMA/alignment problem. **RK3568's dw_mmc can DMA
     normally, so it doesn't have this problem.** ✅ good for us.
   - Layer 2, driver bugs (all boards): read-to-clear WHISR interrupt status not fully saved (lost TX
     credits/RX events → stalls, disconnects); 112-byte RX-enhance tail not parsed; no recovery after
     mailbox timeout or TX quota exhaustion (drops during scans); Wi-Fi and SDIO-BT share an eFuse, and
     initializing them at the same time gives Wi-Fi a wrong EEPROM/MAC (no ordering in mainline).
   - Layer 3, per-board: N9 firmware and ROM patch must be a **matching pair** (extract them from the
     stock Android: `/vendor/firmware` or `/vendor/etc/firmware`), reset/power GPIOs, whether 1.8 V
     is fixed (CMD11), BT over SDIO vs UART, calibration data.
   - They have patches working on the **ZTE W103D** (S905L3A). Plan: turn the model check into a
     DT property, ship it in the ophub kernel, and **look for RK3568 W6XX testers**. They'd need the
     stock firmware, Wi-Fi reset/power GPIOs, and which SDIO controller is used.
     **We have all three:** MT7663 on `dwmmc@fe2c0000` (sdmmc1), power GPIO0_A5, reset GPIO0_B5,
     host-wake GPIO2_B2 (see `ref-z96a-comparison.md`). We could contribute here.
   - The kernel needs ≥ 5.11 for `mt7663s`. That's another argument for a newer kernel than the 5.10 BSP
     (or backporting mt76).

## 2. Their device vs ours

| | Issue #3681 unit | **Our unit** |
|---|---|---|
| Product code | `rk3568_r_w600d2` | `rk3568_r_w600d2` |
| Android build | 2023-12-26 | 2024-05-29 (slot A), slot B 2024-07-31 |
| U-Boot | 2017.09, Dec 26 2023 | 2017.09, May 29 2024 / Jul 31 2024 |
| Running slot | **B** | **A** |
| DTB candidates in boot image | 13 | 17 |
| ADC selection | ch1 = 853 → dtb_idx 0 | ch1/ch4 = 938/779 → `rk3568-w600dse-pvt-cs` |
| eDP panel | **GX-KD140N2530** | **guoxian-30NK** |
| eMMC | A3A551, 28.9 GiB | A3A551 (same) |
| RAM | 2 GB DDR4 | 2 GB DDR4 |

So the "W600D2" covers several panels and board revisions. **A DTS for one unit isn't
automatically right for another one**. Always use the DTB that U-Boot picks on *your* unit.

## 3. Where the report is wrong or doesn't apply to us (checked)

| Report says | Reality (our unit) |
|---|---|
| idbloader sits in eMMC **boot0/boot1**, which must be written first | **Checked 2026-11-05:** `mmcblk2boot0/1` are **all zeros** (sha256 = 4 MiB of zeros), `EXT_CSD PARTITION_CONFIG = 0x00` (boot partitions not enabled for boot), `force_ro=1`. The idbloader is at **user-area sector 64** (we have it in `emmc_first16MiB.bin`). Writing boot0/1 does nothing useful. |
| `backup` (p13) = 1.5 GB factory recovery image | Ours is an **empty ext4**. |
| `baseparameter` = baseband parameters | It's Rockchip **display** parameters ("BASP", DISP_0..4). |
| Stock U-Boot "can be replaced directly by Armbian's u-boot" | Possible, but a mainline U-Boot **has no RK3568 VOP2 driver → no screen in U-Boot**, and SPL expects the A/B partitions by name. Our plan keeps the stock U-Boot (`usb-boot.md`). |
| Recommended path A: `dd` a whole Armbian `.img` onto `/dev/block/mmcblk2` from running Android | **Risky and against our plan.** It overwrites GPT + idbloader + uboot/trust while Android runs from the same disk. If anything is wrong, the only way out is MaskROM. Not recommended. |
| BQ25700: "mainline driver available" | Not verified. The Rockchip BSP has `bq25700_charger`. Mainline has no driver under that name, as far as known. Check before relying on it. |
| Dual GMAC disabled → maybe RJ45 inside | The GMAC nodes come from the EVB base DTS. The laptop has **no Ethernet port**, so expect no PHY. |
| eDP: "no panel config in mainline, make your own or give up" | The timings are in the stock DTB (`simple-panel`), so a mainline-kernel DTS can copy them. Only U-Boot (mainline) lacks the display driver. |

## 4. Impact on our plan

- **Backups:** boot0/1 don't need backing up (empty). Our `emmc_first16MiB.bin` is the real loader.
- **Recovery/Android:** fetch and inspect the ZTE firmware zip. It may replace the 5 GB `super` dump
  and give us a matching MaskROM loader.
- **Wi-Fi:** plan for mainline `mt7663s` (kernel ≥ 5.11) plus pigeon2049's fixes, with firmware
  pulled from our Android **before the wipe**. The issue is a good place to offer testing.
- **Kernel choice** moves a bit towards newer kernels (6.x): mt7663s, VOP2/HDMI are in mainline.
  The 5.10 BSP remains the fastest route to working eDP + charging.
