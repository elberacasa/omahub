// omahub-pointer: a virtual pointer for recording demos. It moves, clicks, holds, drags, and
// scrolls through the wlr virtual pointer protocol, which Hyprland supports, so no root access
// and no extra package are needed.
//
//   omahub-pointer --extent <width> <height> --from <x> <y> [command...]
//
// Commands run in order:
//   move <x> <y> <ms>   go straight to a point in the compositor's global layout, eased in and out
//   glide <x> <y> <ms>  go there the way a hand does: a slight curve, a faint tremor, a small overshoot
//   down <button>       press left, right, or middle
//   up <button>         release it
//   click <button>      press and release
//   scroll <steps>      wheel steps, positive scrolls down
//   wait <ms>           pause

#define _DEFAULT_SOURCE

#include <linux/input-event-codes.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_display *display;
static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct zwlr_virtual_pointer_v1 *pointer;
static uint32_t extent_width;
static uint32_t extent_height;
static double position_x;
static double position_y;

static void handle_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
                          uint32_t version) {
  (void)data;
  (void)version;
  if (strcmp(interface, wl_seat_interface.name) == 0 && seat == NULL) {
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
  } else if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
    manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
  }
}

static void handle_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener registry_listener = {
  .global = handle_global,
  .global_remove = handle_global_remove,
};

static uint32_t now_ms(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000);
}

static void sleep_ms(long ms) {
  struct timespec duration = { ms / 1000, (ms % 1000) * 1000000L };
  nanosleep(&duration, NULL);
}

static void place(double x, double y) {
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x > extent_width - 1) x = extent_width - 1;
  if (y > extent_height - 1) y = extent_height - 1;
  position_x = x;
  position_y = y;
  zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), (uint32_t)lround(x), (uint32_t)lround(y),
                                          extent_width, extent_height);
  zwlr_virtual_pointer_v1_frame(pointer);
  wl_display_flush(display);
}

// Ease in and out, about 120 steps a second, so recorded motion looks like a hand.
static void move_to(double x, double y, long ms) {
  double start_x = position_x;
  double start_y = position_y;
  long steps = ms / 8;
  if (steps < 1) steps = 1;
  for (long step = 1; step <= steps; step++) {
    double t = (double)step / steps;
    double eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
    place(start_x + (x - start_x) * eased, start_y + (y - start_y) * eased);
    sleep_ms(ms / steps);
  }
}

// A hand's path: a gentle curve bowing to one side, quick in the middle and slow at both ends, a
// faint tremor that fades as it arrives, and a small overshoot that settles back onto the point.
static void glide_to(double x, double y, long ms) {
  double start_x = position_x;
  double start_y = position_y;
  double dx = x - start_x;
  double dy = y - start_y;
  double distance = hypot(dx, dy);
  if (distance < 3 || ms < 60) {
    move_to(x, y, ms);
    return;
  }
  double normal_x = -dy / distance;
  double normal_y = dx / distance;
  double bow = distance * (0.05 + drand48() * 0.08) * (drand48() < 0.5 ? -1 : 1);
  double overshoot = fmin(9, distance * 0.018);
  double end_x = x + dx / distance * overshoot;
  double end_y = y + dy / distance * overshoot;
  double control1_x = start_x + dx * 0.28 + normal_x * bow;
  double control1_y = start_y + dy * 0.28 + normal_y * bow;
  double control2_x = start_x + dx * 0.72 + normal_x * bow * 0.55;
  double control2_y = start_y + dy * 0.72 + normal_y * bow * 0.55;
  double phase = drand48() * 6.28;
  long travel = ms * 86 / 100;
  long steps = travel / 8;
  if (steps < 1) steps = 1;
  for (long step = 1; step <= steps; step++) {
    double t = (double)step / steps;
    double eased = t * t * t * (10 - 15 * t + 6 * t * t);
    double u = 1 - eased;
    double px = u * u * u * start_x + 3 * u * u * eased * control1_x + 3 * u * eased * eased * control2_x
      + eased * eased * eased * end_x;
    double py = u * u * u * start_y + 3 * u * u * eased * control1_y + 3 * u * eased * eased * control2_y
      + eased * eased * eased * end_y;
    double tremor = 0.6 * (1 - t);
    place(px + tremor * sin(phase + t * 23), py + tremor * cos(phase * 1.3 + t * 19));
    sleep_ms(travel / steps);
  }
  move_to(x, y, ms - travel);
}

static int button_code(const char *name) {
  if (strcmp(name, "left") == 0) return BTN_LEFT;
  if (strcmp(name, "right") == 0) return BTN_RIGHT;
  if (strcmp(name, "middle") == 0) return BTN_MIDDLE;
  return -1;
}

static void button(int code, int pressed) {
  zwlr_virtual_pointer_v1_button(pointer, now_ms(), (uint32_t)code,
                                 pressed ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
  zwlr_virtual_pointer_v1_frame(pointer);
  wl_display_flush(display);
}

static void scroll(int steps) {
  zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
  zwlr_virtual_pointer_v1_axis_discrete(pointer, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL,
                                        wl_fixed_from_int(steps * 15), steps);
  zwlr_virtual_pointer_v1_frame(pointer);
  wl_display_flush(display);
}

static int fail(const char *message) {
  fprintf(stderr, "omahub-pointer: %s\n", message);
  return 1;
}

static const char *argument(int argc, char **argv, int index) {
  return index < argc ? argv[index] : NULL;
}

int main(int argc, char **argv) {
  int index = 1;
  double from_x = -1;
  double from_y = -1;

  while (index < argc && strncmp(argv[index], "--", 2) == 0) {
    if (strcmp(argv[index], "--extent") == 0 && index + 2 < argc) {
      extent_width = (uint32_t)strtoul(argv[index + 1], NULL, 10);
      extent_height = (uint32_t)strtoul(argv[index + 2], NULL, 10);
      index += 3;
    } else if (strcmp(argv[index], "--from") == 0 && index + 2 < argc) {
      from_x = strtod(argv[index + 1], NULL);
      from_y = strtod(argv[index + 2], NULL);
      index += 3;
    } else {
      return fail("usage: omahub-pointer --extent <width> <height> --from <x> <y> [command...]");
    }
  }
  if (extent_width == 0 || extent_height == 0 || from_x < 0 || from_y < 0) {
    return fail("usage: omahub-pointer --extent <width> <height> --from <x> <y> [command...]");
  }

  display = wl_display_connect(NULL);
  if (display == NULL) return fail("cannot connect to the Wayland display");

  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  wl_display_roundtrip(display);
  if (manager == NULL) return fail("this compositor has no virtual pointer support");

  pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
  wl_display_roundtrip(display);
  sleep_ms(40);
  position_x = from_x;
  position_y = from_y;
  srand48((long)now_ms() ^ (long)getpid());

  while (index < argc) {
    const char *command = argv[index];
    const char *first = argument(argc, argv, index + 1);
    const char *second = argument(argc, argv, index + 2);
    const char *third = argument(argc, argv, index + 3);

    if (strcmp(command, "move") == 0 && third != NULL) {
      move_to(strtod(first, NULL), strtod(second, NULL), strtol(third, NULL, 10));
      index += 4;
    } else if (strcmp(command, "glide") == 0 && third != NULL) {
      glide_to(strtod(first, NULL), strtod(second, NULL), strtol(third, NULL, 10));
      index += 4;
    } else if ((strcmp(command, "down") == 0 || strcmp(command, "up") == 0 || strcmp(command, "click") == 0)
               && first != NULL) {
      int code = button_code(first);
      if (code < 0) return fail("buttons are left, right, or middle");
      if (strcmp(command, "up") != 0) button(code, 1);
      if (strcmp(command, "click") == 0) sleep_ms(40);
      if (strcmp(command, "down") != 0) button(code, 0);
      index += 2;
    } else if (strcmp(command, "scroll") == 0 && first != NULL) {
      scroll((int)strtol(first, NULL, 10));
      index += 2;
    } else if (strcmp(command, "wait") == 0 && first != NULL) {
      sleep_ms(strtol(first, NULL, 10));
      index += 2;
    } else {
      return fail("commands are move or glide <x> <y> <ms>, down, up, or click <button>, scroll <steps>, and wait <ms>");
    }
  }

  wl_display_roundtrip(display);
  zwlr_virtual_pointer_v1_destroy(pointer);
  zwlr_virtual_pointer_manager_v1_destroy(manager);
  wl_display_roundtrip(display);
  wl_display_disconnect(display);
  return 0;
}
