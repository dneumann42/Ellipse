import std/[hashes]

type
  ComponentTypeId* = distinct uint16
  ComponentSet* = object
    words: array[4, uint64]

const CacheLine* = 64

proc `==`*(a, b: ComponentTypeId): bool {.borrow.}

proc hash*(s: ComponentSet): Hash =
  var h: Hash = 0
  for w in s.words:
    h = h !& hash(w)
  result = !$h

proc contains*(s: ComponentSet; id: ComponentTypeId): bool =
  let n = uint16(id).int
  let word = n div 64
  let bit = n mod 64
  (s.words[word] and (1'u64 shl bit)) != 0

proc incl*(s: var ComponentSet; id: ComponentTypeId) =
  let n = uint16(id).int
  let word = n div 64
  let bit = n mod 64
  s.words[word] = s.words[word] or (1'u64 shl bit)

proc excl*(s: var ComponentSet; id: ComponentTypeId) =
  let n = uint16(id).int
  let word = n div 64
  let bit = n mod 64
  s.words[word] = s.words[word] and not (1'u64 shl bit)

proc with*(s: ComponentSet; id: ComponentTypeId): ComponentSet =
  result = s
  result.incl(id)

proc without*(s: ComponentSet; id: ComponentTypeId): ComponentSet =
  result = s
  result.excl(id)

proc isSubsetOf*(a, b: ComponentSet): bool =
  ## True when every component in a is present in b.
  for i in 0 ..< a.words.len:
    if (a.words[i] and not b.words[i]) != 0:
      return false
  true

proc intersects*(a, b: ComponentSet): bool =
  for i in 0 ..< a.words.len:
    if (a.words[i] and b.words[i]) != 0:
      return true
  false

proc ids*(s: ComponentSet): seq[ComponentTypeId] =
  for wordIndex, word in s.words:
    var w = word
    var bit = 0
    while w != 0:
      if (w and 1) != 0:
        result.add ComponentTypeId(wordIndex * 64 + bit)
      w = w shr 1
      inc bit