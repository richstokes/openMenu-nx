#pragma once

/* Hands-off boot into dcload-ip. When the card carries a dcload-ip image and
 * nobody touches a controller, keyboard or mouse during the first 15 seconds
 * after power on, that image is launched as if it had been picked from the
 * list. Any input before then cancels it for the rest of the session. */

/* Looks the image up once the game list is loaded. Without one the feature
 * stays off. */
void dcload_autoboot_init(void);

/* Any user input cancels the pending launch */
void dcload_autoboot_cancel(void);

/* Once per frame. Launches when the deadline passes and nothing cancelled it. */
void dcload_autoboot_tick(void);
