import sdl3

type
  EllipseError* = object of CatchableError
  SDLException* = object of EllipseError
  ResourceError* = object of EllipseError

proc raiseSdlError*(context: string) {.noreturn.} =
  raise SDLException.newException(context & ": " & $sdl3.getError())

template checkSdl*(success: bool, context: string) =
  if not success:
    raiseSdlError(context)
