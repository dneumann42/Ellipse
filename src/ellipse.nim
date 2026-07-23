import ellipse/application
export application

when isMainModule:
  plugin Ellipse:
    proc load() =
      echo "Hello"

  buildApplication()

  start()
