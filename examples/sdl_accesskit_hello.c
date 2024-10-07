#include <SDL2/SDL.h>
#include <SDL2/SDL_syswm.h>
#include <stdio.h>
#include <stdlib.h>

#include "accesskit.h"

#if (defined(__linux__) || defined(__DragonFly__) || defined(__FreeBSD__) || \
     defined(__NetBSD__) || defined(__OpenBSD__))
#define UNIX
#endif

const char WINDOW_TITLE[] = "Hello world";

const accesskit_node_id WINDOW_ID = 0;
const accesskit_node_id BUTTON_1_ID = 1;
const accesskit_node_id BUTTON_2_ID = 2;
const accesskit_node_id ANNOUNCEMENT_ID = 3;
#define INITIAL_FOCUS BUTTON_1_ID

const accesskit_rect BUTTON_1_RECT = {20.0, 20.0, 100.0, 60.0};

const accesskit_rect BUTTON_2_RECT = {20.0, 60.0, 100.0, 100.0};

const Sint32 SET_FOCUS_MSG = 0;
const Sint32 DO_DEFAULT_ACTION_MSG = 1;

accesskit_node *build_button(accesskit_node_id id, const char *name) {
  accesskit_rect rect;
  if (id == BUTTON_1_ID) {
    rect = BUTTON_1_RECT;
  } else {
    rect = BUTTON_2_RECT;
  }

  accesskit_node_builder *builder =
      accesskit_node_builder_new(ACCESSKIT_ROLE_BUTTON);
  accesskit_node_builder_set_bounds(builder, rect);
  accesskit_node_builder_set_name(builder, name);
  accesskit_node_builder_add_action(builder, ACCESSKIT_ACTION_FOCUS);
  accesskit_node_builder_set_default_action_verb(
      builder, ACCESSKIT_DEFAULT_ACTION_VERB_CLICK);
  return accesskit_node_builder_build(builder);
}

accesskit_node *build_announcement(const char *text) {
  accesskit_node_builder *builder =
      accesskit_node_builder_new(ACCESSKIT_ROLE_LABEL);
  accesskit_node_builder_set_name(builder, text);
  accesskit_node_builder_set_live(builder, ACCESSKIT_LIVE_POLITE);
  return accesskit_node_builder_build(builder);
}

struct accesskit_sdl_adapter {
#if defined(__APPLE__)
  accesskit_macos_subclassing_adapter *adapter;
#elif defined(UNIX)
  accesskit_unix_adapter *adapter;
#elif defined(_WIN32)
  accesskit_windows_subclassing_adapter *adapter;
#endif
};

void accesskit_sdl_adapter_init(
    struct accesskit_sdl_adapter *adapter, SDL_Window *window,
    accesskit_activation_handler_callback activation_handler,
    void *activation_handler_userdata,
    accesskit_action_handler_callback action_handler,
    void *action_handler_userdata,
    accesskit_deactivation_handler_callback deactivation_handler,
    void *deactivation_handler_userdata) {
#if defined(__APPLE__)
  accesskit_macos_add_focus_forwarder_to_window_class("SDLWindow");
  SDL_SysWMinfo wmInfo;
  SDL_VERSION(&wmInfo.version);
  SDL_GetWindowWMInfo(window, &wmInfo);
  adapter->adapter = accesskit_macos_subclassing_adapter_for_window(
      (void *)wmInfo.info.cocoa.window, activation_handler,
      activation_handler_userdata, action_handler, action_handler_userdata);
#elif defined(UNIX)
  adapter->adapter = accesskit_unix_adapter_new(
      activation_handler, activation_handler_userdata, action_handler,
      action_handler_userdata, deactivation_handler,
      deactivation_handler_userdata);
#elif defined(_WIN32)
  SDL_SysWMinfo wmInfo;
  SDL_VERSION(&wmInfo.version);
  SDL_GetWindowWMInfo(window, &wmInfo);
  adapter->adapter = accesskit_windows_subclassing_adapter_new(
      wmInfo.info.win.window, activation_handler, activation_handler_userdata,
      action_handler, action_handler_userdata);
#endif
}

void accesskit_sdl_adapter_destroy(struct accesskit_sdl_adapter *adapter) {
  if (adapter->adapter != NULL) {
#if defined(__APPLE__)
    accesskit_macos_subclassing_adapter_free(adapter->adapter);
#elif defined(UNIX)
    accesskit_unix_adapter_free(adapter->adapter);
#elif defined(_WIN32)
    accesskit_windows_subclassing_adapter_free(adapter->adapter);
#endif
  }
}

void accesskit_sdl_adapter_update_if_active(
    struct accesskit_sdl_adapter *adapter,
    accesskit_tree_update_factory update_factory,
    void *update_factory_userdata) {
#if defined(__APPLE__)
  accesskit_macos_queued_events *events =
      accesskit_macos_subclassing_adapter_update_if_active(
          adapter->adapter, update_factory, update_factory_userdata);
  if (events != NULL) {
    accesskit_macos_queued_events_raise(events);
  }
#elif defined(UNIX)
  accesskit_unix_adapter_update_if_active(adapter->adapter, update_factory,
                                          update_factory_userdata);
#elif defined(_WIN32)
  accesskit_windows_queued_events *events =
      accesskit_windows_subclassing_adapter_update_if_active(
          adapter->adapter, update_factory, update_factory_userdata);
  if (events != NULL) {
    accesskit_windows_queued_events_raise(events);
  }
#endif
}

void accesskit_sdl_adapter_update_window_focus_state(
    struct accesskit_sdl_adapter *adapter, bool is_focused) {
#if defined(__APPLE__)
  accesskit_macos_queued_events *events =
      accesskit_macos_subclassing_adapter_update_view_focus_state(
          adapter->adapter, is_focused);
  if (events != NULL) {
    accesskit_macos_queued_events_raise(events);
  }
#elif defined(UNIX)
  accesskit_unix_adapter_update_window_focus_state(adapter->adapter,
                                                   is_focused);
#endif
  /* On Windows, the subclassing adapter takes care of this. */
}

void accesskit_sdl_adapter_update_root_window_bounds(
    struct accesskit_sdl_adapter *adapter, SDL_Window *window) {
#if defined(UNIX)
  int x, y, width, height;
  SDL_GetWindowPosition(window, &x, &y);
  SDL_GetWindowSize(window, &width, &height);
  int top, left, bottom, right;
  SDL_GetWindowBordersSize(window, &top, &left, &bottom, &right);
  accesskit_rect outer_bounds = {x - left, y - top, x + width + right,
                                 y + height + bottom};
  accesskit_rect inner_bounds = {x, y, x + width, y + height};
  accesskit_unix_adapter_set_root_window_bounds(adapter->adapter, outer_bounds,
                                                inner_bounds);
#endif
}

struct window_state {
  accesskit_node_id focus;
  const char *announcement;
  SDL_mutex *mutex;
};

void window_state_init(struct window_state *state) {
  state->focus = INITIAL_FOCUS;
  state->announcement = NULL;
  state->mutex = SDL_CreateMutex();
}

void window_state_destroy(struct window_state *state) {
  SDL_DestroyMutex(state->mutex);
}

void window_state_lock(struct window_state *state) {
  SDL_LockMutex(state->mutex);
}

void window_state_unlock(struct window_state *state) {
  SDL_UnlockMutex(state->mutex);
}

accesskit_node *window_state_build_root(const struct window_state *state) {
  accesskit_node_builder *builder =
      accesskit_node_builder_new(ACCESSKIT_ROLE_WINDOW);
  accesskit_node_builder_push_child(builder, BUTTON_1_ID);
  accesskit_node_builder_push_child(builder, BUTTON_2_ID);
  if (state->announcement != NULL) {
    accesskit_node_builder_push_child(builder, ANNOUNCEMENT_ID);
  }
  accesskit_node_builder_set_name(builder, WINDOW_TITLE);
  return accesskit_node_builder_build(builder);
}

accesskit_tree_update *window_state_build_initial_tree(
    const struct window_state *state) {
  accesskit_node *root = window_state_build_root(state);
  accesskit_node *button_1 = build_button(BUTTON_1_ID, "Button 1");
  accesskit_node *button_2 = build_button(BUTTON_2_ID, "Button 2");
  accesskit_tree_update *result = accesskit_tree_update_with_capacity_and_focus(
      (state->announcement != NULL) ? 4 : 3, state->focus);
  accesskit_tree *tree = accesskit_tree_new(WINDOW_ID);
  accesskit_tree_set_app_name(tree, "Hello World");
  accesskit_tree_update_set_tree(result, tree);
  accesskit_tree_update_push_node(result, WINDOW_ID, root);
  accesskit_tree_update_push_node(result, BUTTON_1_ID, button_1);
  accesskit_tree_update_push_node(result, BUTTON_2_ID, button_2);
  if (state->announcement != NULL) {
    accesskit_node *announcement = build_announcement(state->announcement);
    accesskit_tree_update_push_node(result, ANNOUNCEMENT_ID, announcement);
  }
  return result;
}

accesskit_tree_update *build_tree_update_for_button_press(void *userdata) {
  struct window_state *state = userdata;
  accesskit_node *announcement = build_announcement(state->announcement);
  accesskit_node *root = window_state_build_root(state);
  accesskit_tree_update *update =
      accesskit_tree_update_with_capacity_and_focus(2, state->focus);
  accesskit_tree_update_push_node(update, ANNOUNCEMENT_ID, announcement);
  accesskit_tree_update_push_node(update, WINDOW_ID, root);
  return update;
}

void window_state_press_button(struct window_state *state,
                               struct accesskit_sdl_adapter *adapter,
                               accesskit_node_id id) {
  const char *text;
  if (id == BUTTON_1_ID) {
    text = "You pressed button 1";
  } else {
    text = "You pressed button 2";
  }
  state->announcement = text;
  accesskit_sdl_adapter_update_if_active(
      adapter, build_tree_update_for_button_press, state);
}

accesskit_tree_update *build_tree_update_for_focus_update(void *userdata) {
  struct window_state *state = userdata;
  accesskit_tree_update *update =
      accesskit_tree_update_with_focus(state->focus);
  return update;
}

void window_state_set_focus(struct window_state *state,
                            struct accesskit_sdl_adapter *adapter,
                            accesskit_node_id focus) {
  state->focus = focus;
  accesskit_sdl_adapter_update_if_active(
      adapter, build_tree_update_for_focus_update, state);
}

struct action_handler_state {
  Uint32 event_type;
  Uint32 window_id;
};

void do_action(accesskit_action_request *request, void *userdata) {
  struct action_handler_state *state = userdata;
  SDL_Event event;
  SDL_zero(event);
  event.type = state->event_type;
  event.user.windowID = state->window_id;
  event.user.data1 = (void *)((uintptr_t)(request->target));
  if (request->action == ACCESSKIT_ACTION_FOCUS) {
    event.user.code = SET_FOCUS_MSG;
    SDL_PushEvent(&event);
  } else if (request->action == ACCESSKIT_ACTION_DEFAULT) {
    event.user.code = DO_DEFAULT_ACTION_MSG;
    SDL_PushEvent(&event);
  }
  accesskit_action_request_free(request);
}

accesskit_tree_update *build_initial_tree(void *userdata) {
  struct window_state *state = userdata;
  window_state_lock(state);
  accesskit_tree_update *update = window_state_build_initial_tree(state);
  window_state_unlock(state);
  return update;
}

void deactivate_accessibility(void *userdata) {
  /* There's nothing in the state that depends on whether the adapter
     is active, so there's nothing to do here. */
}

int main(int argc, char *argv[]) {
  printf("This example has no visible GUI, and a keyboard interface:\n");
  printf("- [Tab] switches focus between two logical buttons.\n");
  printf(
      "- [Space] 'presses' the button, adding static text in a live region "
      "announcing that it was pressed.\n");
#if defined(_WIN32)
  printf(
      "Enable Narrator with [Win]+[Ctrl]+[Enter] (or [Win]+[Enter] on older "
      "versions of Windows).\n");
#elif defined(UNIX)
  printf("Enable Orca with [Super]+[Alt]+[S].\n");
#endif
  if (SDL_Init(SDL_INIT_VIDEO) != 0) {
    fprintf(stderr, "SDL initialization failed: (%s)\n", SDL_GetError());
    return -1;
  }
  Uint32 user_event = SDL_RegisterEvents(1);
  if (user_event == (Uint32)-1) {
    fprintf(stderr, "Couldn't register user event: (%s)\n", SDL_GetError());
    return -1;
  }

  struct window_state state;
  window_state_init(&state);
  SDL_Window *window =
      SDL_CreateWindow(WINDOW_TITLE, SDL_WINDOWPOS_UNDEFINED,
                       SDL_WINDOWPOS_UNDEFINED, 800, 600, SDL_WINDOW_HIDDEN);
  Uint32 window_id = SDL_GetWindowID(window);
  struct action_handler_state action_handler = {user_event, window_id};
  struct accesskit_sdl_adapter adapter;
  accesskit_sdl_adapter_init(&adapter, window, build_initial_tree, &state,
                             do_action, &action_handler,
                             deactivate_accessibility, &state);
  SDL_ShowWindow(window);

  SDL_Event event;
  while (SDL_WaitEvent(&event)) {
    if (event.type == SDL_QUIT) {
      break;
    } else if (event.type == SDL_WINDOWEVENT &&
               event.window.windowID == window_id) {
      switch (event.window.event) {
        case SDL_WINDOWEVENT_FOCUS_GAINED:
          accesskit_sdl_adapter_update_window_focus_state(&adapter, true);
          break;
        case SDL_WINDOWEVENT_FOCUS_LOST:
          accesskit_sdl_adapter_update_window_focus_state(&adapter, false);
          break;
        case SDL_WINDOWEVENT_MAXIMIZED:
        case SDL_WINDOWEVENT_MOVED:
        case SDL_WINDOWEVENT_RESIZED:
        case SDL_WINDOWEVENT_RESTORED:
        case SDL_WINDOWEVENT_SIZE_CHANGED:
        case SDL_WINDOWEVENT_SHOWN:
          accesskit_sdl_adapter_update_root_window_bounds(&adapter, window);
          break;
      }
    } else if (event.type == SDL_KEYDOWN && event.key.windowID == window_id) {
      switch (event.key.keysym.sym) {
        case SDLK_TAB:
          window_state_lock(&state);
          accesskit_node_id new_focus =
              (state.focus == BUTTON_1_ID) ? BUTTON_2_ID : BUTTON_1_ID;
          window_state_set_focus(&state, &adapter, new_focus);
          window_state_unlock(&state);
          break;
        case SDLK_SPACE:
          window_state_lock(&state);
          accesskit_node_id id = state.focus;
          window_state_press_button(&state, &adapter, id);
          window_state_unlock(&state);
          break;
      }
    } else if (event.type == user_event && event.user.windowID == window_id) {
      accesskit_node_id target =
          (accesskit_node_id)((uintptr_t)(event.user.data1));
      if (target == BUTTON_1_ID || target == BUTTON_2_ID) {
        window_state_lock(&state);
        if (event.user.code == SET_FOCUS_MSG) {
          window_state_set_focus(&state, &adapter, target);
        } else if (event.user.code == DO_DEFAULT_ACTION_MSG) {
          window_state_press_button(&state, &adapter, target);
        }
        window_state_unlock(&state);
      }
    }
  }

  accesskit_sdl_adapter_destroy(&adapter);
  window_state_destroy(&state);
  SDL_Quit();
  return 0;
}
