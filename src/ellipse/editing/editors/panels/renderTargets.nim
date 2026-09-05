## Live GPU target inspector used by the editor.
import std/os

import ellipse
import nest/screen as nestScreen

import ../uihelpers

const
  SceneTargetImagePath* = "ellipse:target:scene"
  DepthTargetImagePath* = "ellipse:target:depth"
  AmbientOcclusionTargetImagePath* = "ellipse:target:ao"
  CompositeTargetImagePath* = "ellipse:target:composite"

proc registerRenderTargetImages*(artist: Artist3D) =
  let size = artist.renderTargetSize()
  template register(path: string, target: RenderTarget) =
    let texture = artist.renderTarget(target)
    setNestExternalTexture(path, texture, size.width, size.height)
    # Nest canonicalizes image paths before loading them. Register both forms
    # so virtual GPU textures never fall back to disk IO.
    setNestExternalTexture(path.absolutePath, texture, size.width, size.height)
  register(SceneTargetImagePath, SceneColorTarget)
  register(DepthTargetImagePath, DepthTarget)
  register(AmbientOcclusionTargetImagePath, AmbientOcclusionTarget)
  register(CompositeTargetImagePath, CompositeTarget)

widget renderTargetPreview*(title, path: string):
  ui.scope(title):
    ui.card(ui.id(), cfg(width = fill(), height = fixed(154), gap = 5, padding = 7)):
      ui.label(title, fill(), fixed(20))
      ui.image(ui.id("image"), path, fill(), fill())

widget renderTargetsPanel*():
  ui.panel(ui.id("render targets panel"), cfg(width = fixed(260),
      height = fill(), gap = 0, padding = 0,
      style = ComponentStyle(hasBackground: true, background: nestScreen.color(
          25, 31, 34, 210)))):
    ui.panelHeader("render targets panel", "Render Targets")
    ui.column(ui.id("render target list"), cfg(width = fill(), height = fill(
        ), gap = 8, padding = 8, scrollY = true)):
      ui.renderTargetPreview("Scene color", SceneTargetImagePath)
      ui.renderTargetPreview("Depth", DepthTargetImagePath)
      ui.renderTargetPreview("SSAO", AmbientOcclusionTargetImagePath)
      ui.renderTargetPreview("Composite", CompositeTargetImagePath)
