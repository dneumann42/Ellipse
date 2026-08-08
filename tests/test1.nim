# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import std/[streams, times, unittest]

import ellipse/profiles

test "profile metadata round-trips through owl":
  let original = Profile(
    id: "profile-1",
    name: "Dana \"D\"",
    lastWritten: dateTime(2024, mJan, 2, 3, 4, 5, zone = utc())
  )
  let stream = newStringStream()

  original.write(stream)
  stream.setPosition(0)

  var loaded: Profile
  loaded.read(stream)

  check loaded.id == original.id
  check loaded.name == original.name
  check loaded.lastWritten == original.lastWritten
