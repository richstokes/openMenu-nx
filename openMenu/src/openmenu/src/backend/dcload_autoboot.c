#include <ctype.h>
#include <stdint.h>
#include <string.h>

#include <arch/timer.h>

#include <backend/gd_item.h>
#include <backend/gd_list.h>
#include "backend/dcload_autoboot.h"

/* Same entry point the A button uses for a normal game */
extern void dreamcast_launch_disc(const struct gd_item* disc);

/* Measured on the KOS millisecond clock, which starts when openMenu boots */
#define DCLOAD_AUTOBOOT_MS 15000

static const gd_item* target;
static int armed;

static int
name_has_ci(const char* name, const char* needle) {
    size_t n = strlen(needle);

    for (; *name; name++) {
        size_t i;
        for (i = 0; i < n && name[i]; i++) {
            if (tolower((unsigned char)name[i]) != tolower((unsigned char)needle[i])) {
                break;
            }
        }
        if (i == n) {
            return 1;
        }
    }
    return 0;
}

/* The title comes from whatever the Card Manager wrote, so accept the usual
 * spellings and only then settle for any dcload that is not the serial one */
static const gd_item*
find_dcload_ip(void) {
    static const char* const spellings[] = {"dcload-ip", "dcload_ip", "dcload ip", "dcloadip"};
    const gd_item* item;

    for (unsigned i = 0; i < sizeof(spellings) / sizeof(spellings[0]); i++) {
        item = list_find_by_name_ci(spellings[i]);
        if (item) {
            return item;
        }
    }

    item = list_find_by_name_ci("dcload");
    if (item && !name_has_ci(item->name, "serial")) {
        return item;
    }
    return NULL;
}

void
dcload_autoboot_init(void) {
    target = find_dcload_ip();
    armed = target != NULL;
}

void
dcload_autoboot_cancel(void) {
    armed = 0;
}

void
dcload_autoboot_tick(void) {
    if (!armed) {
        return;
    }
    if (timer_ms_gettime64() < DCLOAD_AUTOBOOT_MS) {
        return;
    }

    /* Only ever try once. A launch that fails to leave openMenu (for
     * example a missing loader) must not fire again every frame. */
    armed = 0;
    dreamcast_launch_disc(target);
}
