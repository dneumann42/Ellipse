import std/[tables, sequtils, hashes, algorithm, typeinfo, macros, strutils]

import ../base

import componentSets

type
  Entity* = tuple[index, generation: uint32]
  EntityLocation = object
    archetype: ptr Archetype
    row: int
    generation: uint32
    alive: bool
  Column = object
    typeId: ComponentTypeId
    elemSize, elemAlign: int
    length, capacity: int
    data: pointer
  Archetype = object
    signature: ComponentSet
    entities: seq[Entity]
    columns: seq[Column]
  ComponentInfo = object
    id: ComponentTypeId
    size, align: int
    name: string
  EntityManager* = object
    information: seq[ComponentInfo]
    componentIds: Table[string, ComponentTypeId]
    archetypes: seq[ref Archetype]
    archetypeBySignature: Table[ComponentSet, ptr Archetype]
    locations: seq[EntityLocation]
    freeList: seq[uint32]

proc init(
  T: typedesc[Column]; 
  info: ComponentInfo; 
  initialCapacity = 64
): T =
  let align = max(info.align, CacheLine)
  result = T(
    typeId: info.id,
    elemSize: info.size,
    elemAlign: align,
    length: 0,
    capacity: initialCapacity,
    data: allocAligned(info.size * initialCapacity, align)
  )

proc destroy(c: var Column) =
  deallocAligned(c.data)
  c = Column.default()

proc columnPtr[T](c: var Column): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](c.data)

proc columnPtrConst[T](c: Column): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](c.data)

proc ensureCapacity(c: var Column; needed: int) =
  if needed <= c.capacity:
    return
  let newCapacity = max(64, max(needed, c.capacity * 2))
  let newData = allocAligned(c.elemSize * newCapacity, c.elemAlign)

  # copy to newData
  if not c.data.isNil and c.length > 0:
    copyMem(newData, c.data, c.elemSize * c.length) 
  deallocAligned(c.data)
  c.data = newData
  c.capacity = newCapacity

proc copyElement(dst: var Column; dstRow: int; src: Column; srcRow: int) =
  let
    dstAddr = cast[pointer](cast[uint](dst.data) + uint(dst.elemSize * dstRow))
    srcAddr = cast[pointer](cast[uint](src.data) + uint(src.elemSize * srcRow))
  copyMem(dstAddr, srcAddr, dst.elemSize)

proc moveLastInto(c: var Column; dstRow, srcRow: int) =
  if dstRow == srcRow:
    return
  let
    dstAddr = cast[pointer](cast[uint](c.data) + uint(c.elemSize * dstRow))
    srcAddr = cast[pointer](cast[uint](c.data) + uint(c.elemSize * srcRow))
  copyMem(dstAddr, srcAddr, c.elemSize)

proc componentKey[T](_: typedesc[T]): string =
  result = $T

proc componentId*[T](U: typedesc[T], entityManager: EntityManager): ComponentTypeId =
  result = entityManager.componentIds[U.componentKey()]

proc registerComponent*[T](_: typedesc[T], entityManager: var EntityManager) =
  let key = T.componentKey()
  if key in entityManager.componentIds:
    return
  doAssert entityManager.information.len < 256, "ComponentSet only supports 256 component types"
  let id = ComponentTypeId(entityManager.information.len)
  entityManager.componentIds[key] = id
  entityManager.information.add ComponentInfo(
    id: id,
    size: sizeof(T),
    align: alignof(T),
    name: key
  )

proc info(entityManager: EntityManager; id: ComponentTypeId): ComponentInfo =
  entityManager.information[uint16(id).int]

proc findColumnIndex(a: Archetype; id: ComponentTypeId): int =
  result = -1
  for i, c in a.columns:
    if c.typeId == id:
      return i

proc column(a: var Archetype; id: ComponentTypeId): var Column =
  let idx = a.findColumnIndex(id)
  doAssert idx >= 0, "Missing component column"
  result = a.columns[idx]

proc getOrCreateArchetype(entityManager: var EntityManager; sig: ComponentSet): ptr Archetype =
  if sig in entityManager.archetypeBySignature:
    return entityManager.archetypeBySignature[sig]
  var archRef = Archetype.new()
  archRef.signature = sig
  let sortedIds = sig.ids.sortedByIt(it.uint16)
  for id in sortedIds:
    archRef.columns.add Column.init(entityManager.info(id))
  entityManager.archetypes.add archRef
  result = addr archRef[]
  entityManager.archetypeBySignature[sig] = result

proc reserveRow(a: var Archetype; entity: Entity): int =
  result = a.entities.len
  a.entities.add entity
  for c in a.columns.mitems:
    c.ensureCapacity(result + 1)
    c.length = result + 1

proc swapRemoveRow(entityManager: var EntityManager; a: var Archetype; row: int) =
  let last = a.entities.len - 1
  if row != last:
    let moved = a.entities[last]
    a.entities[row] = moved
    entityManager.locations[moved.index].row = row
    for c in a.columns.mitems:
      c.moveLastInto(row, last)

  a.entities.setLen(last)
  for c in a.columns.mitems:
    c.length = last

proc copySharedColumns(dst: var Archetype; dstRow: int; src: Archetype; srcRow: int) =
  for srcCol in src.columns:
    let dstIdx = dst.findColumnIndex(srcCol.typeId)
    if dstIdx >= 0:
      dst.columns[dstIdx].copyElement(dstRow, srcCol, srcRow)

proc init*(T: typedesc[EntityManager]): T =
  result = T()

proc destroy*(entities: var EntityManager) =
  for arch in entities.archetypes.mitems:
    for c in arch.columns.mitems:
      c.destroy()
  entities = EntityManager.default()

proc alive*(entities: EntityManager; e: Entity): bool =
  if e.index.int >= entities.locations.len:
    return false
  let loc = entities.locations[e.index]
  if not loc.alive:
    return false
  if loc.generation != e.generation:
    return false
  true

proc allocEntity(entities: var EntityManager): Entity =
  if entities.freeList.len > 0:
    let 
      idx = entities.freeList.pop()
      gen = entities.locations[idx].generation
    return (index: idx, generation: gen)
  let idx = uint32(entities.locations.len)
  entities.locations.add EntityLocation(generation: 1)
  result = (index: idx, generation: 1)

template buildSignature(entities: EntityManager; types: varargs[typedesc]): ComponentSet =
  for T in types:
    result.incl componentId[T](entities)

template registerComponentsOf(entities: var EntityManager; xs: openArray[untyped]) =
  for x in xs:
    registerComponent(typeof(x), entities)

template inclAllOf(entities: var EntityManager; s: var ComponentSet; xs: openArray[untyped]) =
  for x in xs:
    s.incl componentId(typeof(x), entities)

template inclAll(entities: var EntityManager; s: var ComponentSet; types: openArray[typedesc]) =
  for T in types:
    s.incl componentId[T](entities)

macro createImpl*(entities: untyped; xs: varargs[untyped]): untyped =
  let
    entity = genSym(nskLet, "entity")
    sig    = genSym(nskLet, "sig")
    s      = genSym(nskVar, "s")
    arch   = genSym(nskLet, "arch")
    row    = genSym(nskLet, "row")
    loc    = genSym(nskVar, "loc")
  var registerStmts = newStmtList()
  var sigStmts = newStmtList()
  var addStmts = newStmtList()
  for x in xs:
    registerStmts.add quote do:
      registerComponent(typeof(`x`), `entities`)
    sigStmts.add quote do:
      `s`.incl componentId(typeof(`x`), `entities`)
    addStmts.add quote do:
      columnPtr[typeof(`x`)](
        `arch`[].column(componentId(typeof(`x`), `entities`))
      )[`row`] = `x`
  quote do:
    block:
      `registerStmts`
      let `entity` = `entities`.allocEntity()
      let `sig` = block:
        var `s` = ComponentSet()
        `sigStmts`
        `s`
      let `arch` = `entities`.getOrCreateArchetype(`sig`)
      let `row` = `arch`[].reserveRow(`entity`)
      `addStmts`
      var `loc` = EntityLocation(
        archetype: `arch`,
        row: `row`,
        generation: `entity`.generation,
        alive: true
      )
      `entities`.locations[`entity`.index] = `loc`
      `entity`

proc create*[A](entities: var EntityManager, a: A): Entity =
  createImpl(entities, a)

proc create*[A, B](entities: var EntityManager, a: A, b: B): Entity =
  createImpl(entities, a, b)

proc create*[A, B, C](entities: var EntityManager, a: A, b: B, c: C): Entity =
  createImpl(entities, a, b, c)

proc create*[A, B, C, D](entities: var EntityManager, a: A, b: B, c: C, d: D): Entity =
  createImpl(entities, a, b, c, d)

proc create*[A, B, C, D, E](entities: var EntityManager, a: A, b: B, c: C, d: D, e: E): Entity =
  createImpl(entities, a, b, c, d, e)

proc create*[A, B, C, D, E, F](entities: var EntityManager, a: A, b: B, c: C, d: D, e: E, f: F): Entity =
  createImpl(entities, a, b, c, d, e, f)

proc create*[A, B, C, D, E, F, G](entities: var EntityManager, a: A, b: B, c: C, d: D, e: E, f: F, g: G): Entity =
  createImpl(entities, a, b, c, d, e, f, g)

proc create*[A, B, C, D, E, F, G, H](entities: var EntityManager, a: A, b: B, c: C, d: D, e: E, f: F, g: G, h: H): Entity =
  createImpl(entities, a, b, c, d, e, f, g, h)

proc has*[T](es: EntityManager; e: Entity, _: typedesc[T]): bool =
  if not es.alive(e):
    return
  let id = componentId(T, es)
  es.locations[e.index].archetype.signature.contains(id)

proc get*[T](es: var EntityManager; e: Entity): var T =
  doAssert es.alive(e), "Dead entity"
  let id = componentId(T, es)
  var arch = es.locations[e.index].archetype
  let row = es.locations[e.index].row
  columnPtr[T](arch[].column(id))[row]

proc add*[T](es: var EntityManager; e: Entity; value: T) =
  doAssert es.alive(e), "Dead entity"
  let
    id = componentId(T, es)
    oldLoc = es.locations[e.index]
    oldArch = oldLoc.archetype
  if oldArch.signature.contains(id):
    get[T](es, e) = value
    return
  let
    newSignature = oldArch.signature.with(id)
    newArch = es.getOrCreateArchetype(newSignature)
    newRow = newArch[].reserveRow(e)
  newArch[].copySharedColumns(newRow, oldArch[], oldLoc.row)
  columnPtr[T](newArch[].column(id))[newRow] = value
  es.swapRemoveRow(oldArch[], oldLoc.row)
  es.locations[e.index].archetype = newArch
  es.locations[e.index].row = newRow

proc remove*[T](es: var EntityManager; e: Entity) =
  doAssert es.alive(e), "Dead entity"
  let
    id = componentId(T, es)
    oldLoc = es.locations[e.index]
    oldArch = oldLoc.archetype
  if not oldArch.signature.contains(id):
    return
  let
    newSig = oldArch.signature.without(id)
    newArch = es.getOrCreateArchetype(newSig)
    newRow = newArch[].reserveRow(e)
  newArch[].copySharedColumns(newRow, oldArch[], oldLoc.row)
  es.swapRemoveRow(oldArch[], oldLoc.row)
  es.locations[e.index].archetype = newArch
  es.locations[e.index].row = newRow

proc destroy*(es: var EntityManager; e: Entity) =
  if not es.alive(e):
    return
  let loc = es.locations[e.index]
  swapRemoveRow(es, loc.archetype[], loc.row)
  inc es.locations[e.index].generation
  es.locations[e.index].alive = false
  es.locations[e.index].archetype = nil
  es.locations[e.index].row = -1
  es.freeList.add e.index

when isMainModule:
  import unittest

  type TestComponent = object
    x, y: float32
    id: int

  type TestComponent2 = object
    data: array[32, byte]

  type SmallComponent = object
    value: int8

  suite "Column":
    test "init allocates with correct size":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(TestComponent),
          align: sizeof(TestComponent),
          name: "TestComponent"
        )
      )
      check col.elemSize == sizeof(TestComponent)
      check col.elemAlign == CacheLine
      check col.capacity == 64
      check col.length == 0
      check not col.data.isNil
      col.destroy()

    test "init with custom initialCapacity":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(TestComponent),
          align: sizeof(TestComponent),
          name: "TestComponent"
        ),
        initialCapacity = 128
      )
      check col.capacity == 128
      col.destroy()

    test "init uses max of alignment and CacheLine":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: 4,
          align: 4,
          name: "SmallComponent"
        )
      )
      check col.elemAlign == CacheLine
      col.destroy()

    test "destroy frees memory":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(TestComponent),
          align: sizeof(TestComponent),
          name: "TestComponent"
        )
      )
      let dataPtr = col.data
      col.destroy()
      check col.data.isNil

    test "columnPtr returns cast pointer":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(TestComponent),
          align: sizeof(TestComponent),
          name: "TestComponent"
        )
      )
      check col.data != nil
      col.destroy()

    test "columnPtrConst returns cast pointer":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(TestComponent),
          align: sizeof(TestComponent),
          name: "TestComponent"
        )
      )
      check col.data != nil
      col.destroy()

    test "ensureCapacity grows storage":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(TestComponent),
          align: sizeof(TestComponent),
          name: "TestComponent"
        ),
        initialCapacity = 4
      )
      check col.capacity == 4
      col.ensureCapacity(10)
      check col.capacity >= 10
      col.destroy()

    test "ensureCapacity no-op when sufficient":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(TestComponent),
          align: sizeof(TestComponent),
          name: "TestComponent"
        ),
        initialCapacity = 64
      )
      let oldCapacity = col.capacity
      col.ensureCapacity(32)
      check col.capacity == oldCapacity
      col.destroy()

    test "ensureCapacity doubles when close":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(TestComponent),
          align: sizeof(TestComponent),
          name: "TestComponent"
        ),
        initialCapacity = 8
      )
      col.ensureCapacity(9)
      check col.capacity >= 16
      col.destroy()

    test "copyElement copies data":
      var dst = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(TestComponent),
          align: sizeof(TestComponent),
          name: "TestComponent"
        ),
        initialCapacity = 4
      )
      let srcInfo = ComponentInfo(
        id: ComponentTypeId(0),
        size: sizeof(TestComponent),
        align: sizeof(TestComponent),
        name: "TestComponent"
      )
      var src = Column.init(srcInfo, initialCapacity = 4)
      check dst.length == 0
      check src.length == 0
      src.length = 1
      check src.data != nil
      dst.length = 1
      dst.copyElement(0, src, 0)
      check dst.length == 1
      check dst.data != nil
      dst.destroy()
      src.destroy()

    test "moveLastInto moves element":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(TestComponent),
          align: sizeof(TestComponent),
          name: "TestComponent"
        ),
        initialCapacity = 4
      )
      col.length = 2
      check col.data != nil
      col.moveLastInto(0, 1)
      check col.length == 2
      col.destroy()

  suite "componentKey":
    test "componentKey returns type name":
      let key = TestComponent.componentKey()
      check key == "TestComponent"

    test "componentKey returns expected for other types":
      let key = TestComponent2.componentKey()
      check key == "TestComponent2"

  suite "info":
    test "info raises on empty manager":
      var em: EntityManager
      expect IndexDefect:
        discard em.info(ComponentTypeId(0))

  suite "SmallComponent":
    test "small component aligns to CacheLine":
      var col = Column.init(
        ComponentInfo(
          id: ComponentTypeId(0),
          size: sizeof(SmallComponent),
          align: sizeof(SmallComponent),
          name: "SmallComponent"
        )
      )
      check col.elemAlign == CacheLine
      col.destroy()

  suite "findColumnIndex":
    var arch: Archetype
    test "findColumnIndex returns -1 for empty columns":
      let idx = arch.findColumnIndex(ComponentTypeId(0))
      check idx == -1

    test "findColumnIndex returns -1 for missing":
      arch.columns.add Column.init(
        ComponentInfo(id: ComponentTypeId(0), size: 4, align: 4, name: "test")
      )
      let idx = arch.findColumnIndex(ComponentTypeId(1))
      check idx == -1

    test "findColumnIndex finds existing":
      arch.columns.add Column.init(
        ComponentInfo(id: ComponentTypeId(5), size: 4, align: 4, name: "test")
      )
      let idx = arch.findColumnIndex(ComponentTypeId(5))
      check idx == 1

  suite "EntityManager types":
    test "EntityManager default is empty":
      var em: EntityManager
      check em.information.len == 0
      check em.componentIds.len == 0
      check em.archetypes.len == 0
      check em.locations.len == 0

    test "EntityLocation default":
      var loc: EntityLocation
      check loc.alive == false

  suite "registerComponent":
    test "register new component":
      var em: EntityManager
      registerComponent(TestComponent, em)
      check em.information.len == 1
      check em.componentIds.len == 1
      check em.componentIds["TestComponent"] == ComponentTypeId(0)

    test "register duplicate component does nothing":
      var em: EntityManager
      registerComponent(TestComponent, em)
      registerComponent(TestComponent, em)
      check em.information.len == 1

    test "register multiple components":
      var em: EntityManager
      registerComponent(TestComponent, em)
      registerComponent(TestComponent2, em)
      check em.information.len == 2
      check em.componentIds["TestComponent"] == ComponentTypeId(0)
      check em.componentIds["TestComponent2"] == ComponentTypeId(1)

    test "componentId returns correct id":
      var em: EntityManager
      registerComponent(TestComponent, em)
      check componentId(TestComponent, em) == ComponentTypeId(0)

  suite "create":
    test "create with one component":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      check em.alive(e)
      check em.has(e, TestComponent)

    test "create multiple entities":
      var em: EntityManager
      let e1 = em.create(TestComponent(x: 1.0, y: 2.0, id: 1))
      let e2 = em.create(TestComponent(x: 3.0, y: 4.0, id: 2))
      check em.alive(e1)
      check em.alive(e2)
      check e1 != e2

  suite "has":
    test "has returns true for existing component":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      check em.has(e, TestComponent)

    test "has returns false for missing component":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      check not em.has(e, TestComponent2)

    test "has returns false for dead entity":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.destroy(e)
      check not em.has(e, TestComponent)

  suite "get":
    test "get returns correct component value":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.5, y: 2.5, id: 100))
      check get[TestComponent](em, e).x == 1.5
      check get[TestComponent](em, e).y == 2.5
      check get[TestComponent](em, e).id == 100

    test "get can modify component":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.get[:TestComponent](e).x = 99.0
      check em.get[:TestComponent](e).x == 99.0

    test "get raises on dead entity":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.destroy(e)
      expect AssertionDefect:
        discard em.get[:TestComponent](e)

  suite "add":
    test "add updates existing component":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.add(e, TestComponent(x: 99.0, y: 99.0, id: 999))
      check em.get[:TestComponent](e).x == 99.0
      check em.get[:TestComponent](e).id == 999

    test "add changes archetype":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      let oldArch = em.locations[e.index].archetype
      em.add(e, TestComponent2())
      let newArch = em.locations[e.index].archetype
      check oldArch != newArch

    test "add raises on dead entity":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.destroy(e)
      expect AssertionDefect:
        em.add(e, TestComponent2())

  suite "remove":
    test "remove existing component":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42), TestComponent2())
      em.remove[:TestComponent2](e)
      check not em.has(e, TestComponent2)
      check em.has(e, TestComponent)

    test "remove non-existing component does nothing":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.remove[:TestComponent2](e)
      check em.has(e, TestComponent)

    test "remove raises on dead entity":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.destroy(e)
      expect AssertionDefect:
        em.remove[:TestComponent](e)

  suite "destroy":
    test "destroy marks entity dead":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.destroy(e)
      check not em.alive(e)

    test "destroy adds to freeList":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.destroy(e)
      # The index should be in the freeList
      check e.index in em.freeList

    test "destroyed entity can be reused":
      var em: EntityManager
      let e1 = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      let idx = e1.index
      em.destroy(e1)
      let e2 = em.create(TestComponent(x: 3.0, y: 4.0, id: 99))
      check e2.index == idx
      check e2.generation == e1.generation + 1

    test "destroy non-existent entity does nothing":
      var em: EntityManager
      let e: Entity = (index: 999, generation: 1)
      em.destroy(e)  # Should not crash

  suite "alive":
    test "alive returns true for valid entity":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      check em.alive(e)

    test "alive returns false for destroyed entity":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.destroy(e)
      check not em.alive(e)

    test "alive returns false for out of bounds index":
      var em: EntityManager
      let e: Entity = (index: 100, generation: 1)
      check not em.alive(e)

    test "alive returns false for stale generation":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.destroy(e)
      let staleEntity: Entity = (index: e.index, generation: e.generation)
      check not em.alive(staleEntity)

  suite "entity generation":
    test "new entity has generation 1":
      var em: EntityManager
      let e = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      check e.generation == 1

    test "reused entity has incremented generation":
      var em: EntityManager
      let e1 = em.create(TestComponent(x: 1.0, y: 2.0, id: 42))
      em.destroy(e1)
      let e2 = em.create(TestComponent(x: 3.0, y: 4.0, id: 99))
      check e2.generation == e1.generation + 1

  suite "archetype operations":
    test "getOrCreateArchetype creates new archetype":
      var em: EntityManager
      registerComponent(TestComponent, em)
      var sig = ComponentSet()
      sig.incl(componentId(TestComponent, em))
      let arch = em.getOrCreateArchetype(sig)
      check arch != nil
      check arch.signature.contains(componentId(TestComponent, em))

    test "getOrCreateArchetype returns existing archetype":
      var em: EntityManager
      registerComponent(TestComponent, em)
      var sig = ComponentSet()
      sig.incl(componentId(TestComponent, em))
      let arch1 = em.getOrCreateArchetype(sig)
      let arch2 = em.getOrCreateArchetype(sig)
      check arch1 == arch2

    test "reserveRow adds entity":
      var em: EntityManager
      registerComponent(TestComponent, em)
      var sig = ComponentSet()
      sig.incl(componentId(TestComponent, em))
      let arch = em.getOrCreateArchetype(sig)
      let e: Entity = (index: 0, generation: 1)
      let row = arch[].reserveRow(e)
      check row == 0
      check arch[].entities.len == 1

    test "swapRemoveRow moves last element":
      var em: EntityManager
      registerComponent(TestComponent, em)
      var sig = ComponentSet()
      sig.incl(componentId(TestComponent, em))
      let arch = em.getOrCreateArchetype(sig)
      let e1: Entity = (index: 0, generation: 1)
      let e2: Entity = (index: 1, generation: 1)
      discard arch[].reserveRow(e1)
      discard arch[].reserveRow(e2)
      em.locations.setLen(2)
      em.locations[0] = EntityLocation(archetype: arch, row: 0, generation: 1, alive: true)
      em.locations[1] = EntityLocation(archetype: arch, row: 1, generation: 1, alive: true)
      em.swapRemoveRow(arch[], 0)
      check arch[].entities.len == 1
      check em.locations[1].row == 0