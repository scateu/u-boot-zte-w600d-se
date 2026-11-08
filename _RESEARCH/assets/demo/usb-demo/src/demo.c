/*
 * W600D USB-boot demo: a tiny bare-metal AArch64 program that the vendor U-Boot starts with `go`
 * (from boot.scr on a USB stick). It finds the boot logo framebuffer that is still on screen,
 * draws an animated rainbow band with scrolling text into it for ~8 s, and returns, so U-Boot
 * continues and Android boots.
 *
 * - No libc, no static data except the const font/signature (.rodata), position independent:
 *   tools/link.py lays out .text (entry first) + .rodata and resolves the PC-relative relocations.
 * - The framebuffer is found by content, not by register offsets: the patched logo (p17, a
 *   1920x1080 24-bit BMP, rows stored top-down) is searched for in the drm-logo reserved memory
 *   (0x7df00000, 32 MiB incl. the cubic LUT) using two rows of the "W600D LINUX" text (sig.h).
 * - Only the band rows are written, and every written line is cleaned to RAM (`dc cvac`) so
 *   the display controller sees it.
 */
#include "sig.h"

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long u64;

#define W        1920
#define H        1080
#define ROW      (W * 3)
#define FRAME    (ROW * H)
#ifndef HOST
#define SCAN_LO  0x7df00000UL
#define SCAN_HI  0x7ff08000UL
#else           /* host test (test-host.c): fake drm-logo memory */
extern unsigned long host_lo, host_hi;
#define SCAN_LO  host_lo
#define SCAN_HI  host_hi
#endif
#define BAND_Y   250
#define BAND_H   440
#define RUN_S    8
#define HOLD_S   3
#define MAXFB    4

int entry(int argc, char *const argv[]);

/* must stay the first function: the binary is entered at offset 0 */
int __attribute__((used)) _start(int argc, char *const argv[])
{
    return entry(argc, argv);
}

#ifndef HOST
static inline u64 now(void)
{
    u64 v;
    __asm__ volatile("isb; mrs %0, cntpct_el0" : "=r"(v));
    return v;
}

static inline u64 freq(void)
{
    u64 v;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(v));
    return v ? v : 24000000;
}
#else
u64 now(void);
#define freq() 1000UL
#endif

static void clean(u8 *p, u64 len)
{
#ifdef HOST
    (void)p; (void)len; return;
#endif
    u64 ctr, line, a, end = (u64)p + len;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    line = 4UL << ((ctr >> 16) & 0xf);
    for (a = (u64)p & ~(line - 1); a < end; a += line)
        __asm__ volatile("dc cvac, %0" : : "r"(a) : "memory");
    __asm__ volatile("dsb sy" : : : "memory");
}

/* hue 0..255 -> r,g,b */
static void hue(u32 h, u8 *rgb)
{
    u32 s = (h % 256) * 6, f = s % 256;
    u8 up = f, dn = 255 - f;
    switch (s / 256) {
    case 0:  rgb[0] = 255; rgb[1] = up;  rgb[2] = 0;   break;
    case 1:  rgb[0] = dn;  rgb[1] = 255; rgb[2] = 0;   break;
    case 2:  rgb[0] = 0;   rgb[1] = 255; rgb[2] = up;  break;
    case 3:  rgb[0] = 0;   rgb[1] = dn;  rgb[2] = 255; break;
    case 4:  rgb[0] = up;  rgb[1] = 0;   rgb[2] = 255; break;
    default: rgb[0] = 255; rgb[1] = 0;   rgb[2] = dn;  break;
    }
}

/* 5x7 font: 7 rows, 5 bits each (bit 4 = leftmost) */
static const u8 FONT[][7] = {
    {14,17,17,31,17,17,17}, {30,17,17,30,17,17,30}, {14,17,16,16,16,17,14}, {30,17,17,17,17,17,30}, /* A-D */
    {31,16,16,30,16,16,31}, {31,16,16,30,16,16,16}, {14,17,16,23,17,17,15}, {17,17,17,31,17,17,17}, /* E-H */
    {14, 4, 4, 4, 4, 4,14}, { 7, 2, 2, 2, 2,18,12}, {17,18,20,24,20,18,17}, {16,16,16,16,16,16,31}, /* I-L */
    {17,27,21,21,17,17,17}, {17,25,21,21,19,17,17}, {14,17,17,17,17,17,14}, {30,17,17,30,16,16,16}, /* M-P */
    {14,17,17,17,21,18,13}, {30,17,17,30,20,18,17}, {15,16,16,14, 1, 1,30}, {31, 4, 4, 4, 4, 4, 4}, /* Q-T */
    {17,17,17,17,17,17,14}, {17,17,17,17,17,10, 4}, {17,17,17,21,21,27,17}, {17,17,10, 4,10,17,17}, /* U-X */
    {17,17,10, 4, 4, 4, 4}, {31, 1, 2, 4, 8,16,31},                                                 /* Y-Z */
    {14,17,19,21,25,17,14}, { 4,12, 4, 4, 4, 4,14}, {14,17, 1, 2, 4, 8,31}, {31, 2, 4, 2, 1,17,14}, /* 0-3 */
    { 2, 6,10,18,31, 2, 2}, {31,16,30, 1, 1,17,14}, { 6, 8,16,30,17,17,14}, {31, 1, 2, 4, 8, 8, 8}, /* 4-7 */
    {14,17,17,14,17,17,14}, {14,17,17,15, 1, 2,12},                                                 /* 8-9 */
    { 0, 0, 0, 0, 0, 0, 0}, { 0,12,12, 0,12,12, 0}, { 0, 0, 0, 0, 0,12,12}, { 4, 4, 4, 4, 4, 0, 4}, /* sp : . ! */
    { 0,10,31,31,14, 4, 0}, { 0, 0, 0,31, 0, 0, 0},                                                 /* heart - */
};

static int glyph(char c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= '0' && c <= '9') return 26 + c - '0';
    switch (c) {
    case ':': return 37;
    case '.': return 38;
    case '!': return 39;
    case '*': return 40;            /* heart */
    case '-': return 41;
    default:  return 36;
    }
}

static int slen(const char *s)
{
    int n = 0;
    while (s[n]) n++;
    return n;
}

static void span(u8 *row, int x0, int x1, const u8 *rgb)
{
    if (x0 < 0) x0 = 0;
    if (x1 > W) x1 = W;
    for (int x = x0; x < x1; x++) {
        row[x * 3] = rgb[2];        /* BMP pixel order: B, G, R */
        row[x * 3 + 1] = rgb[1];
        row[x * 3 + 2] = rgb[0];
    }
}

/* draw the part of `text` (scale s, top-left x0,y0) that falls on screen row y */
static void text_row(u8 *row, int y, const char *text, int x0, int y0, int s, const u8 *rgb)
{
    int gy = (y - y0) / s, n = slen(text), cw = 6 * s;
    if (y < y0 || gy >= 7)
        return;
    int first = x0 < 0 ? (-x0) / cw : 0;
    for (int i = first; i < n; i++) {
        int cx = x0 + i * cw;
        if (cx >= W) break;
        u8 bits = FONT[glyph(text[i])][gy];
        for (int b = 0; b < 5; b++)
            if (bits & (16 >> b))
                span(row, cx + b * s, cx + (b + 1) * s, rgb);
    }
}

static const char MSG[] = "BOOTED FROM USB!  *  ZTE W600D  *  RK3568  *  HELLO FROM BARE METAL  *  NEXT: LINUX";
static const char SUB[] = "U-BOOT V13 - USB FIRST";
static const char END1[] = "USB BOOT OK";
static const char END2[] = "STARTING ANDROID...";

/* one band row: rainbow background + text with shadow. scroll < 0: static end screen */
static void band_row(u8 *row, int y, u32 t, int scroll, const u8 *pal)
{
    static const u8 black[3] = {0, 0, 0}, white[3] = {255, 255, 255}, yellow[3] = {255, 230, 0};
    for (int x = 0; x < W; x++) {
        const u8 *c = pal + ((x / 4 + y * 2 + t * 3) & 255) * 3;
        row[x * 3] = c[2] >> 1;     /* half brightness: text stays readable */
        row[x * 3 + 1] = c[1] >> 1;
        row[x * 3 + 2] = c[0] >> 1;
    }
    if (scroll >= 0) {
        int x0 = W - scroll;
        text_row(row, y - 6, MSG, x0 + 6, BAND_Y + 70, 16, black);
        text_row(row, y, MSG, x0, BAND_Y + 70, 16, white);
        int sx = (W - (slen(SUB) * 6 * 8 - 8)) / 2;
        text_row(row, y - 4, SUB, sx + 4, BAND_Y + 300, 8, black);
        text_row(row, y, SUB, sx, BAND_Y + 300, 8, yellow);
    } else {
        int x1 = (W - (slen(END1) * 6 * 20 - 20)) / 2, x2 = (W - (slen(END2) * 6 * 8 - 8)) / 2;
        text_row(row, y - 8, END1, x1 + 8, BAND_Y + 60, 20, black);
        text_row(row, y, END1, x1, BAND_Y + 60, 20, white);
        text_row(row, y - 4, END2, x2 + 4, BAND_Y + 300, 8, black);
        text_row(row, y, END2, x2, BAND_Y + 300, 8, yellow);
    }
}

static int eq(const u8 *a, const u8 *b, int n)
{
    for (int i = 0; i < n; i++)
        if (a[i] != b[i]) return 0;
    return 1;
}

int entry(int argc, char *const argv[])
{
    u8 *fb[MAXFB];
    int flip[MAXFB], nfb = 0;
    u8 pal[256 * 3];
    (void)argc; (void)argv;

    /* find every on-screen copy of the logo: row SIG1_Y at x SIG_X, confirmed with row SIG2_Y */
    /* byte steps: a BMP file kept as-is in RAM has its pixels at +54, not 16-byte aligned */
    u32 head = SIG1[0] | SIG1[1] << 8 | SIG1[2] << 16 | (u32)SIG1[3] << 24;
    for (u64 a = SCAN_LO; a + SIG_LEN <= SCAN_HI && nfb < MAXFB; a++) {
        const u8 *p = (const u8 *)a;
        if ((p[0] | p[1] << 8 | p[2] << 16 | (u32)p[3] << 24) != head || !eq(p, SIG1, SIG_LEN))
            continue;
        u64 down = a - SIG_X - (u64)SIG1_Y * ROW;            /* rows stored top-down */
        u64 up = a - SIG_X - (u64)(H - 1 - SIG1_Y) * ROW;    /* rows stored bottom-up */
        if (down >= SCAN_LO && down + FRAME <= SCAN_HI &&
            eq((u8 *)down + (u64)SIG2_Y * ROW + SIG_X, SIG2, SIG_LEN)) {
            fb[nfb] = (u8 *)down; flip[nfb++] = 0;
        } else if (up >= SCAN_LO && up + FRAME <= SCAN_HI &&
                   eq((u8 *)up + (u64)(H - 1 - SIG2_Y) * ROW + SIG_X, SIG2, SIG_LEN)) {
            fb[nfb] = (u8 *)up; flip[nfb++] = 1;
        } else {
            continue;
        }
        a = (u64)fb[nfb - 1] + FRAME - 1;                   /* skip the rest of this copy */
    }
    if (!nfb)
        return 1;                   /* logo not found: draw nothing */

    for (int i = 0; i < 256; i++)
        hue(i, pal + i * 3);

    u64 f = freq(), t0 = now(), end = t0 + RUN_S * f;
    int width = slen(MSG) * 6 * 16;
    for (u32 t = 0; ; t++) {
        u64 n = now();
        int last = n >= end;
        int scroll = last ? -1 : (int)(((n - t0) * 700 / f) % (u64)(W + width));
        for (int k = 0; k < nfb; k++) {
            for (int y = BAND_Y; y < BAND_Y + BAND_H; y++) {
                int r = flip[k] ? H - 1 - y : y;
                band_row(fb[k] + (u64)r * ROW, y, t, scroll, pal);
            }
            u64 lo = flip[k] ? H - BAND_Y - BAND_H : BAND_Y;
            clean(fb[k] + lo * ROW, (u64)BAND_H * ROW);
        }
        if (last)
            break;
    }
    for (u64 hold = now() + HOLD_S * f; now() < hold; )
        ;
    return 0;
}
