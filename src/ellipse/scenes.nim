import std/[sets, options, sequtils, macros]

import plugnim

type
  SceneID* = string
  SceneStep* = enum
    Init
    Load
    Unload
    UI
    Update
    Draw
  SceneStack* = object
    load, push, goto, unload: HashSet[SceneID]
    stack: seq[SceneID]

proc init*(T: typedesc[SceneStack]): T =
  T(stack: @[])

proc activeScene*(self: SceneStack): SceneID =
  result = ""
  try:
    if self.stack.len == 0:
      return
    result = self.stack[^1]
  except:
    discard

proc isSceneActive*(self: SceneStack, id: SceneID): bool =
  result = self.activeScene() == id

proc shouldLoad*(self: SceneStack, id: SceneID): bool =
  result = self.load.contains(id)

proc shouldUnload*(self: SceneStack, id: SceneID): bool =
  result = self.unload.contains(id)

proc push*(self: var SceneStack, newScene: SceneID) =
  self.push.incl(newScene)

proc pop*(self: var SceneStack): SceneID {.discardable.} =
  result = ""
  if self.stack.len == 0:
    return
  result = self.stack[^1]
  discard self.stack.pop()
  self.unload.incl(result)

proc goto*(self: var SceneStack, sceneId: SceneID): SceneID =
  result = self.pop()
  self.push(sceneId)

proc handlePushed*(self: var SceneStack) =
  var pushed = self.push.items.toSeq()
  for p in pushed:
    self.stack.add(p)
    self.push.excl(p)
    self.load.incl(p)

proc handleLoads*(self: var SceneStack) =
  self.load.clear()

proc handleUnloads*(self: var SceneStack) =
  self.unload.clear()

macro scene*(args: varargs[untyped]): untyped =
  if args.len < 2:
    error "scene expects a name and an indented block of proc definitions, " &
      "e.g. `scene MainMenuScene:`", args
  let body = args[^1]
  let head = args[0 ..< ^1]
  if body.kind != nnkStmtList:
    error "a scene body must be an indented block of proc definitions.", body
  let sceneId = newLit head[0].strVal

  func procName(name: NimNode): string =
    if name.kind == nnkPostfix:
      name[1].strVal
    else:
      name.strVal

  func renameProc(name: NimNode, newName: string): NimNode =
    if name.kind == nnkPostfix:
      newTree(nnkPostfix, copyNimTree(name[0]), ident newName)
    else:
      ident newName

  func hasSceneStackParam(procDef: NimNode): bool =
    for i in 1 ..< procDef.params.len:
      let defs = procDef.params[i]
      for j in 0 ..< defs.len - 2:
        if defs[j].eqIdent("sceneStack"):
          return true

  var transformed = newStmtList()
  for item in body:
    if item.kind != nnkProcDef:
      transformed.add item
      continue
    var procDef = copyNimTree(item)
    if procName(procDef.name) in ["load", "unload"]:
      continue
    if not hasSceneStackParam(procDef):
      procDef.params.add newIdentDefs(ident"sceneStack", nnkVarTy.newTree(ident"SceneStack"))
    let isEarlyUpdate = procName(procDef.name) in ["earlyUpdate", "loadScene"]
    var guards = newStmtList()
    guards.add quote do:
      if not sceneStack.isSceneActive(`sceneId`):
        return
    if isEarlyUpdate:
      guards.add quote do:
        if not sceneStack.shouldLoad(`sceneId`):
          return
    if procName(procDef.name) == "loadScene":
      procDef.name = renameProc(procDef.name, "earlyUpdate")
    var newBody = newStmtList()
    newBody.add guards
    newBody.add procDef.body
    procDef.body = newBody
    transformed.add procDef

  var call = newCall(bindSym"plugin")
  for arg in head:
    call.add arg
  call.add transformed
  result = call
  
