## Reading and writing glTF 2.0 JSON (`.gltf`) and binary (`.glb`) files.

import std/[json, options, streams, tables]

import vmath

import gltfSchema
import rendering/artist3D

export gltfSchema

type
  Glb* = object
    ## A glTF document and its optional GLB binary buffer. Alignment padding
    ## is added and removed by the exporter and importer.
    header*: GlbHeader
    gltf*: Gltf
    binary*: string

  GlbHeader* = object
    magic*, version*, totalLength*: uint32

  GlbError* = object of CatchableError

const
  GlbMagic* = 0x46546C67'u32
  GlbVersion* = 2'u32
  GlbJsonChunk* = 0x4E4F534A'u32
  GlbBinaryChunk* = 0x004E4942'u32
  GlbHeaderLength = 12'u32
  GlbChunkHeaderLength = 8'u32

proc fail(message: string) {.noreturn.} =
  raise newException(GlbError, message)

proc readExact(stream: Stream, length: int, description: string): string =
  if length < 0:
    fail("Invalid negative " & description & " length")
  result = stream.readStr(length)
  if result.len != length:
    fail("Unexpected end of stream while reading " & description)

proc uint32Le(data: string, offset: int): uint32 =
  if offset < 0 or offset > data.len - 4:
    fail("Unexpected end of GLB data while reading a 32-bit value")
  result =
    data[offset].uint8.uint32 or
    (data[offset + 1].uint8.uint32 shl 8) or
    (data[offset + 2].uint8.uint32 shl 16) or
    (data[offset + 3].uint8.uint32 shl 24)

proc readUint32Le(stream: Stream): uint32 =
  result = uint32Le(stream.readExact(4, "32-bit value"), 0)

proc writeUint32Le(stream: Stream, value: uint32) =
  var encoded = newString(4)
  encoded[0] = char(value and 0xff)
  encoded[1] = char((value shr 8) and 0xff)
  encoded[2] = char((value shr 16) and 0xff)
  encoded[3] = char((value shr 24) and 0xff)
  stream.write(encoded)

proc paddedLength(length: int): int =
  if length > high(int) - 3:
    fail("GLB chunk is too large")
  result = (length + 3) and not 3

proc checkedUint32(length: int, description: string): uint32 =
  if length < 0 or uint64(length) > uint64(high(uint32)):
    fail(description & " is too large for a GLB file")
  result = uint32(length)

proc read*(stream: Stream, header: var GlbHeader) =
  header.magic = stream.readUint32Le()
  if header.magic != GlbMagic:
    fail("File is not GLB")
  header.version = stream.readUint32Le()
  if header.version != GlbVersion:
    fail("Unsupported GLB version " & $header.version)
  header.totalLength = stream.readUint32Le()
  if header.totalLength < GlbHeaderLength + GlbChunkHeaderLength:
    fail("Invalid GLB length " & $header.totalLength)

proc read*(stream: Stream, gltf: var Gltf) =
  ## Imports a JSON glTF document from the stream's current position.
  let source = stream.readAll()
  if source.len == 0:
    fail("Empty glTF JSON document")
  try:
    gltf = parseJson(source).to(Gltf)
  except JsonParsingError, JsonKindError, ValueError, RangeDefect:
    fail("Invalid glTF JSON: " & getCurrentExceptionMsg())

proc write*(stream: Stream, gltf: Gltf) =
  ## Exports a compact JSON glTF document.
  stream.write($(%gltf))

proc read*(stream: Stream, glb: var Glb) =
  ## Imports one GLB from the stream. Unknown extension chunks are ignored.
  glb = Glb()
  stream.read(glb.header)

  let bodyLength = int(glb.header.totalLength - GlbHeaderLength)
  let body = stream.readExact(bodyLength, "GLB body")
  if not stream.atEnd():
    fail("GLB contains data beyond its declared total length")
  var
    offset = 0
    chunkIndex = 0
    foundJson = false
    foundBinary = false

  while offset < body.len:
    if body.len - offset < int(GlbChunkHeaderLength):
      fail("Truncated GLB chunk header")
    let
      chunkLength = int(uint32Le(body, offset))
      chunkType = uint32Le(body, offset + 4)
    offset += int(GlbChunkHeaderLength)
    if (chunkLength and 3) != 0:
      fail("GLB chunk length must be a multiple of four")
    if chunkLength > body.len - offset:
      fail("GLB chunk extends beyond the declared file length")

    let chunk = body[offset ..< offset + chunkLength]
    offset += chunkLength

    if chunkIndex == 0 and chunkType != GlbJsonChunk:
      fail("The first GLB chunk must be JSON")
    case chunkType
    of GlbJsonChunk:
      if foundJson:
        fail("GLB contains more than one JSON chunk")
      let jsonStream = newStringStream(chunk)
      jsonStream.read(glb.gltf)
      foundJson = true
    of GlbBinaryChunk:
      if not foundJson:
        fail("GLB binary chunk appears before its JSON chunk")
      if foundBinary:
        fail("GLB contains more than one binary chunk")
      if glb.gltf.buffers.len == 0 or glb.gltf.buffers[0].uri.isSome:
        fail("GLB binary chunk has no URI-less buffer declaration")
      let declaredLength = int(glb.gltf.buffers[0].byteLength)
      if declaredLength > chunk.len or chunk.len - declaredLength > 3:
        fail("GLB binary chunk length does not match buffers[0].byteLength")
      glb.binary = chunk[0 ..< declaredLength]
      foundBinary = true
    else:
      discard
    inc chunkIndex

  if not foundJson:
    fail("GLB does not contain a JSON chunk")
  if glb.gltf.buffers.len > 0 and glb.gltf.buffers[0].uri.isNone and
      glb.gltf.buffers[0].byteLength > 0 and not foundBinary:
    fail("GLB URI-less buffers[0] has no binary chunk")

proc writeChunk(stream: Stream, chunkType: uint32, payload: string,
                padding: char) =
  let length = paddedLength(payload.len)
  stream.writeUint32Le(checkedUint32(length, "GLB chunk"))
  stream.writeUint32Le(chunkType)
  stream.write(payload)
  for _ in payload.len ..< length:
    stream.write(padding)

proc write*(stream: Stream, glb: Glb) =
  ## Exports a GLB 2.0 document. Header values are calculated rather than
  ## trusting the cached values in `glb.header`.
  if glb.binary.len > 0:
    if glb.gltf.buffers.len == 0 or glb.gltf.buffers[0].uri.isSome:
      fail("GLB binary data requires a URI-less buffers[0]")
    if uint64(glb.binary.len) != uint64(glb.gltf.buffers[0].byteLength):
      fail("GLB binary data length must equal buffers[0].byteLength")
  elif glb.gltf.buffers.len > 0 and glb.gltf.buffers[0].uri.isNone and
      glb.gltf.buffers[0].byteLength > 0:
    fail("GLB URI-less buffers[0] requires binary data")

  let
    jsonPayload = $(%glb.gltf)
    jsonLength = paddedLength(jsonPayload.len)
    binaryLength = paddedLength(glb.binary.len)
    binarySectionLength =
      if glb.binary.len > 0: int(GlbChunkHeaderLength) + binaryLength else: 0
    totalLength = int(GlbHeaderLength) + int(GlbChunkHeaderLength) +
      jsonLength + binarySectionLength

  stream.writeUint32Le(GlbMagic)
  stream.writeUint32Le(GlbVersion)
  stream.writeUint32Le(checkedUint32(totalLength, "GLB file"))
  stream.writeChunk(GlbJsonChunk, jsonPayload, ' ')
  if glb.binary.len > 0:
    stream.writeChunk(GlbBinaryChunk, glb.binary, '\0')

proc componentCount(accessorType: AccessorType): int =
  case accessorType
  of Scalar: 1
  of Vec2: 2
  of Vec3: 3
  of Vec4, Mat2: 4
  of Mat3: 9
  of Mat4: 16

proc componentSize(componentType: AccessorComponentType): int =
  case componentType
  of Byte, UnsignedByte: 1
  of Short, UnsignedShort: 2
  of UnsignedInt, Float: 4

proc readUint16Le(data: string, offset: int): uint16 =
  if offset < 0 or offset > data.len - 2:
    fail("Accessor extends beyond the GLB binary buffer")
  result = data[offset].uint8.uint16 or
    (data[offset + 1].uint8.uint16 shl 8)

proc componentFloat(data: string, offset: int,
                    componentType: AccessorComponentType,
                    normalized: bool): float32 =
  case componentType
  of Byte:
    let value = cast[int8](data[offset].uint8)
    result = if normalized: max(value.float32 / 127'f32, -1'f32)
      else: value.float32
  of UnsignedByte:
    let value = data[offset].uint8
    result = if normalized: value.float32 / 255'f32 else: value.float32
  of Short:
    let value = cast[int16](readUint16Le(data, offset))
    result = if normalized: max(value.float32 / 32767'f32, -1'f32)
      else: value.float32
  of UnsignedShort:
    let value = readUint16Le(data, offset)
    result = if normalized: value.float32 / 65535'f32 else: value.float32
  of UnsignedInt:
    let value = uint32Le(data, offset)
    result = if normalized: value.float64.float32 / 4294967295'f32
      else: value.float32
  of Float:
    result = cast[float32](uint32Le(data, offset))

proc componentUint(data: string, offset: int,
                   componentType: AccessorComponentType): uint32 =
  case componentType
  of UnsignedByte: data[offset].uint8.uint32
  of UnsignedShort: readUint16Le(data, offset).uint32
  of UnsignedInt: uint32Le(data, offset)
  else: fail("Index accessor must use an unsigned integer component type")

proc checkedView(glb: Glb, index: GltfIndex): BufferView =
  if uint64(index) >= uint64(glb.gltf.bufferViews.len):
    fail("Accessor references a missing buffer view")
  result = glb.gltf.bufferViews[index.int]
  if result.buffer != 0:
    fail("GLB mesh accessor references an external buffer")
  let
    start = if result.byteOffset.isSome: result.byteOffset.get.int else: 0
    finish = start + result.byteLength.int
  if start < 0 or finish < start or finish > glb.binary.len:
    fail("Buffer view extends beyond the GLB binary buffer")

proc validateRange(glb: Glb, accessor: Accessor, view: BufferView,
                   packedSize, stride: int): int =
  let
    viewStart = if view.byteOffset.isSome: view.byteOffset.get.int else: 0
    accessorOffset = if accessor.byteOffset.isSome: accessor.byteOffset.get.int else: 0
    count = accessor.count.int
  if stride < packedSize:
    fail("Accessor byteStride is smaller than its element size")
  if accessorOffset < 0 or accessorOffset > view.byteLength.int:
    fail("Accessor offset is outside its buffer view")
  if count > 0:
    let required = accessorOffset + (count - 1) * stride + packedSize
    if required < accessorOffset or required > view.byteLength.int:
      fail("Accessor extends beyond its buffer view")
  result = viewStart + accessorOffset

proc sparseIndices(glb: Glb, sparse: AccessorSparse): seq[int] =
  let
    view = glb.checkedView(sparse.indices.bufferView)
    componentType = AccessorComponentType(ord(sparse.indices.componentType))
    size = componentSize(componentType)
    viewStart = if view.byteOffset.isSome: view.byteOffset.get.int else: 0
    offset = if sparse.indices.byteOffset.isSome:
      sparse.indices.byteOffset.get.int else: 0
    count = sparse.count.int
  if offset < 0 or offset + count * size > view.byteLength.int:
    fail("Sparse accessor indices extend beyond their buffer view")
  for index in 0 ..< count:
    result.add componentUint(glb.binary, viewStart + offset + index * size,
      componentType).int

proc accessorFloats(glb: Glb, accessorIndex: GltfIndex): seq[float32] =
  if uint64(accessorIndex) >= uint64(glb.gltf.accessors.len):
    fail("Mesh references a missing accessor")
  let
    accessor = glb.gltf.accessors[accessorIndex.int]
    components = componentCount(accessor.type)
    size = componentSize(accessor.componentType)
    packedSize = components * size
    normalized = accessor.normalized.isSome and accessor.normalized.get
  result.setLen(accessor.count.int * components)

  if accessor.bufferView.isSome:
    let view = glb.checkedView(accessor.bufferView.get)
    let stride = if view.byteStride.isSome: view.byteStride.get.int else: packedSize
    let start = glb.validateRange(accessor, view, packedSize, stride)
    for element in 0 ..< accessor.count.int:
      for component in 0 ..< components:
        result[element * components + component] = componentFloat(
          glb.binary, start + element * stride + component * size,
          accessor.componentType, normalized)

  if accessor.sparse.isSome:
    let
      sparse = accessor.sparse.get
      indices = glb.sparseIndices(sparse)
      view = glb.checkedView(sparse.values.bufferView)
      viewStart = if view.byteOffset.isSome: view.byteOffset.get.int else: 0
      offset = if sparse.values.byteOffset.isSome:
        sparse.values.byteOffset.get.int else: 0
      valuesSize = sparse.count.int * packedSize
    if offset < 0 or offset + valuesSize > view.byteLength.int:
      fail("Sparse accessor values extend beyond their buffer view")
    for sparseIndex, element in indices:
      if element < 0 or element >= accessor.count.int:
        fail("Sparse accessor index is out of range")
      for component in 0 ..< components:
        result[element * components + component] = componentFloat(
          glb.binary,
          viewStart + offset + sparseIndex * packedSize + component * size,
          accessor.componentType, normalized)

proc accessorIndices(glb: Glb, accessorIndex: GltfIndex): seq[uint32] =
  if uint64(accessorIndex) >= uint64(glb.gltf.accessors.len):
    fail("Mesh references a missing index accessor")
  let accessor = glb.gltf.accessors[accessorIndex.int]
  if accessor.type != Scalar:
    fail("Index accessor must have SCALAR type")
  let size = componentSize(accessor.componentType)
  result.setLen(accessor.count.int)
  if accessor.bufferView.isSome:
    let view = glb.checkedView(accessor.bufferView.get)
    let stride = if view.byteStride.isSome: view.byteStride.get.int else: size
    let start = glb.validateRange(accessor, view, size, stride)
    for index in 0 ..< result.len:
      result[index] = componentUint(glb.binary, start + index * stride,
        accessor.componentType)
  if accessor.sparse.isSome:
    let
      sparse = accessor.sparse.get
      indices = glb.sparseIndices(sparse)
      view = glb.checkedView(sparse.values.bufferView)
      viewStart = if view.byteOffset.isSome: view.byteOffset.get.int else: 0
      offset = if sparse.values.byteOffset.isSome:
        sparse.values.byteOffset.get.int else: 0
    if offset < 0 or offset + sparse.count.int * size > view.byteLength.int:
      fail("Sparse index values extend beyond their buffer view")
    for sparseIndex, element in indices:
      if element < 0 or element >= result.len:
        fail("Sparse accessor index is out of range")
      result[element] = componentUint(glb.binary,
        viewStart + offset + sparseIndex * size, accessor.componentType)

proc triangleIndices(indices: seq[uint32], mode: PrimitiveMode): seq[uint32] =
  case mode
  of Triangles:
    if indices.len mod 3 != 0:
      fail("Triangle primitive index count is not divisible by three")
    result = indices
  of TriangleStrip:
    for index in 2 ..< indices.len:
      if (index and 1) == 0:
        result.add [indices[index - 2], indices[index - 1], indices[index]]
      else:
        result.add [indices[index - 1], indices[index - 2], indices[index]]
  of TriangleFan:
    for index in 2 ..< indices.len:
      result.add [indices[0], indices[index - 1], indices[index]]
  else:
    fail("Ellipse's mesh renderer only supports triangle glTF primitives")

proc nodeTransform(node: Node): Mat4 =
  if node.matrix.isSome:
    let values = node.matrix.get
    for column in 0 .. 3:
      for row in 0 .. 3:
        result[column, row] = values[column * 4 + row].float32
    return
  let
    translation = if node.translation.isSome:
      vec3(node.translation.get[0].float32, node.translation.get[1].float32,
        node.translation.get[2].float32) else: vec3()
    scaling = if node.scale.isSome:
      vec3(node.scale.get[0].float32, node.scale.get[1].float32,
        node.scale.get[2].float32) else: vec3(1, 1, 1)
    rotation = if node.rotation.isSome:
      vec4(node.rotation.get[0].float32, node.rotation.get[1].float32,
        node.rotation.get[2].float32, node.rotation.get[3].float32) else: quat()
  result = translate(translation) * mat4(rotation) * scale(scaling)

proc importModels*(glb: Glb, artist: Artist3D,
                   namespace = "gltf"): seq[Model] =
  ## Converts all triangle primitives in the active glTF scene into Ellipse
  ## meshes and returns their node-instanced render models.
  var
    meshModels = newSeq[seq[Model]](glb.gltf.meshes.len)
    importedModels: seq[Model]
    visiting = newSeq[bool](glb.gltf.nodes.len)
  for meshIndex, mesh in glb.gltf.meshes:
    for primitiveIndex, primitive in mesh.primitives:
      if not primitive.attributes.hasKey("POSITION"):
        fail("glTF mesh primitive has no POSITION attribute")
      let
        positions = glb.accessorFloats(primitive.attributes["POSITION"])
        positionAccessor = glb.gltf.accessors[
          primitive.attributes["POSITION"].int]
      if positionAccessor.type != Vec3:
        fail("POSITION accessor must have VEC3 type")
      let vertexCount = positionAccessor.count.int
      var
        normals: seq[float32]
        uvs: seq[float32]
        vertices = newSeq[Vertex](vertexCount)
      if primitive.attributes.hasKey("NORMAL"):
        let normalAccessor = glb.gltf.accessors[
          primitive.attributes["NORMAL"].int]
        if normalAccessor.type != Vec3 or normalAccessor.count.int != vertexCount:
          fail("NORMAL accessor does not match POSITION")
        normals = glb.accessorFloats(primitive.attributes["NORMAL"])
      if primitive.attributes.hasKey("TEXCOORD_0"):
        let uvAccessor = glb.gltf.accessors[
          primitive.attributes["TEXCOORD_0"].int]
        if uvAccessor.type != Vec2 or uvAccessor.count.int != vertexCount:
          fail("TEXCOORD_0 accessor does not match POSITION")
        uvs = glb.accessorFloats(primitive.attributes["TEXCOORD_0"])
      for index in 0 ..< vertexCount:
        vertices[index].position = vec3(positions[index * 3],
          positions[index * 3 + 1], positions[index * 3 + 2])
        if normals.len > 0:
          vertices[index].normal = vec3(normals[index * 3],
            normals[index * 3 + 1], normals[index * 3 + 2])
        if uvs.len > 0:
          vertices[index].uv = vec2(uvs[index * 2], uvs[index * 2 + 1])

      var indices: seq[uint32]
      if primitive.indices.isSome:
        indices = glb.accessorIndices(primitive.indices.get)
      else:
        for index in 0 ..< vertexCount:
          indices.add index.uint32
      let mode = if primitive.mode.isSome: primitive.mode.get else: Triangles
      indices = triangleIndices(indices, mode)
      for index in indices:
        if index.int >= vertices.len:
          fail("Primitive index is outside its POSITION accessor")

      if normals.len == 0:
        for index in countup(0, indices.high, 3):
          let
            a = indices[index].int
            b = indices[index + 1].int
            c = indices[index + 2].int
            normal = cross(vertices[b].position - vertices[a].position,
              vertices[c].position - vertices[a].position)
          vertices[a].normal += normal
          vertices[b].normal += normal
          vertices[c].normal += normal
        for vertex in vertices.mitems:
          if length(vertex.normal) > 0.000001'f32:
            vertex.normal = normalize(vertex.normal)

      let meshId = namespace & ":mesh:" & $meshIndex & ":" & $primitiveIndex
      artist.setMesh(meshId, vertices, indices)
      var renderOptions = RenderOptions.init()
      if primitive.material.isSome:
        let materialIndex = primitive.material.get.int
        if materialIndex < 0 or materialIndex >= glb.gltf.materials.len:
          fail("Primitive references a missing material")
        let source = glb.gltf.materials[materialIndex]
        let materialId = namespace & ":material:" & $materialIndex
        var color = vec3(1, 1, 1)
        if source.pbrMetallicRoughness.isSome and
            source.pbrMetallicRoughness.get.baseColorFactor.isSome:
          let factor = source.pbrMetallicRoughness.get.baseColorFactor.get
          color = vec3(factor[0].float32, factor[1].float32, factor[2].float32)
        artist.setMaterial(artist3D.Material(id: materialId, baseColor: color))
        renderOptions = RenderOptions.init(materialID = materialId)
      meshModels[meshIndex].add Model.init(meshId, renderOptions = renderOptions)

  proc addNode(nodeIndex: int, parentTransform: Mat4) =
    if nodeIndex < 0 or nodeIndex >= glb.gltf.nodes.len:
      fail("Scene references a missing node")
    if visiting[nodeIndex]:
      fail("glTF node hierarchy contains a cycle")
    visiting[nodeIndex] = true
    defer: visiting[nodeIndex] = false
    let
      node = glb.gltf.nodes[nodeIndex]
      transform = parentTransform * node.nodeTransform
    if node.mesh.isSome:
      let meshIndex = node.mesh.get.int
      if meshIndex < 0 or meshIndex >= meshModels.len:
        fail("Node references a missing mesh")
      for sourceModel in meshModels[meshIndex]:
        var model = sourceModel
        model.transform = transform
        importedModels.add model
    for child in node.children:
      addNode(child.int, transform)

  var roots: seq[GltfIndex]
  if glb.gltf.scenes.len > 0:
    let sceneIndex = if glb.gltf.scene.isSome: glb.gltf.scene.get.int else: 0
    if sceneIndex < 0 or sceneIndex >= glb.gltf.scenes.len:
      fail("glTF default scene index is out of range")
    roots = glb.gltf.scenes[sceneIndex].nodes
  else:
    var isChild = newSeq[bool](glb.gltf.nodes.len)
    for node in glb.gltf.nodes:
      for child in node.children:
        if child.int < isChild.len:
          isChild[child.int] = true
    for index in 0 ..< isChild.len:
      if not isChild[index]: roots.add index.uint32
  for root in roots:
    addNode(root.int, mat4(quat()))
  result = move(importedModels)
