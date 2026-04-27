import std/[tables, hashes, algorithm, typeinfo]

import ../base

import componentSets

type
  Entity* = tuple[index, generation: uint32]
  ComponentTypeId* = distinct uint16
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

proc column(
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
    data: allocAligned(info.size * initialCapacity, result.elemAlign)
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

proc registerComponent*[T](entityManager: EntityManager) =
  let key = T.componentKey()
  if key in entityManager.componentIds:
    return
  doAssert world.componentInfos.len < 256, "ComponentSet only supports 256 component types"
  let id = ComponentTypeId(entityManager.information.len)
  entityManager.componentIds[key] = id
  entityManager.information.add ComponentInfo(
    id: id,
    size: sizeof(T),
    align: sizeof(T),
    name: key
  )

proc info(entityManager: EntityManager; id: ComponentTypeId): ComponentInfo =
  entityManager.information[uint16(id).int]

