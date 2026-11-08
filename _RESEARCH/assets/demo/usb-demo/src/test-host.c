/* Host test for demo.c: fake drm-logo memory with the logo BMP file at +0 and a 4 KiB-aligned
 * pixel copy after it (vendor layout guess), run entry(), dump the first copy as a BMP.
 * cc -DHOST -O2 test-host.c -o test-host && ./test-host ../../logo/logo_w600d.img out.bmp */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define entry demo_entry
#define _start demo_start
#include "demo.c"
unsigned long host_lo, host_hi;
static unsigned long tick;
u64 now(void) { return tick += 5; }    /* fake 1 kHz clock, 5 ms per call */

int main(int argc, char **argv)
{
    FILE *f = fopen(argv[1], "rb");
    static unsigned char bmp[54 + FRAME];
    fread(bmp, 1, sizeof bmp, f); fclose(f);
    unsigned long size = 0x2008000;
    unsigned char *mem = calloc(1, size);
    host_lo = (unsigned long)mem; host_hi = host_lo + size;
    memcpy(mem, bmp, sizeof bmp);                         /* BMP file as loaded */
    unsigned long dec = (sizeof bmp + 4095) & ~4095UL;
    memcpy(mem + dec, bmp + 54, FRAME);                   /* decoded copy */
    int rc = demo_entry(0, 0);
    printf("rc=%d\n", rc);
    f = fopen(argv[2], "wb");
    fwrite(bmp, 1, 54, f); fwrite(mem + dec, 1, FRAME, f); fclose(f);
    return rc;
}
