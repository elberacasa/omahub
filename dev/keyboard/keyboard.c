// omahub-keyboard: a virtual keyboard for dev/agent. It loads the same keymap as the keyboard at the
// desk, so every key reaches Hyprland the way a physical key does: bindings, release bindings, key
// sets, held modifiers, and number keys on any layout. No root access and no extra package are needed.
//
//   omahub-keyboard --layout <layout> [--variant <v>] [--options <o>] [--rules <r>] [--model <m>] run <commands...>
//   omahub-keyboard --layout <layout> [...] serve <command fifo> <reply fifo>
//
// Commands run in order:
//   down <key>    press a key and keep it down, by keysym name (Super_L, Tab, 5, u) or code:<xkb keycode>
//   up <key>      let it go
//   tap <key>     press and let go
//   wait <ms>     pause
//   release       let go of every key still down
//   ping          do nothing, to check the keyboard answers
//   quit          stop serving
//
// When serving, each line is "<id> <commands...>" and its answer, "<id> ok" or "<id> error <why>", is
// written to the reply fifo once Hyprland has the keys. Keys still down are let go when it stops.

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

#include "virtual-keyboard-unstable-v1-client-protocol.h"

static struct wl_display *display;
static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *manager;
static struct zwp_virtual_keyboard_v1 *keyboard;
static struct xkb_context *context;
static struct xkb_keymap *keymap;
static struct xkb_state *state;
static bool held[256];
static bool quitting;
static volatile sig_atomic_t stopping;

static void handle_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
                          uint32_t version) {
  (void)data;
  (void)version;
  if (strcmp(interface, wl_seat_interface.name) == 0 && seat == NULL) {
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
  } else if (strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name) == 0) {
    manager = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
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

static void handle_signal(int signal) {
  (void)signal;
  stopping = 1;
}

static uint32_t now_ms(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000);
}

static void sleep_ms(long ms) {
  struct timespec duration = { ms / 1000, (ms % 1000) * 1000000L };
  nanosleep(&duration, NULL);
}

static int fail(const char *message) {
  fprintf(stderr, "omahub-keyboard: %s\n", message);
  return 1;
}

static bool write_all(int fd, const char *text, size_t size) {
  while (size > 0) {
    ssize_t written = write(fd, text, size);
    if (written < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    text += written;
    size -= (size_t)written;
  }
  return true;
}

static bool upload_keymap(void) {
  char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
  if (text == NULL) return false;
  size_t size = strlen(text) + 1;
  int fd = memfd_create("omahub-keyboard-keymap", MFD_CLOEXEC);
  bool ok = fd >= 0 && write_all(fd, text, size);
  free(text);
  if (ok) zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, (uint32_t)size);
  if (fd >= 0) close(fd);
  return ok;
}

// A key by the keysym it types without modifiers, or by its xkb keycode. A symbol only reached with
// Shift, such as N, is not a key of its own: press Shift_L and n instead.
static xkb_keycode_t keycode_for(const char *name) {
  if (strncmp(name, "code:", 5) == 0) {
    char *end;
    long code = strtol(name + 5, &end, 10);
    return *end == '\0' && code > 8 && code < 256 ? (xkb_keycode_t)code : XKB_KEYCODE_INVALID;
  }
  xkb_keysym_t wanted = xkb_keysym_from_name(name, XKB_KEYSYM_NO_FLAGS);
  if (wanted == XKB_KEY_NoSymbol) wanted = xkb_keysym_from_name(name, XKB_KEYSYM_CASE_INSENSITIVE);
  if (wanted == XKB_KEY_NoSymbol) return XKB_KEYCODE_INVALID;
  xkb_keycode_t max = xkb_keymap_max_keycode(keymap);
  for (xkb_keycode_t code = xkb_keymap_min_keycode(keymap); code <= max && code < 256; code++) {
    const xkb_keysym_t *symbols;
    int count = xkb_keymap_key_get_syms_by_level(keymap, code, 0, 0, &symbols);
    for (int i = 0; i < count; i++) {
      if (symbols[i] == wanted) return code;
    }
  }
  return XKB_KEYCODE_INVALID;
}

// The key first, then the modifiers it leaves, in the order a physical keyboard reports them, so a
// release binding still sees SUPER on the key that lets SUPER go.
static void send_key(xkb_keycode_t code, bool pressed) {
  zwp_virtual_keyboard_v1_key(keyboard, now_ms(), code - 8,
                              pressed ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED);
  xkb_state_update_key(state, code, pressed ? XKB_KEY_DOWN : XKB_KEY_UP);
  zwp_virtual_keyboard_v1_modifiers(keyboard, xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED),
                                    xkb_state_serialize_mods(state, XKB_STATE_MODS_LATCHED),
                                    xkb_state_serialize_mods(state, XKB_STATE_MODS_LOCKED),
                                    xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE));
  held[code] = pressed;
  wl_display_flush(display);
}

static void release_all(void) {
  for (int code = 0; code < 256; code++) {
    if (held[code]) send_key((xkb_keycode_t)code, false);
  }
}

// Runs commands from words, and returns NULL when they all ran or why one could not.
static const char *run(char **words, int count) {
  static char why[160];
  for (int index = 0; index < count; index++) {
    const char *command = words[index];
    const char *value = index + 1 < count ? words[index + 1] : NULL;
    if (strcmp(command, "down") == 0 || strcmp(command, "up") == 0 || strcmp(command, "tap") == 0) {
      if (value == NULL) return "down, up, and tap need a key";
      xkb_keycode_t code = keycode_for(value);
      if (code == XKB_KEYCODE_INVALID) {
        snprintf(why, sizeof why, "no key types %s on this layout without modifiers", value);
        return why;
      }
      if (strcmp(command, "up") != 0) send_key(code, true);
      if (strcmp(command, "tap") == 0) sleep_ms(30);
      if (strcmp(command, "down") != 0) send_key(code, false);
      index++;
    } else if (strcmp(command, "wait") == 0) {
      if (value == NULL) return "wait needs milliseconds";
      sleep_ms(strtol(value, NULL, 10));
      index++;
    } else if (strcmp(command, "release") == 0) {
      release_all();
    } else if (strcmp(command, "quit") == 0) {
      quitting = true;
    } else if (strcmp(command, "ping") != 0) {
      snprintf(why, sizeof why, "unknown command %s", command);
      return why;
    }
    sleep_ms(12);
  }
  // Answer only once Hyprland has every key, so the next check sees their effect.
  wl_display_roundtrip(display);
  return NULL;
}

// The reply fifo has a reader only while dev/agent waits, so an answer nobody waits for is dropped
// after a moment instead of blocking the keyboard.
static void reply(const char *path, const char *id, const char *why) {
  for (int tries = 0; tries < 400; tries++) {
    int fd = open(path, O_WRONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd >= 0) {
      if (why == NULL) {
        dprintf(fd, "%s ok\n", id);
      } else {
        dprintf(fd, "%s error %s\n", id, why);
      }
      close(fd);
      return;
    }
    if (errno != ENXIO && errno != EINTR) return;
    sleep_ms(5);
  }
}

static int serve(const char *command_path, const char *reply_path) {
  // Opened for reading and writing, so the fifo never reaches end of file between commands.
  int fd = open(command_path, O_RDWR | O_CLOEXEC);
  if (fd < 0) return fail("cannot open the command fifo");
  FILE *commands = fdopen(fd, "r");
  char *line = NULL;
  size_t capacity = 0;

  while (!stopping && !quitting) {
    ssize_t length = getline(&line, &capacity, commands);
    if (length < 0) {
      if (errno == EINTR && !stopping) {
        clearerr(commands);
        continue;
      }
      break;
    }
    char *words[64];
    int count = 0;
    char *save = NULL;
    char *word = strtok_r(line, " \t\n", &save);
    for (; word != NULL && count < 64; word = strtok_r(NULL, " \t\n", &save)) {
      words[count++] = word;
    }
    if (count == 0) continue;
    // A longer command would lose its end without a word, so it is refused whole instead.
    if (word != NULL) {
      reply(reply_path, words[0], "a command holds at most 63 words");
      continue;
    }
    reply(reply_path, words[0], run(words + 1, count - 1));
  }

  free(line);
  fclose(commands);
  return 0;
}

int main(int argc, char **argv) {
  struct xkb_rule_names names = { 0 };
  int index = 1;

  while (index + 1 < argc && strncmp(argv[index], "--", 2) == 0) {
    const char *option = argv[index];
    const char *value = argv[index + 1];
    if (strcmp(option, "--layout") == 0) names.layout = value;
    else if (strcmp(option, "--variant") == 0) names.variant = value;
    else if (strcmp(option, "--options") == 0) names.options = value;
    else if (strcmp(option, "--rules") == 0) names.rules = value;
    else if (strcmp(option, "--model") == 0) names.model = value;
    else return fail("options are --layout, --variant, --options, --rules, and --model");
    index += 2;
  }
  const char *mode = index < argc ? argv[index] : NULL;
  bool serving = mode != NULL && strcmp(mode, "serve") == 0;
  if (names.layout == NULL || mode == NULL || (!serving && strcmp(mode, "run") != 0) || (serving && index + 2 >= argc)) {
    return fail("usage: omahub-keyboard --layout <layout> [--variant <v>] [--options <o>] run <commands...> | serve <command fifo> <reply fifo>");
  }
  for (const char **field = &names.rules; field <= &names.options; field++) {
    if (*field != NULL && **field == '\0') *field = NULL;
  }

  context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  keymap = context ? xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS) : NULL;
  if (keymap == NULL) return fail("cannot build a keymap for that layout");
  state = xkb_state_new(keymap);

  display = wl_display_connect(NULL);
  if (display == NULL) return fail("cannot connect to the Wayland display");
  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  wl_display_roundtrip(display);
  if (manager == NULL || seat == NULL) return fail("this compositor has no virtual keyboard support");

  keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
  if (!upload_keymap()) return fail("cannot hand the keymap to the compositor");
  wl_display_roundtrip(display);
  sleep_ms(60);

  struct sigaction action = { 0 };
  action.sa_handler = handle_signal;
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);
  signal(SIGPIPE, SIG_IGN);

  int status = 0;
  if (serving) {
    status = serve(argv[index + 1], argv[index + 2]);
  } else {
    const char *why = run(argv + index + 1, argc - index - 1);
    if (why != NULL) status = fail(why);
  }

  release_all();
  wl_display_roundtrip(display);
  zwp_virtual_keyboard_v1_destroy(keyboard);
  zwp_virtual_keyboard_manager_v1_destroy(manager);
  wl_display_roundtrip(display);
  wl_display_disconnect(display);
  xkb_state_unref(state);
  xkb_keymap_unref(keymap);
  xkb_context_unref(context);
  return status;
}
