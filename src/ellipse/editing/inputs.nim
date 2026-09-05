## Default action identifiers and bindings used by the built-in world editor.
import ellipse/inputs
import sdl3

const
  GameCameraForward* = "game.camera.forward"
  GameCameraBackward* = "game.camera.backward"
  GameCameraLeft* = "game.camera.left"
  GameCameraRight* = "game.camera.right"
  GameCameraUp* = "game.camera.up"
  GameCameraDown* = "game.camera.down"
  GameCameraLook* = "game.camera.look"
  GamePrimary* = "game.primary"
  GamePlaceCursor* = "game.place_cursor"
  GameMeshRotatePlaneLeft* = "game.mesh.rotate_plane_left"
  GameMeshRotatePlaneRight* = "game.mesh.rotate_plane_right"
  GameMeshClearSelection* = "game.mesh.clear_selection"
  GameMeshKeyboardMove* = "game.mesh.keyboard_move"
  GameMeshMultiSelect* = "game.mesh.multi_select"
  GameToggleTextureFiltering* = "game.toggle_texture_filtering"
  GameModelDelete* = "game.model.delete"

proc installDefaultEditorInputBindings*(inputs: var InputMap) =
  inputs.bindings:
    action(GameCameraForward, key(SCANCODE_W))
    action(GameCameraBackward, key(SCANCODE_S))
    action(GameCameraLeft, key(SCANCODE_A))
    action(GameCameraRight, key(SCANCODE_D))
    action(GameCameraUp, key(SCANCODE_SPACE))
    action(GameCameraDown, key(SCANCODE_LSHIFT))
    action(GameCameraDown, key(SCANCODE_RSHIFT))
    action(GameCameraLook, mouseButton(BUTTON_RIGHT))
    action(GamePrimary, mouseButton(BUTTON_LEFT))
    action(GamePlaceCursor, mouseButton(BUTTON_MIDDLE))
    action(GameMeshRotatePlaneLeft, key(SCANCODE_COMMA))
    action(GameMeshRotatePlaneRight, key(SCANCODE_PERIOD))
    action(GameMeshClearSelection, key(SCANCODE_ESCAPE))
    action(GameMeshKeyboardMove, key(SCANCODE_LALT))
    action(GameMeshKeyboardMove, key(SCANCODE_RALT))
    action(GameMeshMultiSelect, key(SCANCODE_LCTRL))
    action(GameMeshMultiSelect, key(SCANCODE_RCTRL))
    action(GameToggleTextureFiltering, key(SCANCODE_F3))
    action(GameModelDelete, key(SCANCODE_DELETE))
