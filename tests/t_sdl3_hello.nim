import ellipse/platform/application

type
  DemoState = object

when isMainModule:
  startApplication(
    AppConfig(
      appId: "dev.ellipse.tests.sdl3hello",
      title: "Ellipse SDL3 Hello",
      width: 800,
      height: 600,
      windowFlags: 0
    ),
    DemoState()
  )
