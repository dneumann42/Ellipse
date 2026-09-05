## Types for the glTF 2.0 core JSON schema.

import std/[json, options, tables]

type
  GltfIndex* = uint32
  GltfExtensions* = Table[string, JsonNode]

  AccessorComponentType* = enum
    Byte = 5120, UnsignedByte = 5121, Short = 5122,
    UnsignedShort = 5123, UnsignedInt = 5125, Float = 5126
  AccessorType* = enum
    Scalar, Vec2, Vec3, Vec4, Mat2, Mat3, Mat4
  SparseIndexComponentType* = enum
    UnsignedByte = 5121, UnsignedShort = 5123, UnsignedInt = 5125
  PrimitiveMode* = enum
    Points = 0, Lines = 1, LineLoop = 2, LineStrip = 3,
    Triangles = 4, TriangleStrip = 5, TriangleFan = 6
  BufferViewTarget* = enum
    ArrayBuffer = 34962, ElementArrayBuffer = 34963
  MagnificationFilter* = enum
    Nearest = 9728, Linear = 9729
  MinificationFilter* = enum
    Nearest = 9728, Linear = 9729,
    NearestMipmapNearest = 9984, LinearMipmapNearest = 9985,
    NearestMipmapLinear = 9986, LinearMipmapLinear = 9987
  WrapMode* = enum
    ClampToEdge = 33071, MirroredRepeat = 33648, Repeat = 10497
  AlphaMode* = enum
    Opaque, Mask, Blend
  Interpolation* = enum
    Linear, Step, CubicSpline
  AnimationPath* = enum
    Translation, Rotation, Scale, Weights
  CameraType* = enum
    Perspective, Orthographic
  ImageMimeType* = enum
    Jpeg, Png

  GltfProperty* = object of RootObj
    extensions*: Option[GltfExtensions]
    extras*: Option[JsonNode]

  GltfNamedProperty* = object of GltfProperty
    name*: Option[string]

  Asset* = object of GltfProperty
    copyright*, generator*: Option[string]
    version*: string
    minVersion*: Option[string]

  Buffer* = object of GltfNamedProperty
    uri*: Option[string]
    byteLength*: uint32

  BufferView* = object of GltfNamedProperty
    buffer*: GltfIndex
    byteOffset*: Option[uint32]
    byteLength*: uint32
    byteStride*: Option[uint32]
    target*: Option[BufferViewTarget]

  AccessorSparseIndices* = object of GltfProperty
    bufferView*: GltfIndex
    byteOffset*: Option[uint32]
    componentType*: SparseIndexComponentType

  AccessorSparseValues* = object of GltfProperty
    bufferView*: GltfIndex
    byteOffset*: Option[uint32]

  AccessorSparse* = object of GltfProperty
    count*: uint32
    indices*: AccessorSparseIndices
    values*: AccessorSparseValues

  Accessor* = object of GltfNamedProperty
    bufferView*: Option[GltfIndex]
    byteOffset*: Option[uint32]
    componentType*: AccessorComponentType
    normalized*: Option[bool]
    count*: uint32
    `type`*: AccessorType
    max*, min*: seq[float64]
    sparse*: Option[AccessorSparse]

  Image* = object of GltfNamedProperty
    uri*: Option[string]
    mimeType*: Option[ImageMimeType]
    bufferView*: Option[GltfIndex]

  Sampler* = object of GltfNamedProperty
    magFilter*: Option[MagnificationFilter]
    minFilter*: Option[MinificationFilter]
    wrapS*, wrapT*: Option[WrapMode]

  Texture* = object of GltfNamedProperty
    sampler*, source*: Option[GltfIndex]

  TextureInfo* = object of GltfProperty
    index*: GltfIndex
    texCoord*: Option[uint32]

  NormalTextureInfo* = object of TextureInfo
    scale*: Option[float64]

  OcclusionTextureInfo* = object of TextureInfo
    strength*: Option[float64]

  MaterialPbrMetallicRoughness* = object of GltfProperty
    baseColorFactor*: Option[array[4, float64]]
    baseColorTexture*: Option[TextureInfo]
    metallicFactor*, roughnessFactor*: Option[float64]
    metallicRoughnessTexture*: Option[TextureInfo]

  Material* = object of GltfNamedProperty
    pbrMetallicRoughness*: Option[MaterialPbrMetallicRoughness]
    normalTexture*: Option[NormalTextureInfo]
    occlusionTexture*, emissiveTexture*: Option[TextureInfo]
    emissiveFactor*: Option[array[3, float64]]
    alphaMode*: Option[AlphaMode]
    alphaCutoff*: Option[float64]
    doubleSided*: Option[bool]

  MorphTarget* = Table[string, GltfIndex]

  MeshPrimitive* = object of GltfProperty
    attributes*: Table[string, GltfIndex]
    indices*, material*: Option[GltfIndex]
    mode*: Option[PrimitiveMode]
    targets*: seq[MorphTarget]

  Mesh* = object of GltfNamedProperty
    primitives*: seq[MeshPrimitive]
    weights*: seq[float64]

  CameraPerspective* = object of GltfProperty
    aspectRatio*: Option[float64]
    yfov*: float64
    zfar*: Option[float64]
    znear*: float64

  CameraOrthographic* = object of GltfProperty
    xmag*, ymag*, zfar*, znear*: float64

  Camera* = object of GltfNamedProperty
    `type`*: CameraType
    perspective*: Option[CameraPerspective]
    orthographic*: Option[CameraOrthographic]

  Node* = object of GltfNamedProperty
    camera*: Option[GltfIndex]
    children*: seq[GltfIndex]
    skin*: Option[GltfIndex]
    matrix*: Option[array[16, float64]]
    mesh*: Option[GltfIndex]
    rotation*: Option[array[4, float64]]
    scale*, translation*: Option[array[3, float64]]
    weights*: seq[float64]

  Skin* = object of GltfNamedProperty
    inverseBindMatrices*, skeleton*: Option[GltfIndex]
    joints*: seq[GltfIndex]

  Scene* = object of GltfNamedProperty
    nodes*: seq[GltfIndex]

  AnimationSampler* = object of GltfProperty
    input*: GltfIndex
    interpolation*: Option[Interpolation]
    output*: GltfIndex

  AnimationChannelTarget* = object of GltfProperty
    node*: Option[GltfIndex]
    path*: AnimationPath

  AnimationChannel* = object of GltfProperty
    sampler*: GltfIndex
    target*: AnimationChannelTarget

  Animation* = object of GltfNamedProperty
    channels*: seq[AnimationChannel]
    samplers*: seq[AnimationSampler]

  Gltf* = object of GltfProperty
    asset*: Asset
    extensionsUsed*, extensionsRequired*: seq[string]
    accessors*: seq[Accessor]
    animations*: seq[Animation]
    buffers*: seq[Buffer]
    bufferViews*: seq[BufferView]
    cameras*: seq[Camera]
    images*: seq[Image]
    materials*: seq[Material]
    meshes*: seq[Mesh]
    nodes*: seq[Node]
    samplers*: seq[Sampler]
    scene*: Option[GltfIndex]
    scenes*: seq[Scene]
    skins*: seq[Skin]
    textures*: seq[Texture]

proc gltfEnumName[E: enum](value: E): string =
  when E is AccessorType:
    case value
    of Scalar: "SCALAR"
    of Vec2: "VEC2"
    of Vec3: "VEC3"
    of Vec4: "VEC4"
    of Mat2: "MAT2"
    of Mat3: "MAT3"
    of Mat4: "MAT4"
  elif E is AlphaMode:
    case value
    of Opaque: "OPAQUE"
    of Mask: "MASK"
    of Blend: "BLEND"
  elif E is Interpolation:
    case value
    of Linear: "LINEAR"
    of Step: "STEP"
    of CubicSpline: "CUBICSPLINE"
  elif E is AnimationPath:
    case value
    of Translation: "translation"
    of Rotation: "rotation"
    of Scale: "scale"
    of Weights: "weights"
  elif E is CameraType:
    case value
    of Perspective: "perspective"
    of Orthographic: "orthographic"
  elif E is ImageMimeType:
    case value
    of Jpeg: "image/jpeg"
    of Png: "image/png"
  else:
    $value

proc `%`*[E: enum](value: E): JsonNode =
  ## Encodes glTF enums using their schema representation.
  when E is AccessorComponentType or E is SparseIndexComponentType or
       E is PrimitiveMode or E is BufferViewTarget or
       E is MagnificationFilter or E is MinificationFilter or E is WrapMode:
    %ord(value)
  else:
    %gltfEnumName(value)

proc invalidEnum[E: enum](value: string, path: string): E =
  raise newException(ValueError, "Invalid " & $E & " at " & path & ": " & value)

proc initFromJson*[E: enum](dst: var E; jsonNode: JsonNode; jsonPath: var string) =
  ## Decodes glTF enums, whose JSON spelling is not always Nim's enum name.
  when E is AccessorComponentType or E is SparseIndexComponentType or
       E is PrimitiveMode or E is BufferViewTarget or
       E is MagnificationFilter or E is MinificationFilter or E is WrapMode:
    if jsonNode.kind != JInt:
      raise newException(JsonKindError, "Expected integer at " & jsonPath)
    dst = E(jsonNode.getInt)
  else:
    if jsonNode.kind != JString:
      raise newException(JsonKindError, "Expected string at " & jsonPath)
    let value = jsonNode.getStr
    when E is AccessorType:
      case value
      of "SCALAR": dst = Scalar
      of "VEC2": dst = Vec2
      of "VEC3": dst = Vec3
      of "VEC4": dst = Vec4
      of "MAT2": dst = Mat2
      of "MAT3": dst = Mat3
      of "MAT4": dst = Mat4
      else: dst = invalidEnum[E](value, jsonPath)
    elif E is AlphaMode:
      case value
      of "OPAQUE": dst = Opaque
      of "MASK": dst = Mask
      of "BLEND": dst = Blend
      else: dst = invalidEnum[E](value, jsonPath)
    elif E is Interpolation:
      case value
      of "LINEAR": dst = Linear
      of "STEP": dst = Step
      of "CUBICSPLINE": dst = CubicSpline
      else: dst = invalidEnum[E](value, jsonPath)
    elif E is AnimationPath:
      case value
      of "translation": dst = Translation
      of "rotation": dst = Rotation
      of "scale": dst = Scale
      of "weights": dst = Weights
      else: dst = invalidEnum[E](value, jsonPath)
    elif E is CameraType:
      case value
      of "perspective": dst = Perspective
      of "orthographic": dst = Orthographic
      else: dst = invalidEnum[E](value, jsonPath)
    elif E is ImageMimeType:
      case value
      of "image/jpeg": dst = Jpeg
      of "image/png": dst = Png
      else: dst = invalidEnum[E](value, jsonPath)
    else:
      dst = parseEnum[E](value)

proc initFromJson*[T: GltfProperty](dst: var T; jsonNode: JsonNode;
                                    jsonPath: var string)

proc readJson(dst: var string; jsonNode: JsonNode; jsonPath: var string) =
  if jsonNode.kind != JString:
    raise newException(JsonKindError, "Expected string at " & jsonPath)
  dst = jsonNode.getStr

proc readJson(dst: var bool; jsonNode: JsonNode; jsonPath: var string) =
  if jsonNode.kind != JBool:
    raise newException(JsonKindError, "Expected boolean at " & jsonPath)
  dst = jsonNode.getBool

proc readJson(dst: var JsonNode; jsonNode: JsonNode; _: var string) =
  dst = jsonNode.copy

proc readJson[T: SomeInteger](dst: var T; jsonNode: JsonNode; jsonPath: var string) =
  if jsonNode.kind != JInt:
    raise newException(JsonKindError, "Expected integer at " & jsonPath)
  dst = T(jsonNode.getBiggestInt)

proc readJson[T: SomeFloat](dst: var T; jsonNode: JsonNode; jsonPath: var string) =
  if jsonNode.kind notin {JInt, JFloat}:
    raise newException(JsonKindError, "Expected number at " & jsonPath)
  dst = T(jsonNode.getFloat)

proc readJson[E: enum](dst: var E; jsonNode: JsonNode; jsonPath: var string) =
  initFromJson(dst, jsonNode, jsonPath)

proc readJson[T: GltfProperty](dst: var T; jsonNode: JsonNode; jsonPath: var string) =
  initFromJson(dst, jsonNode, jsonPath)

proc readJson[T](dst: var Table[string, T]; jsonNode: JsonNode; jsonPath: var string)

proc readJson[T](dst: var seq[T]; jsonNode: JsonNode; jsonPath: var string) =
  if jsonNode.kind != JArray:
    raise newException(JsonKindError, "Expected array at " & jsonPath)
  dst.setLen(jsonNode.len)
  for index in 0 ..< jsonNode.len:
    let child = jsonNode[index]
    let originalPathLength = jsonPath.len
    jsonPath.add '['
    jsonPath.addInt(index)
    jsonPath.add ']'
    readJson(dst[index], child, jsonPath)
    jsonPath.setLen(originalPathLength)

proc readJson[S, T](dst: var array[S, T]; jsonNode: JsonNode; jsonPath: var string) =
  if jsonNode.kind != JArray or jsonNode.len != dst.len:
    raise newException(JsonKindError, "Expected array of length " & $dst.len & " at " & jsonPath)
  for index in 0 ..< jsonNode.len:
    let child = jsonNode[index]
    let originalPathLength = jsonPath.len
    jsonPath.add '['
    jsonPath.addInt(index)
    jsonPath.add ']'
    readJson(dst[index.S], child, jsonPath)
    jsonPath.setLen(originalPathLength)

proc readJson[T](dst: var Table[string, T]; jsonNode: JsonNode; jsonPath: var string) =
  if jsonNode.kind != JObject:
    raise newException(JsonKindError, "Expected object at " & jsonPath)
  dst = initTable[string, T]()
  for key, child in jsonNode:
    let originalPathLength = jsonPath.len
    jsonPath.add '.'
    jsonPath.add key
    var value: T
    readJson(value, child, jsonPath)
    dst[key] = value
    jsonPath.setLen(originalPathLength)

proc readJson[T](dst: var Option[T]; jsonNode: JsonNode; jsonPath: var string) =
  if jsonNode.kind != JNull:
    dst = some(default(T))
    readJson(dst.get, jsonNode, jsonPath)

proc `%`*(value: GltfExtensions): JsonNode =
  result = newJObject()
  for key, child in value.pairs:
    result[key] = child

proc writeJson[T](value: T): JsonNode =
  %value

proc writeJson[E: enum](value: E): JsonNode =
  when E is AccessorComponentType or E is SparseIndexComponentType or
       E is PrimitiveMode or E is BufferViewTarget or
       E is MagnificationFilter or E is MinificationFilter or E is WrapMode:
    newJInt(ord(value))
  else:
    newJString(gltfEnumName(value))

proc writeJson[T: GltfProperty](value: T): JsonNode

proc writeJson[T](value: Option[T]): JsonNode =
  if value.isSome: writeJson(value.get) else: newJNull()

proc writeJson[T](value: Table[string, T]): JsonNode

proc writeJson[T](value: seq[T]): JsonNode =
  result = newJArray()
  for child in value:
    result.add(writeJson(child))

proc writeJson[S, T](value: array[S, T]): JsonNode =
  result = newJArray()
  for child in value:
    result.add(writeJson(child))

proc writeJson[T](value: Table[string, T]): JsonNode =
  result = newJObject()
  for key, child in value.pairs:
    result[key] = writeJson(child)

proc `%`*[T: GltfProperty](value: T): JsonNode =
  ## Encodes a glTF object, omitting absent optional members and empty
  ## collections. In the glTF schema collections are either optional or must
  ## contain at least one item, so an empty collection must not be emitted.
  result = newJObject()
  for key, field in value.fieldPairs:
    when field is Option:
      if field.isSome:
        result[key] = writeJson(field.get)
    elif field is seq or field is Table:
      if field.len > 0:
        result[key] = writeJson(field)
    else:
      result[key] = writeJson(field)

proc writeJson[T: GltfProperty](value: T): JsonNode =
  %value

proc initFromJson*[T: GltfProperty](dst: var T; jsonNode: JsonNode;
                                    jsonPath: var string) =
  ## Decodes a glTF object. Absent optional and collection members retain
  ## their default values (`none` and `@[]`, respectively).
  if jsonNode == nil or jsonNode.kind != JObject:
    raise newException(JsonKindError, "Expected object at " & jsonPath)
  for key, field in dst.fieldPairs:
    if jsonNode.hasKey(key):
      let originalPathLength = jsonPath.len
      jsonPath.add '.'
      jsonPath.add key
      readJson(field, jsonNode[key], jsonPath)
      jsonPath.setLen(originalPathLength)

proc initFromJson*[T: GltfProperty](jsonNode: JsonNode; _: typedesc[T]): T =
  ## Convenience form mirroring `JsonNode.to`.
  var path = "$"
  initFromJson(result, jsonNode, path)
