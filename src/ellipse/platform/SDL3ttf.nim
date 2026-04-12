{.passL: "-lSDL3_ttf".}

import ./SDL3

type
  TTF_Font* {.importc: "TTF_Font", header: "<SDL3_ttf/SDL_ttf.h>", incompleteStruct.} = object

proc initTTF*(): bool {.
  importc: "TTF_Init",
  header: "<SDL3_ttf/SDL_ttf.h>"
.}

proc quitTTF*() {.
  importc: "TTF_Quit",
  header: "<SDL3_ttf/SDL_ttf.h>"
.}

proc openFont*(file: cstring; ptsize: cfloat): ptr TTF_Font {.
  importc: "TTF_OpenFont",
  header: "<SDL3_ttf/SDL_ttf.h>"
.}

proc closeFont*(font: ptr TTF_Font) {.
  importc: "TTF_CloseFont",
  header: "<SDL3_ttf/SDL_ttf.h>"
.}

proc setFontSize*(font: ptr TTF_Font; ptsize: cfloat): bool {.
  importc: "TTF_SetFontSize",
  header: "<SDL3_ttf/SDL_ttf.h>"
.}

proc getFontHeight*(font: ptr TTF_Font): cint {.
  importc: "TTF_GetFontHeight",
  header: "<SDL3_ttf/SDL_ttf.h>"
.}

proc getStringSize*(
  font: ptr TTF_Font;
  text: cstring;
  length: csize_t;
  w: ptr cint;
  h: ptr cint
): bool {.
  importc: "TTF_GetStringSize",
  header: "<SDL3_ttf/SDL_ttf.h>"
.}

proc renderTextBlended*(
  font: ptr TTF_Font;
  text: cstring;
  length: csize_t;
  fg: Color
): ptr Surface {.
  importc: "TTF_RenderText_Blended",
  header: "<SDL3_ttf/SDL_ttf.h>"
.}
