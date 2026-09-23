// Synthetic window with a separate cyan subsurface in the lower-right quadrant.
// This catches capture implementations that scale the main image but crop child
// surfaces using destination dimensions before transforming their coordinates.
#define _GNU_SOURCE
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client.h"

static struct wl_compositor *compositor;
static struct wl_subcompositor *subcompositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm;
static struct wl_surface *root, *child;
static struct wl_buffer *root_buffer, *child_buffer;
static int width, height, mapped;

static void ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
    xdg_wm_base_pong(base, serial);
}
static const struct xdg_wm_base_listener wm_listener = {.ping = ping};

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (!strcmp(interface, "wl_compositor"))
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (!strcmp(interface, "wl_subcompositor"))
        subcompositor = wl_registry_bind(registry, name, &wl_subcompositor_interface, 1);
    else if (!strcmp(interface, "wl_shm"))
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (!strcmp(interface, "xdg_wm_base")) {
        wm = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(wm, &wm_listener, NULL);
    }
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {.global = global, .global_remove = removed};

static struct wl_buffer *buffer(int w, int h, int cyan) {
    int fd = memfd_create("capture-subsurface", MFD_CLOEXEC);
    assert(fd >= 0);
    size_t length = (size_t)w * h * 4;
    assert(ftruncate(fd, length) == 0);
    uint32_t *pixels = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    assert(pixels != MAP_FAILED);
    const uint32_t colors[] = {0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffff00};
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x)
            pixels[y * w + x] = cyan ? 0xff00ffff : colors[(y >= h / 2) * 2 + (x >= w / 2)];
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, length);
    struct wl_buffer *result = wl_shm_pool_create_buffer(pool, 0, w, h, w * 4, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    munmap(pixels, length);
    close(fd);
    return result;
}

static void configure(void *data, struct xdg_surface *surface, uint32_t serial) {
    xdg_surface_ack_configure(surface, serial);
    if (mapped) return;
    mapped = 1;
    wl_surface_attach(child, child_buffer, 0, 0);
    wl_surface_damage_buffer(child, 0, 0, width / 10, height / 10);
    wl_surface_commit(child);
    wl_surface_attach(root, root_buffer, 0, 0);
    wl_surface_damage_buffer(root, 0, 0, width, height);
    wl_surface_commit(root);
}
static const struct xdg_surface_listener surface_listener = {.configure = configure};
static void toplevel_configure(void *data, struct xdg_toplevel *top, int32_t w, int32_t h, struct wl_array *states) {}
static void close_window(void *data, struct xdg_toplevel *top) { exit(0); }
static const struct xdg_toplevel_listener top_listener = {.configure = toplevel_configure, .close = close_window};

int main(void) {
    width = atoi(getenv("CAPTURE_WIDTH") ? getenv("CAPTURE_WIDTH") : "1280");
    height = atoi(getenv("CAPTURE_HEIGHT") ? getenv("CAPTURE_HEIGHT") : "720");
    assert(width >= 100 && height >= 100);
    struct wl_display *display = wl_display_connect(NULL);
    assert(display);
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    assert(wl_display_roundtrip(display) >= 0);
    assert(compositor && subcompositor && shm && wm);
    root = wl_compositor_create_surface(compositor);
    child = wl_compositor_create_surface(compositor);
    struct wl_subsurface *subsurface = wl_subcompositor_get_subsurface(subcompositor, child, root);
    wl_subsurface_set_position(subsurface, width * 6 / 10, height * 6 / 10);
    root_buffer = buffer(width, height, 0);
    child_buffer = buffer(width / 10, height / 10, 1);
    struct xdg_surface *surface = xdg_wm_base_get_xdg_surface(wm, root);
    xdg_surface_add_listener(surface, &surface_listener, NULL);
    struct xdg_toplevel *top = xdg_surface_get_toplevel(surface);
    xdg_toplevel_add_listener(top, &top_listener, NULL);
    xdg_toplevel_set_title(top, "Capture probe subsurface");
    xdg_toplevel_set_app_id(top, "capture-benchmark-subsurface");
    xdg_toplevel_set_min_size(top, width, height);
    xdg_toplevel_set_max_size(top, width, height);
    wl_surface_commit(root);
    while (wl_display_dispatch(display) >= 0) {}
    return 0;
}
