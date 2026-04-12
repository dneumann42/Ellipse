import unittest
import os

import ellipse/platform/SDL3
import ellipse/platform/SDL3ext
import ellipse/platform/SDL3gpu
import ellipse/platform/SDL3gpuext

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

  test "gpu handle wrappers compile":
    var device: GPUDeviceHandle
    var texture: GPUTextureHandle
    check raw(device).isNil
    check raw(texture).isNil

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
