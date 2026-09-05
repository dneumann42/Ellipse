import std/[oids, hashes, tables, typetraits, json, strformat, sets, algorithm, strutils, sugar, macros, sequtils]
import vmath
export json

type
  EntityID* = distinct uint64

proc `==`*(a, b: EntityID): bool {.borrow.}
proc hash*(b: EntityID): Hash {.borrow.}
proc `$`*(id: EntityID): string =
  $(uint64 id)

type
  ComponentID* = uint64
  Component* = concept type T
    proc `%`(t: T): JsonNode
    proc initFromJson(t: var T, js: JsonNode, path: var string): void

proc componentID*(name: string): ComponentID =
  result = 14695981039346656037'u64
  for c in name:
    result = result xor uint64(ord(c))
    result = result * 1099511628211'u64

type
  AbstractComponentBuffer* = ref object of RootObj
    entityIndex: Table[EntityID, int]
    entityIDs: seq[EntityID]
    dead: seq[int]
    dataToJson: proc(): JsonNode
    dataFromJson: proc(js: JsonNode): void
    
  ComponentBuffer*[T] = ref object of AbstractComponentBuffer
    data: seq[T]

proc liveSlot(buffer: AbstractComponentBuffer, index: int): bool =
  index >= 0 and index < buffer.entityIDs.len and index notin buffer.dead and
    buffer.entityIDs[index] in buffer.entityIndex and
    buffer.entityIndex[buffer.entityIDs[index]] == index

proc remove*(buffer: var AbstractComponentBuffer, entityID: EntityID): bool =
  if entityID notin buffer.entityIndex:
    return false
  let index = buffer.entityIndex[entityID]
  buffer.entityIndex.del(entityID)
  if index notin buffer.dead:
    buffer.dead.add(index)
  true

proc add*[T](cb: var ComponentBuffer[T], entityID: EntityID, comp: T) =
  if entityID in cb.entityIndex:
    cb.data[cb.entityIndex[entityID]] = comp
    return
  let idx =
    if cb.dead.len > 0:
      cb.dead.pop()
    else:
      cb.data.len
  cb.data.setLen(idx + 1)
  cb.data[idx] = comp
  cb.entityIDs.setLen(idx + 1)
  cb.entityIDs[idx] = entityID
  cb.entityIndex[entityID] = idx

iterator items*[T](cb: ComponentBuffer[T]): T =
  for index in 0 ..< cb.data.len:
    if cb.liveSlot(index):
      yield cb.data[index]

iterator mitems*[T](cb: var ComponentBuffer[T]): var T =
  for index in 0 ..< cb.data.len:
    if cb.liveSlot(index):
      yield cb.data[index]

iterator pairs*[T](cb: ComponentBuffer[T]): (EntityID, T) =
  for index in 0 ..< cb.data.len:
    if cb.liveSlot(index):
      yield (cb.entityIDs[index], cb.data[index])

iterator mpairs*[T](cb: var ComponentBuffer[T]): tuple[
    entityID: EntityID,
    component: var T
  ] =
  for index in 0 ..< cb.data.len:
    if cb.liveSlot(index):
      yield (cb.entityIDs[index], cb.data[index])

type
  Entity = tuple[id: EntityID, key: ComponentID]

  EntityCommandKind = enum
    SpawnEntityCommand
    KillEntityCommand

  EntityCommand = object
    case kind: EntityCommandKind
    of SpawnEntityCommand, KillEntityCommand:
      entityID: EntityID

  View* = ref object
    invalid: bool
    key: ComponentID
    requiredComponents: seq[ComponentID]
    entities: seq[Entity]
    
  EntityManager* = object
    componentBuffers: Table[ComponentID, AbstractComponentBuffer]
    views: seq[View]
    entities: seq[Entity]
    entityCommands: seq[EntityCommand]
    pendingDead: HashSet[EntityID]
    deadEntities: HashSet[EntityID]

proc init*(T: typedesc[EntityManager]): T =
  T()

proc spawn*(em: var EntityManager): EntityID =
  result = EntityID(componentID($genOid()))
  em.entityCommands.add EntityCommand(kind: SpawnEntityCommand, entityID: result)
  em.deadEntities.excl(result)

proc kill*(em: var EntityManager, entityID: EntityID) =
  if entityID in em.pendingDead or entityID in em.deadEntities:
    return
  em.pendingDead.incl(entityID)
  em.entityCommands.add EntityCommand(kind: KillEntityCommand, entityID: entityID)

proc isDead*(em: EntityManager, entityID: EntityID): bool =
  entityID in em.pendingDead or entityID in em.deadEntities

proc componentKey(em: EntityManager, entityID: EntityID): ComponentID =
  var strs = collect:
    for componentName, buffer in em.componentBuffers.pairs:
      if not buffer.entityIndex.hasKey(entityID):
        continue
      componentName
  strs.sort()
  componentID(strs.join("."))

proc invalidateViews(em: var EntityManager) =
  for view in em.views:
    view.invalid = true

proc resolveEntityCommands*(em: var EntityManager) =
  if em.entityCommands.len == 0:
    return
  for command in em.entityCommands:
    case command.kind
    of SpawnEntityCommand:
      if command.entityID in em.pendingDead or command.entityID in em.deadEntities:
        continue
      var exists = false
      for entity in em.entities:
        if entity.id == command.entityID:
          exists = true
          break
      if not exists:
        em.entities.add((
          id: command.entityID,
          key: em.componentKey(command.entityID),
        ))
    of KillEntityCommand:
      var index = 0
      while index < em.entities.len:
        if em.entities[index].id == command.entityID:
          em.entities.delete(index)
          break
        inc index
      for buffer in em.componentBuffers.mvalues:
        discard buffer.remove(command.entityID)
      em.deadEntities.incl(command.entityID)
  em.entityCommands.setLen(0)
  em.pendingDead.clear()
  em.invalidateViews()

proc endFrame*(em: var EntityManager) =
  em.resolveEntityCommands()

proc superKeyString*(nodes: varargs[NimNode]): string =
  result = collect(for n in nodes: n.repr).mapIt(componentID(it)).join(".")

macro superKey*(ts: varargs[typed]): auto =
  let key = ts
    .items()
    .toSeq()
    .superKeyString()
    .componentID()
  result = quote do:
    `key`

macro createView*(ts: varargs[typed]): View =
  var requiredComponents = newNimNode(nnkBracket)
  for t in ts:
    requiredComponents.add quote do:
      componentID(`t`.name)
  requiredComponents = newNimNode(nnkPrefix).add(ident("@"), requiredComponents)
  result = quote do:
    View(
      invalid: true,
      key: superKey(`ts`),
      requiredComponents: `requiredComponents`
    )
      
template withComponentBuffer(em: var EntityManager, T: typedesc, blk) =
  if not em.componentBuffers.hasKey(componentID(T.name)):
    var buffer = AbstractComponentBuffer(ComponentBuffer[T]())
    buffer.dataToJson = proc(): JsonNode =
      result = %* []
      var buff = cast[ComponentBuffer[T]](buffer)
      for datum in buff.data:
        result.add(% datum)
    buffer.dataFromJson = proc(js: JsonNode) =
      let buff = cast[ComponentBuffer[T]](buffer)
      buff.data = js.to(seq[T])
    em.componentBuffers[componentID(T.name)] = buffer
  block:
    var buffer {.inject.} = cast[ComponentBuffer[T]](em.componentBuffers[componentID(T.name)])
    blk

proc getBuffer*[T](em: var EntityManager): ComponentBuffer[T] =
  em.withComponentBuffer(T):
    result = buffer

proc updateKey*(em: var EntityManager, entityID: EntityID, newComponent: string) =
  discard newComponent
  var strs = collect:
    for componentName, buffer in em.componentBuffers.pairs:
      if not buffer.entityIndex.hasKey(entityID):
        continue
      componentName
  strs.sort()
  var superKey = strs.join(".")
  for i in 0 ..< em.entities.len:
    if em.entities[i].id == entityID:
      em.entities[i].key = componentID(superKey)
      for view in em.views:
        view.invalid = true
      return

proc add*[T](em: var EntityManager, entityID: EntityID, comp: T) =
  if em.isDead(entityID):
    return
  em.withComponentBuffer(T):
    buffer.add(entityID, comp)
  em.updateKey(entityID, T.name)

proc hasComponent*[T](em: EntityManager, entityID: EntityID): bool =
  if em.isDead(entityID):
    return false
  let key = componentID(T.name)
  if key notin em.componentBuffers:
    return false
  let buffer = em.componentBuffers[key]
  entityID in buffer.entityIndex

macro has*(em: EntityManager, entityID: EntityID,
    ts: varargs[typed]): untyped =
  result = newLit(true)
  for t in ts:
    result = quote do:
      `result` and hasComponent[`t`](`em`, `entityID`)

proc get*[T](em: var EntityManager, entityID: EntityID): var T =
  if em.isDead(entityID):
    raise newException(KeyError, "Entity '" & $entityID & "' is dead")
  let key = componentID(T.name)
  if key notin em.componentBuffers:
    raise newException(
      KeyError,
      "No component buffer exists for type '" & $key & "'"
    )
  let buffer =
    cast[ComponentBuffer[T]](em.componentBuffers[key])
  if entityID notin buffer.entityIndex:
    raise newException(
      KeyError,
      "Entity '" & $entityID &
      "' does not have component '" & $key & "'"
    )
  result = buffer.data[buffer.entityIndex[entityID]]

macro buildEntity*(em: var EntityManager, entityID: EntityID, blk: untyped): auto =
  var stmts = newStmtList()
  for stmt in blk:
    stmts.add(quote do:
      add(`em`, id, `stmt`))
  result = quote do:
    block:
      let id {.inject.} = `entityID`
      `stmts`
      id

proc getOrCreateView(
    em: var EntityManager,
    key: ComponentID,
    requiredComponents: seq[ComponentID]
  ): View =
  result = nil
  for idx, view in em.views.pairs:
    if view.key == key:
      result = em.views[idx]
      break
  if result == nil:
    em.views.add(View(
      key: key,
      invalid: true,
      requiredComponents: requiredComponents
    ))
    result = em.views[^1]

proc hydrateView*(em: var EntityManager, view: View) =
  view.entities.setLen(0)
  for entity in em.entities:
    if em.isDead(entity.id):
      continue
    var matches = true
    for componentKey in view.requiredComponents:
      if componentKey notin em.componentBuffers or
          entity.id notin em.componentBuffers[componentKey].entityIndex:
        matches = false
        break
    if matches:
      view.entities.add(entity)
  view.invalid = false

iterator items*(view: View): EntityID =
  for entity in view.entities:
    yield entity.id

macro view*(em: var EntityManager, ts: varargs[typed]): auto =
  var requiredComponents = newNimNode(nnkBracket)
  for t in ts:
    requiredComponents.add quote do:
      componentID(`t`.name)
  requiredComponents = newNimNode(nnkPrefix).add(ident("@"), requiredComponents)
  result = quote do:
    block:
      var view = `em`.getOrCreateView(
        superKey(`ts`),
        `requiredComponents`
      )
      if view.invalid:
        `em`.hydrateView(view)
      view

macro componentsOf*(viewExpr: untyped): untyped =
  if viewExpr.kind notin {nnkCall, nnkCommand}:
    error("componentsOf expects a view(em, Component, ...) expression", viewExpr)

  var
    em: NimNode
    componentStart = 2
  if viewExpr[0].repr == "view" and viewExpr.len >= 3:
    em = viewExpr[1]
  elif viewExpr[0].kind == nnkDotExpr and viewExpr[0].len == 2 and
      viewExpr[0][1].repr == "view" and viewExpr.len >= 2:
    em = viewExpr[0][0]
    componentStart = 1
  else:
    error("componentsOf expects a view(em, Component, ...) expression", viewExpr)

  let entityID = genSym(nskForVar, "entityID")
  var componentTypes = newSeq[NimNode]()
  for index in componentStart ..< viewExpr.len:
    componentTypes.add(viewExpr[index])

  var tupleType = newNimNode(nnkTupleTy)
  tupleType.add(newTree(
    nnkIdentDefs,
    ident("entityID"),
    ident("EntityID"),
    newEmptyNode()
  ))

  var yieldedValues = newNimNode(nnkPar)
  yieldedValues.add(entityID)
  for index, componentType in componentTypes:
    tupleType.add(newTree(
      nnkIdentDefs,
      ident("component" & $index),
      newTree(nnkVarTy, componentType),
      newEmptyNode()
    ))
    yieldedValues.add quote do:
      get[`componentType`](`em`, `entityID`)

  result = quote do:
    (iterator(): `tupleType` =
      let currentView = `viewExpr`
      for `entityID` in currentView:
        yield `yieldedValues`
    )()

# JSON marshaling    

proc `%`*(em: EntityID): JsonNode =
  result = % uint64(em)

proc jsonUInt64(js: JsonNode): uint64 =
  case js.kind
  of JInt:
    cast[uint64](js.num)
  of JString:
    parseUInt(js.str)
  else:
    raise newException(JsonKindError, "expected an unsigned integer")

proc initFromJson*(id: var EntityID, js: JsonNode, path: var string) =
  discard path
  id = EntityID(jsonUInt64(js))

proc `%`*(em: Entity): JsonNode =
  result = %* [em.id, em.key]

proc initFromJson*(entity: var Entity, js: JsonNode, path: var string) =
  discard path
  entity = (id: EntityID(jsonUInt64(js[0])), key: ComponentID(jsonUInt64(js[1])))

proc initFromJson*[T](dst: var Table[EntityID, T]; jsonNode: JsonNode; jsonPath: var string) =
  dst = initTable[EntityID, T]()
  if jsonNode.kind != JObject:
    raise newException(JsonKindError, "expected object for table at: " & jsonPath)
  let originalJsonPathLen = jsonPath.len
  for key, value in jsonNode.pairs:
    jsonPath.add '.'
    jsonPath.add key
    dst[EntityID(parseUInt(key))] = value.to(T)
    jsonPath.setLen originalJsonPathLen

proc `%`*(compBuff: AbstractComponentBuffer): JsonNode =
  result = %* {
    "entityIndex": {},
    "entityIDs": compBuff.entityIDs,
    "dead": compBuff.dead,
    "data": {},
  }
  for key, value in compBuff.entityIndex.pairs:
    result["entityIndex"][$key] = % value
  result["data"] = compBuff.dataToJson()

proc initFromJson*(
  buff: var AbstractComponentBuffer,
  js: JsonNode,
  path: var string
) =
  discard path
  buff.dead = js["dead"].to(seq[int])
  buff.entityIndex = js["entityIndex"].to(Table[EntityID, int])
  if js.hasKey("entityIDs"):
    buff.entityIDs = js["entityIDs"].to(seq[EntityID])
  else:
    buff.entityIDs.setLen(js["data"].len)
    for entityID, index in buff.entityIndex.pairs:
      buff.entityIDs[index] = entityID
  buff.dataFromJson(js["data"])

proc `%`*(em: EntityManager): JsonNode =
  result = %* {
    "componentBuffers": {},
    "entities": em.entities
  }
  for key, value in em.componentBuffers.pairs:
    result["componentBuffers"][$key] = % value

proc initFromJson*(em: var EntityManager, js: JsonNode, path: var string) =
  discard path
  em.entities = js["entities"].to(typeof em.entities)
  for serializedKey, buffer in js["componentBuffers"].pairs:
    let key = ComponentID(parseUInt(serializedKey))
    if key notin em.componentBuffers:
      raise ValueError.newException(
        &"No component buffer exists for component type: {key}"
      )
    initFromJson(em.componentBuffers[key], buffer, path)

when isMainModule:
  type
    Spatial = object
      x, y, z: int
    Health = object
      value: float
    Physics = object
      vx, vy, vz: float

  var manager = EntityManager.init()

  let
    entity = manager.buildEntity(manager.spawn()):
      Spatial(z: 123)
      Health(value: 4.3)
      Physics(vx: 333.444)
  
    entity2 = manager.buildEntity(manager.spawn()):
      Spatial(z: 69)
      Health(value: 4.3)
  
  for e, physics in componentsOf(manager.view(Physics)):
    echo "HERE: ", physics

  for e, spatial, health in componentsOf(manager.view(Spatial, Health)):
    echo "HERE AGAIN: ", spatial, " ", health
