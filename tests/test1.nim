import unittest
import os

import ellipse/platform/SDL3
import ellipse/platform/SDL3ext
import ellipse/platform/SDL3gpu
import ellipse/platform/SDL3gpuext
import ellipse/rendering/artist2D
import ellipse/rendering/canvases

suite "SDL3 binding smoke tests":
  test "core constants are available":
    check INIT_VIDEO == 0x20'u32
    check EVENT_QUIT == 0x100'u32
    check EVENT_WINDOW_CLOSE_REQUESTED == 0x210'u32
    check PIXELFORMAT_RGBA8888 == 0x16462004'u32
    check AUDIO_S16LE == 0x8010'u16

  test "event layout exposes the type field":
    var event: Event
    event.`type` = EVENT_QUIT
    check event.`type` == EVENT_QUIT

suite "SDL3 GPU binding smoke tests":
  test "gpu constants are available":
    check GPU_SHADERFORMAT_SPIRV == 0x2'u32
    check GPU_TEXTUREFORMAT_R8G8B8A8_UNORM == 0x4'u32
    check GPU_TEXTUREUSAGE_SAMPLER == 0x1'u32
    check GPU_BUFFERUSAGE_VERTEX == 0x1'u32

  test "gpu structs expose expected fields":
    var samplerInfo = GPUSamplerCreateInfo(
      min_filter: gpuFilterNearest,
      mag_filter: gpuFilterNearest,
      mipmap_mode: gpuSamplerMipmapModeNearest,
      address_mode_u: gpuSamplerAddressModeRepeat,
      address_mode_v: gpuSamplerAddressModeRepeat,
      address_mode_w: gpuSamplerAddressModeRepeat
    )
    check samplerInfo.min_filter == gpuFilterNearest
    check samplerInfo.address_mode_u == gpuSamplerAddressModeRepeat

  test "texture filter enum defaults to linear":
    check default(TextureFilterMode) == tfLinear

  test "gpu handle wrappers compile":
    var device: GPUDeviceHandle
    var texture: GPUTextureHandle
    check raw(device).isNil
    check raw(texture).isNil

suite "Artist2D primitives":
  test "circle segment count clamps to supported range":
    check primitiveCircleSegmentCount(0'f32) == 0
    check primitiveCircleSegmentCount(1'f32) == 12
    check primitiveCircleSegmentCount(24'f32) >= primitiveCircleSegmentCount(8'f32)
    check primitiveCircleSegmentCount(1_000'f32) == 96

  test "primitive helper signatures compile":
    var artist: Artist2D
    check compiles(drawFilledRect(artist, [0'f32, 0'f32], [10'f32, 20'f32], [1'f32, 0'f32, 0'f32, 1'f32]))
    check compiles(drawRect(artist, [0'f32, 0'f32], [10'f32, 20'f32], FColor(r: 1, g: 1, b: 1, a: 1), 2'f32))
    check compiles(drawLine(artist, [0'f32, 0'f32], [8'f32, 8'f32], [1'f32, 1'f32, 1'f32, 1'f32], 3'f32))
    check compiles(drawTriangle(artist, [0'f32, 0'f32], [8'f32, 0'f32], [4'f32, 6'f32], [0'f32, 1'f32, 0'f32, 1'f32]))
    check compiles(drawCircle(artist, [0'f32, 0'f32], 20'f32, FColor(r: 1, g: 0, b: 0, a: 1)))
    check compiles(drawRing(artist, [0'f32, 0'f32], 20'f32, [0'f32, 0'f32, 1'f32, 1'f32], 4'f32))

suite "SDL3ext ownership":
  test "properties are created and owned":
    let props = SDL3ext.createProperties()
    check raw(props) != 0

  test "surface palette and texture wrappers compile and own handles":
    let surface = SDL3ext.createSurface(8, 8, PIXELFORMAT_RGBA8888)
    let palette = SDL3ext.createPalette(4)
    check not raw(surface).isNil
    check not raw(palette).isNil

  test "io streams own file handles":
    let path = getTempDir() / "ellipse-sdl3ext.txt"
    writeFile(path, "ellipse")
    defer:
      if fileExists(path):
        removeFile(path)
    let stream = SDL3ext.openIOFromFile(path, "rb")
    check not raw(stream).isNil

  test "audio streams own conversion handles":
    let spec = AudioSpec(format: AUDIO_S16LE, channels: 2, freq: 48_000)
    let stream = SDL3ext.createAudioStream(spec, spec)
    check not raw(stream).isNil

  test "wav buffers are owned":
    let path = getTempDir() / "ellipse-sdl3ext.wav"
    writeFile(
      path,
      "RIFF" &
      "\x24\x00\x00\x00" &
      "WAVE" &
      "fmt " &
      "\x10\x00\x00\x00" &
      "\x01\x00" &
      "\x01\x00" &
      "\x40\x1F\x00\x00" &
      "\x80\x3E\x00\x00" &
      "\x02\x00" &
      "\x10\x00" &
      "data" &
      "\x04\x00\x00\x00" &
      "\x00\x00\x00\x00"
    )
    defer:
      if fileExists(path):
        removeFile(path)
    let wav = SDL3ext.loadWav(path)
    check wav.len == 4'u32
    check not raw(wav).isNil

suite "Canvas helpers":
  test "canvas validation rejects invalid sizes":
    expect CanvasError:
      validateRenderCanvasConfig(RenderCanvasConfig(
        id: "bad",
        width: 0,
        height: 180,
        destRect: Rect(x: 0, y: 0, w: 320, h: 180)
      ))

  test "default target rect uses full window when canvas rect is unset":
    let rect = resolveCanvasTargetRect(
      RenderCanvasConfig(id: "full", width: 320, height: 180),
      1280'u32,
      720'u32
    )
    check rect.x == 0
    check rect.y == 0
    check rect.w == 1280
    check rect.h == 720

  test "canvas filter defaults to linear":
    check default(RenderCanvasConfig).filterMode == tfLinear

  test "contain scaling centers inside full window by default":
    let rect = canvasCompositeRect(RenderCanvasConfig(
      id: "game",
      width: 320,
      height: 180,
      scaleMode: csmContain
    ), 1280'u32, 720'u32)
    check rect.x == 0'f32
    check rect.y == 0'f32
    check rect.w == 1280'f32
    check rect.h == 720'f32

  test "contain scaling produces left and right bars for taller targets":
    let rect = canvasCompositeRect(RenderCanvasConfig(
      id: "portraitFit",
      width: 320,
      height: 180,
      scaleMode: csmContain
    ), 700'u32, 900'u32)
    check rect.x == 0'f32
    check rect.y == 253.125'f32
    check rect.w == 700'f32
    check rect.h == 393.75'f32

  test "stretch scaling fills full window by default":
    let rect = canvasCompositeRect(RenderCanvasConfig(
      id: "hud",
      width: 320,
      height: 180,
      scaleMode: csmStretch
    ), 1280'u32, 720'u32)
    check rect.x == 0'f32
    check rect.y == 0'f32
    check rect.w == 1280'f32
    check rect.h == 720'f32

  test "custom rect still overrides full-window presentation":
    let rect = canvasCompositeRect(RenderCanvasConfig(
      id: "custom",
      width: 320,
      height: 180,
      destRect: Rect(x: 10, y: 20, w: 640, h: 360),
      scaleMode: csmStretch
    ), 1280'u32, 720'u32)
    check rect.x == 10'f32
    check rect.y == 20'f32
    check rect.w == 640'f32
    check rect.h == 360'f32

  test "integer scaling uses whole-number upscale and centers":
    let rect = canvasCompositeRect(RenderCanvasConfig(
      id: "pixel",
      width: 320,
      height: 180,
      scaleMode: csmInteger
    ), 1000'u32, 700'u32)
    check rect.x == 20'f32
    check rect.y == 80'f32
    check rect.w == 960'f32
    check rect.h == 540'f32

  test "layer sorting is stable for equal layers":
    let order = sortedCanvasIndicesByLayer([
      RenderCanvasConfig(id: "midA", width: 1, height: 1, destRect: Rect(w: 1, h: 1), layer: 2),
      RenderCanvasConfig(id: "back", width: 1, height: 1, destRect: Rect(w: 1, h: 1), layer: 0),
      RenderCanvasConfig(id: "midB", width: 1, height: 1, destRect: Rect(w: 1, h: 1), layer: 2),
      RenderCanvasConfig(id: "front", width: 1, height: 1, destRect: Rect(w: 1, h: 1), layer: 5)
    ])
    check order == @[1, 0, 2, 3]
