{.push raises: [].}
import std/[algorithm, tables, os, streams, strutils]
import ellipse/worlds/worlds
export worlds

type
  WorldsRegistry* = object
    worlds: Table[string, World]

  WorldsRegistryError* = object of CatchableError

proc getWorldsDirectory*(): string {.raises: [OSError].} =
  getCurrentDir() / "data" / "worlds"

proc init*(T: typedesc[WorldsRegistry]): T =
  T(worlds: initTable[string, World]())

proc validWorldID*(worldID: WorldID): bool =
  let id = worldID.strip()
  id.len > 0 and not id.contains(DirSep) and not id.contains(AltSep) and
      not id.contains('\0')

proc load*(self: var WorldsRegistry, worldID: WorldID) =
  if not validWorldID(worldID):
    debugEcho "Failed to load world: invalid world id"
    return
  try:
    let fstream = openFileStream(getWorldsDirectory() / worldID /
        "data.world", fmRead)
    var world = World.init("")
    fstream.read(world)
    self.worlds[world.name] = world
    fstream.close()
  except:
    debugEcho "Failed to load world: ", worldID, " ", getCurrentExceptionMsg()

proc loadAll*(self: var WorldsRegistry) =
  self.worlds.clear()
  try:
    for (kind, path) in walkDir(getWorldsDirectory()):
      if kind != pcDir:
        continue
      try:
        let fstream = openFileStream(path / "data.world", fmRead)
        var world = World.init("")
        fstream.read(world)
        fstream.close()
        if validWorldID(world.name):
          self.worlds[world.name] = world
        else:
          debugEcho "Failed to load world: invalid world id in ", path
      except:
        debugEcho "Failed to load world: ", path, " ", getCurrentExceptionMsg()
  except:
    debugEcho "Failed to load all worlds", getCurrentExceptionMsg()

proc contains*(self: WorldsRegistry, worldID: WorldID): bool =
  self.worlds.hasKey(worldID)

proc worldIDs*(self: WorldsRegistry): seq[WorldID] =
  for worldID in self.worlds.keys:
    result.add worldID.WorldID
  result.sort()

proc getOrDefault*(self: WorldsRegistry, worldID: WorldID): World =
  self.worlds.withValue(worldID, world):
    result = world
  do:
    result = World.init(worldID)

proc getPtr*(self: var WorldsRegistry, worldID: WorldID): ptr World =
  self.worlds.withValue(worldID, world):
    result = addr world[]
  do:
    result = nil

proc put*(self: var WorldsRegistry, world: World) =
  self.worlds[world.name] = world

proc save*(self: var WorldsRegistry, world: World): bool {.discardable.} =
  if not validWorldID(world.name):
    debugEcho "Failed to save world: invalid world id"
    return false
  let dir =
    try:
      getWorldsDirectory() / world.name
    except:
      ""
  try:
    createDir(dir)
  except:
    debugEcho "Failed to create world directory", getCurrentExceptionMsg()
  try:
    let fstream = openFileStream(dir / "data.world", fmWrite)
    fstream.write(world)
    fstream.close()
    self.put(world)
    result = true
  except:
    debugEcho "Failed to open data file stream for world: ",
        getCurrentExceptionMsg()

proc save*(self: var WorldsRegistry, worldID: WorldID): bool {.discardable.} =
  self.save(World.init(worldID))

proc create*(self: var WorldsRegistry, worldID: WorldID): bool {.discardable.} =
  self.save(worldID)

{.pop.}

when isMainModule:
  var registry = WorldsRegistry.init()
  registry.loadAll()
  echo registry
