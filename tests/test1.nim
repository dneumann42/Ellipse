import unittest
import os

import ellipse/platform/SDL3
import ellipse/platform/SDL3ext

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
