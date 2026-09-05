# Simple API for saving and loading game profiles.

import std/[os, oids, streams, tables, times]

import owl

const DateFormat = "yyyy-MM-dd HH:mm:ss zzz"

type
  ProfileID* = string
  Profile* = object
    id*: ProfileID
    name*: string
    lastWritten*: DateTime

proc init*(T: typedesc[Profile]): T =
  result = T(id: $genOid())

proc toOwl*(p: Profile): owl.Value =
  result = record([
    ("id", toOwl p.id),
    ("name", toOwl p.name),
    ("lastWritten", toOwl p.lastWritten.utc.format(DateFormat)),
  ])

proc fromOwl*(v: owl.Value, p: var Profile) =
  doAssert v.kind == Record
  v.entries["id"].fromOwl(p.id)
  v.entries["name"].fromOwl(p.name)

  var lastWritten: string
  v.entries["lastWritten"].fromOwl(lastWritten)
  p.lastWritten = times.parse(lastWritten, DateFormat, utc())

proc write*(profile: Profile, stream: Stream) =
  stream.write($profile.toOwl())
  stream.write("\n")

proc read*(profile: var Profile, stream: Stream) =
  readOwl(stream, "profile.owl").fromOwl(profile)

iterator profiles*(): Profile =
  let profilesDir = getDataDir() / "profiles"
  if not dirExists(profilesDir):
    createDir(profilesDir)
  for f in walkDir(profilesDir):
    if f.kind != pcDir:
      continue
    let metadataPath = f.path / "metadata.owl"
    if not fileExists(metadataPath):
      continue
    let stream = openFileStream(metadataPath, fmRead)
    defer: stream.close()
    var profile = Profile()
    profile.read(stream)
    yield profile

proc createProfile*(name: string) =
  var profile = Profile.init()
  profile.name = name
  profile.lastWritten = now()
  let profileDir = getDataDir() / "profiles" / profile.id
  if not dirExists(getDataDir() / "profiles"):
    createDir(getDataDir() / "profiles")
  if not dirExists(profileDir):
    createDir(profileDir)
  var fs = openFileStream(profileDir / "metadata.owl", fmWrite)
  defer: fs.close()
  profile.write(fs)
