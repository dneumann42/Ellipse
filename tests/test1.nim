# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import std/[os, streams, times, unittest]

import ellipse/profiles
import ellipse/scenes

test "profile metadata round-trips through owl":
  let original = Profile(
    id: "profile-1",
    name: "Dana \"D\"",
    lastWritten: dateTime(2024, mJan, 2, 3, 4, 5, zone = utc())
  )
  let stream = newStringStream()

  original.write(stream)
  stream.setPosition(0)

  var loaded: Profile
  loaded.read(stream)

  check loaded.id == original.id
  check loaded.name == original.name
  check loaded.lastWritten == original.lastWritten

test "scene stack round-trips through owl":
  let stream = newStringStream("""
{}:
  goto = []
  load = []
  push = []
  stack = []:
    "mainMenu"
    "settings"
  unload = []
""")

  var loaded = SceneStack.init()
  loaded.read(stream)

  check loaded.activeScene == "settings"

  let output = newStringStream()
  loaded.write(output)
  output.setPosition(0)

  var reloaded = SceneStack.init()
  reloaded.read(output)

  check reloaded.activeScene == "settings"

test "restored scene stack schedules active scene load":
  let previousDir = getCurrentDir()
  let testDir = getTempDir() / ("ellipse-scene-stack-test-" & $epochTime())
  if not dirExists(testDir):
    createDir(testDir)
  setCurrentDir(testDir)
  defer:
    setCurrentDir(previousDir)
    removeFile(testDir / "scene-stack.owl")
    removeDir(testDir)

  writeFile("scene-stack.owl", """
{}:
  goto = []
  load = []
  push = []
  stack = []:
    "MainMenuScene"
  unload = []
""")

  var loaded = SceneStack.init()
  loaded.loadSceneStackState()

  check loaded.activeScene == "MainMenuScene"
  check loaded.shouldLoad("MainMenuScene")
