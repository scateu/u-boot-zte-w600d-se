# SPDX-License-Identifier: GPL-2.0+
# Build rules for the `typewriter` command. Drop this directory in as
# cmd/typewriter/ and add to cmd/Makefile:
#   obj-$(CONFIG_CMD_TYPEWRITER) += typewriter/
# (or copy the sources straight into cmd/ and append these lines there - do NOT
# overwrite cmd/Makefile, that drops bootm/booti/bootd and breaks the link).
obj-$(CONFIG_CMD_TYPEWRITER) += cmd_tw.o cmd_tw_fs.o cmd_tw_video.o \
				ime_table.o wubi_embed.o font_data.o
# WFI-idle debug command (twwfi): pokes RK3399 GIC/CRU/GPIO directly.
obj-$(CONFIG_TW_RK3399_POWERSAVE) += cmd_twwfi.o
