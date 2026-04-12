import std/[macros, macrocache, options, sugar, algorithm, tables, typeinfo, typetraits, sequtils]

export macros

const
  PluginLoadFunctions = CacheTable"PluginLoadFunctions"
  PluginLoadSceneFunctions = CacheTable"PluginLoadSceneFunctions"
  PluginUpdateFunctions = CacheTable"PluginUpdateFunctions"
  PluginAlwaysUpdateFunctions = CacheTable"PluginAlwaysUpdateFunctions"
  PluginDrawFunctions = CacheTable"PluginDrawFunctions"
  PluginDrawHudFunctions = CacheTable"PluginDrawHudFunctions"

  PluginMessageTypes = CacheTable"PluginMessageTypes"

  # Table[MessageType, seq[Listener]] where seq is a nnkStmtList
  PluginMessageListeners = CacheTable"PluginMessageListeners"

  PluginScenes = CacheTable"PluginScenes"
  PluginScenePluginNames = CacheTable"PluginScenePluginNames"
  PluginOrder = CacheTable"PluginOrder"
  PluginLocalStates = CacheTable"PluginLocalStates"
  PluginLocalStateTypes = CacheTable"PluginLocalStateTypes"

type
  AbstractSceneState* = ref object of RootObj
    # TODO: include module
    typeName*: string

  SceneState*[T] = ref object of AbstractSceneState
    state*: T

  SceneStack* = ref object
    sceneStack: seq[string]
    loadScenes: seq[string]
    pushedScene: seq[string]

    # Used to push state to the next scene
    sceneState: Option[AbstractSceneState]

    # Used as a return value (ex. a confirmation or form results)
    sceneResult*: Option[AbstractSceneState]
    sceneChanged: bool

  AbstractPluginState* = ref object of RootObj
  PluginState*[T] = ref object of AbstractPluginState
    state*: T

  PluginStates* = Table[string, AbstractPluginState]

  AbstractMessage* = ref object of RootObj
    typeName*: string
    handled*: bool

  Message*[T] = ref object of AbstractMessage
    payload*: T

  PluginMessages* = object
    queue: seq[AbstractMessage]

proc init*(T: typedesc[PluginMessages]): T =
  T(queue: @[])

proc send*[T](msg: var PluginMessages, payload: T) =
  let m = Message[T](payload: payload, typeName: $T.name)
  msg.queue.add(AbstractMessage(m))

proc recv*[T](msg: var PluginMessages, Ty: typedesc[T]): Option[Ty] =
  for m in msg.queue.mitems:
    if m.handled:
      continue
    if m.typeName == $Ty.name:
      return some(Message[Ty](m).payload)

proc lateUpdate*(msg: var PluginMessages) =
  msg.queue.keepIf(proc(m: AbstractMessage): auto = not m.handled)

proc handle*[T](msg: var PluginMessages, Ty: typedesc[T]) =
  for m in msg.queue.mitems:
    if m.typeName == $Ty.name:
      m.handled = true 

proc new*(T: typedesc[SceneStack]): T =
  T()

proc pushScene*(self: SceneStack, sceneId: string) =
  self.pushedScene.add(sceneId)
  self.sceneChanged = true

proc pushScene*[T](self: SceneStack, sceneId: string, state: T) =
  self.pushedScene.add(sceneId)
  let sceneState = SceneState[T](state: state, typeName: $T)
  self.sceneState = some(cast[AbstractSceneState](sceneState))
  self.sceneChanged = true

proc popScene*(self: SceneStack): Option[string] {.discardable, gcsafe.} =
  if self.sceneStack.len() == 0:
    return
  result = self.sceneStack.pop().some()
  self.sceneChanged = true

proc popScene*[T](
    self: var SceneStack, sceneResult: T
): Option[string] {.discardable, gcsafe.} =
  result = self.popScene()
  let sceneState = SceneState[T](state: sceneResult, typeName: $T)
  self.sceneResult = some(cast[AbstractSceneState](sceneState))

template withSceneState*(self: var SceneStack, T: typedesc, blk: untyped) =
  if self.sceneState.isSome:
    let res = self.sceneState.get()
    let it {.inject.} = cast[SceneState[T]](res).state
    blk
    self.sceneState = none(AbstractSceneState)

template expectSceneState*(self: var SceneStack, T: typedesc, blk: untyped) =
  if self.sceneState.isSome:
    let res = self.sceneState.get()
    let it {.inject.} = cast[SceneState[T]](res).state
    blk
    self.sceneState = none(AbstractSceneState)
  else:
    stderr.writeLine("Failed to load game scene: expected " & $T)
    self.popScene()

template withSceneResult*(self: var SceneStack, T: typedesc, blk: untyped) =
  if self.sceneResult.isSome:
    let res = self.sceneResult.get()
    if res.typeName == $T:
      let it {.inject.} = cast[SceneState[T]](res).state
      blk
      self.sceneResult = none(AbstractSceneState)

proc gotoScene*(self: SceneStack, sceneId: string) {.gcsafe.} =
  discard self.popScene()
  self.pushScene(sceneId)

proc currentScene*(self: SceneStack): string =
  if self.sceneStack.len == 0:
    return
  result = self.sceneStack[^1]

proc canGoBack*(self: SceneStack): bool =
  self.sceneStack.len > 1

macro getPluginSceneNames*(): auto =
  result = nnkBracket.newTree()
  for name in PluginScenePluginNames.pairs:
    let s = newLit(name[0])
    result.add(s)

proc pushingScene*(self: SceneStack): bool =
  result = self.pushedScene.len > 0

proc hasPreviousScene*(self: SceneStack): bool =
  result = self.sceneStack.len > 1

proc handlePushed*(self: SceneStack) =
  for pushed in self.pushedScene:
    self.sceneStack.add(pushed)
    self.loadScenes.add(pushed)
  self.pushedScene.setLen(0)

proc handleLoad*(self: SceneStack) =
  self.loadScenes.setLen(0)

proc sceneChanged*(self: SceneStack): bool =
  self.sceneChanged

proc startFrame*(self: var SceneStack) =
  self.sceneChanged = false

proc shouldLoad*(self: SceneStack, sceneId: string): bool =
  for v in self.loadScenes:
    if v == sceneId:
      return true

proc getFunctionCacheTable*(kind: string): CacheTable =
  if kind == "update":
    result = PluginUpdateFunctions
  elif kind == "alwaysUpdate":
    result = PluginAlwaysUpdateFunctions
  elif kind == "draw":
    result = PluginDrawFunctions
  elif kind == "drawHud":
    result = PluginDrawHudFunctions
  elif kind == "load":
    result = PluginLoadFunctions
  elif kind == "loadScene":
    result = PluginLoadSceneFunctions
  else:
    macros.error("Unknown plugin function kind: " & kind)

proc renameIt(identifier, funName: NimNode): auto =
  result = ident(funName.repr & identifier.repr)

proc exportIt(identifier, fun: NimNode): auto =
  result = fun
  if fun[0].kind == nnkPostfix:
    result[0] = nnkPostfix.newTree(ident"*", renameIt(identifier, fun[0][1]))
  else:
    result[0] = nnkPostfix.newTree(ident"*", renameIt(identifier, fun[0]))
  if result.kind == nnkProcDef:
    const pragmaPos = 4
    if result[pragmaPos].kind == nnkEmpty:
      result[pragmaPos] = nnkPragma.newTree(ident"gcsafe")
    elif result[pragmaPos].kind == nnkPragma:
      var has = false
      for n in result[pragmaPos]:
        if n.kind == nnkIdent and n.eqIdent"gcsafe":
          has = true
      if not has:
        result[pragmaPos].add ident"gcsafe"

proc getMessageType(fun: NimNode): NimNode =
  expectKind(fun, nnkProcDef) 
  expectKind(fun[3], nnkFormalParams)
  expectKind(fun[3][1], nnkIdentDefs)
  expectKind(fun[3][1][1], nnkIdent)
  result = fun[3][1][1]

proc updateListenerIdent(fun, identifier: NimNode) =
  expectKind(fun, nnkProcDef) 
  let typ = fun.getMessageType()
  fun[0] = ident(identifier.repr & fun[0].repr & "_" & typ.repr) 

proc handleListener(fun, identifier: NimNode): NimNode =
  expectKind(fun, nnkProcDef) 
  updateListenerIdent(fun, identifier)
  result = fun

macro plugin*(identifier, body: untyped): auto =
  result = newStmtList()
  var order = 0
  for fun in body:
    if fun.kind == nnkAsgn and fun[0].repr == "order":
      order = fun[1].intVal().int
      continue
    if fun.kind == nnkAsgn and fun[0].repr == "state":
      let t =
        if fun[1].kind == nnkStrLit:
          ident("string")
        elif fun[1].kind == nnkIntLit:
          ident("int")
        elif fun[1].kind == nnkInt16Lit:
          ident("int16")
        elif fun[1].kind == nnkInt32Lit:
          ident("int32")
        elif fun[1].kind == nnkInt64Lit:
          ident("int64")
        elif fun[1].kind == nnkIdent and fun[1].repr in ["true", "false"]:
          ident("bool")
        else:
          expectKind(fun[1], nnkCall)
          fun[1][0]
      PluginLocalStates[identifier.repr] = fun[1]
      PluginLocalStateTypes[identifier.repr] = t
      continue

    let functionKind = fun[0].repr

    if functionKind == "listen":
      var fn = handleListener(fun, identifier).copy()
      fn[0] = nnkPostfix.newTree(ident"*", fn[0])
      result.add(fn)
      let typ = fun.getMessageType()
      if not PluginMessageTypes.hasKey(typ.repr):
        PluginMessageTypes[typ.repr] = typ
      if not PluginMessageListeners.hasKey(typ.repr):
        PluginMessageListeners[typ.repr] = nnkStmtList.newTree()
      PluginMessageListeners[typ.repr].add(fun)
    else:
      let exportedFun = exportIt(identifier, fun)
      let cacheTable = getFunctionCacheTable(functionKind)
      let funName = fun[0][1]
      cacheTable[funName.repr] = fun
      PluginOrder[funName.repr] = quote:
        `order`
      result.add(exportedFun)

macro scene*(identifier, body: untyped): auto =
  result = newStmtList()
  var order = 0
  PluginScenePluginNames[identifier.repr] = identifier

  for fun in body:
    if fun.kind == nnkAsgn and fun[0].repr == "order":
      order = fun[1].intVal().int
      continue
    if fun.kind == nnkAsgn and fun[0].repr == "state":
      let t =
        if fun[1].kind == nnkStrLit:
          ident("string")
        elif fun[1].kind == nnkIntLit:
          ident("int")
        elif fun[1].kind == nnkInt16Lit:
          ident("int16")
        elif fun[1].kind == nnkInt32Lit:
          ident("int32")
        elif fun[1].kind == nnkInt64Lit:
          ident("int64")
        elif fun[1].kind == nnkIdent and fun[1].repr in ["true", "false"]:
          ident("bool")
        else:
          expectKind(fun[1], nnkCall)
          fun[1][0]
      PluginLocalStates[identifier.repr] = fun[1]
      PluginLocalStateTypes[identifier.repr] = t
      continue

    let functionKind = fun[0].repr
    if functionKind == "listen":
      var fn = handleListener(fun, identifier).copy()
      fn[0] = nnkPostfix.newTree(ident"*", fn[0])
      result.add(fn)
      let typ = fun.getMessageType()
      if not PluginMessageTypes.hasKey(typ.repr):
        PluginMessageTypes[typ.repr] = typ
      if not PluginMessageListeners.hasKey(typ.repr):
        PluginMessageListeners[typ.repr] = nnkStmtList.newTree()
      PluginMessageListeners[typ.repr].add(fun)
    else:
      let exportedFun = exportIt(identifier, fun)
      let cacheTable = getFunctionCacheTable(functionKind)
      let funName = fun[0][1]
      cacheTable[funName.repr] = fun
      PluginOrder[funName.repr] = quote:
        `order`
      PluginScenes[funName.repr] = fun
      result.add(exportedFun)

proc extractPluginName(id: NimNode, kind: string): string =
  return id.repr[kind.len ..< id.repr.len]

proc generatePluginStepKF(k: string, fn, kind: NimNode): auto =
  var args = nnkArgList.newNimNode()
  let params = fn[3]
  for pi in 1 ..< params.len:
    let p = params[pi][0].strVal
    args.add(ident(p))
  let callName = ident(k)
  let pluginName = extractPluginName(callName, kind.repr)
  if PluginScenes.contains(k) and kind.repr != "loadScene" and kind.repr != "load":
    if PluginLocalStates.contains(pluginName):
      let T = PluginLocalStateTypes[pluginName]
      return quote:
        if scenes.currentScene() == `pluginName`:
          var state {.inject.}: `T` =
            PluginState[`T`](pluginStates[`pluginName`]).state
          `callName`(`args`)
          pluginStates[`pluginName`] =
            PluginState[`T`](state: state).AbstractPluginState
    else:
      return quote:
        if scenes.currentScene() == `pluginName`:
          `callName`(`args`)
  if PluginScenes.contains(k) and kind.repr == "loadScene":
    if PluginLocalStates.contains(pluginName):
      let T = PluginLocalStateTypes[pluginName]
      return quote:
        if scenes.currentScene() == `pluginName` and
            scenes.shouldLoad(scenes.currentScene()):
          scenes.handleLoad()
          var state {.inject.}: `T` =
            PluginState[`T`](pluginStates[`pluginName`]).state
          `callName`(`args`)
          pluginStates[`pluginName`] =
            PluginState[`T`](state: state).AbstractPluginState
    else:
      return quote:
        if scenes.currentScene() == `pluginName` and
            scenes.shouldLoad(scenes.currentScene()):
          scenes.handleLoad()
          `callName`(`args`)
  if PluginLocalStates.contains(pluginName):
    let T = PluginLocalStateTypes[pluginName]
    quote:
      block:
        var state {.inject.}: `T` =
          PluginState[`T`](pluginStates[`pluginName`]).state
        `callName`(`args`)
        pluginStates[`pluginName`] =
          PluginState[`T`](state: state).AbstractPluginState
  else:
    quote:
      `callName`(`args`)

proc cmpPlugin*(a, b: (string, NimNode)): auto =
  result = PluginOrder[a[0]].intVal().cmp(PluginOrder[b[0]].intVal())

macro generatePluginStep*(kind): auto =
  result = newStmtList()
  let cacheTable = getFunctionCacheTable(kind.repr)

  var ps = collect:
    for k, fn in cacheTable.pairs:
      (k, fn)

  ps.sort(cmpPlugin)

  for (k, fn) in ps:
    let call = generatePluginStepKF(k, fn, kind)
    result.add(call)

macro generatePluginStateInitialize*(pluginStates: var PluginStates): auto =
  result = newStmtList()
  for (name, state) in PluginLocalStates.pairs:
    let id = ident(name & "State")
    result.add(
      quote do:
        block:
          var `id` = `state`
          `pluginStates`[`name`] = PluginState[typeof(`id`)](state: `id`)
    )

macro generateListenStep*(messages: untyped): auto =
  var ifs = nnkStmtList.newTree()
  for (typ, fn) in PluginMessageTypes.pairs:
    var stmts = nnkStmtList.newTree()
    let id = ident(typ)
    for stmt in PluginMessageListeners[typ]:
      # Stmt should be the function definition
      let call = stmt[0]

      let params = stmt[3]
      var args = nnkArgList.newTree()
      args.add(ident"msg")
      for pi in 2 ..< params.len:
        let p = params[pi][0].strVal
        args.add(ident(p))

      stmts.add(
        quote do: 
          `call`(`args`)
      )
    ifs.add(
      quote do:
        block:
          let maybeMessage = `messages`.recv(`id`)
          if maybeMessage.isSome():
            let msg {.inject.} = maybeMessage.get()
            `stmts`
    )
  ifs.add(quote do: `messages`.lateUpdate())
  result = ifs

when isMainModule:
  plugin PlugA:
    proc listen(msg: string) =
      discard
    proc listen(n: int) =
      discard

  plugin PlugB:
    proc listen(msg: string) =
      discard
    proc listen(running: bool) =
      discard

  var message {.inject.} = PluginMessages.init()
  expandMacros:
    generateListenStep()
