when defined(windows):
  const SdlImageLibName* = "SDL3_image.dll"
elif defined(macosx):
  const SdlImageLibName* = "libSDL3_image.dylib"
else:
  const SdlImageLibName* = "libSDL3_image.so"
