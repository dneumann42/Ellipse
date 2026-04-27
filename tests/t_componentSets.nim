import unittest
import std/hashes

import ellipse/entities/componentSets

suite "ComponentSet":
  test "init is empty":
    var s: ComponentSet
    check s.ids.len == 0

  test "hash of empty set":
    var s: ComponentSet
    let h = hash(s)
    check h is Hash

  test "hash consistent for same set":
    var s: ComponentSet
    s.incl(ComponentTypeId(1))
    s.incl(ComponentTypeId(5))
    check hash(s) == hash(s)

  test "contains on empty":
    var s: ComponentSet
    check not s.contains(ComponentTypeId(0))
    check not s.contains(ComponentTypeId(100))

  test "contains after incl":
    var s: ComponentSet
    s.incl(ComponentTypeId(3))
    check s.contains(ComponentTypeId(3))
    check not s.contains(ComponentTypeId(4))

  test "contains boundary values word 0":
    var s: ComponentSet
    s.incl(ComponentTypeId(0))
    s.incl(ComponentTypeId(63))
    check s.contains(ComponentTypeId(0))
    check s.contains(ComponentTypeId(63))
    check not s.contains(ComponentTypeId(1))

  test "contains boundary values word 1":
    var s: ComponentSet
    s.incl(ComponentTypeId(64))
    s.incl(ComponentTypeId(127))
    check s.contains(ComponentTypeId(64))
    check s.contains(ComponentTypeId(127))
    check not s.contains(ComponentTypeId(65))

  test "contains boundary values word 2":
    var s: ComponentSet
    s.incl(ComponentTypeId(128))
    s.incl(ComponentTypeId(191))
    check s.contains(ComponentTypeId(128))
    check s.contains(ComponentTypeId(191))

  test "contains boundary values word 3":
    var s: ComponentSet
    s.incl(ComponentTypeId(192))
    s.incl(ComponentTypeId(255))
    check s.contains(ComponentTypeId(192))
    check s.contains(ComponentTypeId(255))

  test "incl idempotent":
    var s: ComponentSet
    s.incl(ComponentTypeId(10))
    s.incl(ComponentTypeId(10))
    check s.contains(ComponentTypeId(10))
    check s.ids.len == 1

  test "incl multiple":
    var s: ComponentSet
    s.incl(ComponentTypeId(1))
    s.incl(ComponentTypeId(50))
    s.incl(ComponentTypeId(200))
    check s.contains(ComponentTypeId(1))
    check s.contains(ComponentTypeId(50))
    check s.contains(ComponentTypeId(200))

  test "excl basic":
    var s: ComponentSet
    s.incl(ComponentTypeId(5))
    s.excl(ComponentTypeId(5))
    check not s.contains(ComponentTypeId(5))

  test "excl no-op":
    var s: ComponentSet
    s.excl(ComponentTypeId(10))
    check not s.contains(ComponentTypeId(10))
    check s.ids.len == 0

  test "excl preserves others":
    var s: ComponentSet
    s.incl(ComponentTypeId(1))
    s.incl(ComponentTypeId(2))
    s.excl(ComponentTypeId(1))
    check not s.contains(ComponentTypeId(1))
    check s.contains(ComponentTypeId(2))

  test "with returns new set":
    var s: ComponentSet
    s.incl(ComponentTypeId(1))
    let s2 = s.with(ComponentTypeId(2))
    check s.contains(ComponentTypeId(1))
    check not s.contains(ComponentTypeId(2))
    check s2.contains(ComponentTypeId(1))
    check s2.contains(ComponentTypeId(2))

  test "with idempotent":
    var s: ComponentSet
    s.incl(ComponentTypeId(5))
    let s2 = s.with(ComponentTypeId(5))
    check s2.contains(ComponentTypeId(5))
    check s2.ids.len == 1

  test "without returns new set":
    var s: ComponentSet
    s.incl(ComponentTypeId(1))
    s.incl(ComponentTypeId(2))
    let s2 = s.without(ComponentTypeId(1))
    check s.contains(ComponentTypeId(1))
    check s2.contains(ComponentTypeId(2))
    check not s2.contains(ComponentTypeId(1))

  test "without no-op":
    var s: ComponentSet
    s.incl(ComponentTypeId(1))
    let s2 = s.without(ComponentTypeId(5))
    check s2.contains(ComponentTypeId(1))
    check s2.ids.len == 1

  test "isSubsetOf empty":
    var a, b: ComponentSet
    check a.isSubsetOf(b)
    b.incl(ComponentTypeId(1))
    check a.isSubsetOf(b)  # empty ⊆ {1}
    check not b.isSubsetOf(a)  # {1} ⊈ empty

  test "isSubsetOf self":
    var s: ComponentSet
    s.incl(ComponentTypeId(1))
    s.incl(ComponentTypeId(2))
    check s.isSubsetOf(s)

  test "isSubsetOf proper":
    var a, b: ComponentSet
    a.incl(ComponentTypeId(1))
    b.incl(ComponentTypeId(1))
    b.incl(ComponentTypeId(2))
    check a.isSubsetOf(b)
    check not b.isSubsetOf(a)

  test "isSubsetOf false":
    var a, b: ComponentSet
    a.incl(ComponentTypeId(1))
    b.incl(ComponentTypeId(2))
    check not a.isSubsetOf(b)

  test "isSubsetOf across words":
    var a, b: ComponentSet
    a.incl(ComponentTypeId(5))
    a.incl(ComponentTypeId(70))
    b.incl(ComponentTypeId(5))
    b.incl(ComponentTypeId(70))
    b.incl(ComponentTypeId(200))
    check a.isSubsetOf(b)

  test "intersects empty":
    var a, b: ComponentSet
    check not a.intersects(b)

  test "intersects self non-empty":
    var s: ComponentSet
    s.incl(ComponentTypeId(1))
    check s.intersects(s)

  test "intersects positive":
    var a, b: ComponentSet
    a.incl(ComponentTypeId(1))
    b.incl(ComponentTypeId(1))
    b.incl(ComponentTypeId(2))
    check a.intersects(b)
    check b.intersects(a)

  test "intersects negative":
    var a, b: ComponentSet
    a.incl(ComponentTypeId(1))
    b.incl(ComponentTypeId(2))
    check not a.intersects(b)

  test "intersects across words":
    var a, b: ComponentSet
    a.incl(ComponentTypeId(5))
    a.incl(ComponentTypeId(100))
    b.incl(ComponentTypeId(100))
    b.incl(ComponentTypeId(200))
    check a.intersects(b)

  test "intersects no overlap across words":
    var a, b: ComponentSet
    a.incl(ComponentTypeId(5))
    b.incl(ComponentTypeId(70))
    check not a.intersects(b)

  test "ids empty":
    var s: ComponentSet
    let empty: seq[ComponentTypeId] = @[]
    check s.ids == empty

  test "ids single":
    var s: ComponentSet
    s.incl(ComponentTypeId(42))
    check s.ids == @[ComponentTypeId(42)]

  test "ids multiple sorted":
    var s: ComponentSet
    s.incl(ComponentTypeId(10))
    s.incl(ComponentTypeId(5))
    s.incl(ComponentTypeId(20))
    check s.ids == @[ComponentTypeId(5), ComponentTypeId(10), ComponentTypeId(20)]

  test "ids across words":
    var s: ComponentSet
    s.incl(ComponentTypeId(5))
    s.incl(ComponentTypeId(70))
    s.incl(ComponentTypeId(200))
    let ids = s.ids
    check ids.len == 3
    check ComponentTypeId(5) in ids
    check ComponentTypeId(70) in ids
    check ComponentTypeId(200) in ids

  test "ids returns increasing order":
    var s: ComponentSet
    s.incl(ComponentTypeId(200))
    s.incl(ComponentTypeId(5))
    s.incl(ComponentTypeId(70))
    s.incl(ComponentTypeId(0))
    let ids = s.ids
    check ids == @[ComponentTypeId(0), ComponentTypeId(5), ComponentTypeId(70), ComponentTypeId(200)]

  test "full workflow":
    var s: ComponentSet
    s.incl(ComponentTypeId(1))
    s.incl(ComponentTypeId(2))
    s.incl(ComponentTypeId(3))
    check s.contains(ComponentTypeId(1))
    check s.contains(ComponentTypeId(2))
    check s.contains(ComponentTypeId(3))
    s.excl(ComponentTypeId(2))
    check not s.contains(ComponentTypeId(2))
    check s.contains(ComponentTypeId(1))
    check s.contains(ComponentTypeId(3))
    let s2 = s.with(ComponentTypeId(4))
    check s2.contains(ComponentTypeId(4))
    check not s.contains(ComponentTypeId(4))
    check s.isSubsetOf(s2)
    check s2.intersects(s)