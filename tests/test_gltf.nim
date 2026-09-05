import std/[json, options, streams, unittest]

import ellipse/gltf
import ellipse/rendering/artist3D

proc exampleGltf(withBinary = false): Gltf =
  result = Gltf(
    asset: Asset(version: "2.0"),
    scene: some(0'u32),
    scenes: @[Scene(nodes: @[0'u32])],
    nodes: @[Node(name: some("Root"))],
  )
  if withBinary:
    result.buffers = @[Buffer(byteLength: 3)]

test "standalone glTF JSON round-trips":
  let encoded = newStringStream()
  encoded.write(exampleGltf())
  encoded.setPosition(0)

  var decoded: Gltf
  encoded.read(decoded)

  check decoded.asset.version == "2.0"
  check decoded.scene == some(0'u32)
  check decoded.nodes[0].name == some("Root")
  check not parseJson(encoded.data).hasKey("animations")

test "JSON-only GLB round-trips":
  let encoded = newStringStream()
  encoded.write(Glb(gltf: exampleGltf()))
  check encoded.data.len mod 4 == 0
  encoded.setPosition(0)

  var decoded: Glb
  encoded.read(decoded)

  check decoded.header.magic == GlbMagic
  check decoded.header.version == GlbVersion
  check decoded.header.totalLength == encoded.data.len.uint32
  check decoded.gltf.asset.version == "2.0"
  check decoded.binary.len == 0

test "binary GLB removes and restores alignment padding":
  let encoded = newStringStream()
  encoded.write(Glb(gltf: exampleGltf(true), binary: "\x01\x02\x03"))
  check encoded.data.len mod 4 == 0
  encoded.setPosition(0)

  var decoded: Glb
  encoded.read(decoded)

  check decoded.gltf.buffers[0].byteLength == 3
  check decoded.binary == "\x01\x02\x03"

test "GLB rejects a missing binary chunk":
  let encoded = newStringStream()
  expect GlbError:
    encoded.write(Glb(gltf: exampleGltf(true)))

test "GLB rejects data beyond its declared length":
  let encoded = newStringStream()
  encoded.write(Glb(gltf: exampleGltf()))
  encoded.write("trailing")
  encoded.setPosition(0)

  var decoded: Glb
  expect GlbError:
    encoded.read(decoded)

test "existing Suzanne GLB imports":
  let stream = openFileStream("res/Suzzane.glb", fmRead)
  require stream != nil
  defer: stream.close()

  var model: Glb
  stream.read(model)

  check model.gltf.asset.version == "2.0"
  check model.gltf.meshes.len > 0
  check model.binary.len > 0
  check model.importModels(default(Artist3D), "test-suzanne").len == 1

  let exported = newStringStream()
  exported.write(model)
  exported.setPosition(0)
  var roundTripped: Glb
  exported.read(roundTripped)

  check roundTripped.gltf.meshes.len == model.gltf.meshes.len
  check roundTripped.gltf.accessors.len == model.gltf.accessors.len
  check roundTripped.binary == model.binary
