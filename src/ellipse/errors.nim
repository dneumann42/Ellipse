type
  EllipseError* = object of CatchableError
  SDLException* = object of EllipseError
  ResourceError* = object of EllipseError
