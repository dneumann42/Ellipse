when defined(windows):
  proc c_aligned_malloc(size, alignment: csize_t): pointer
    {.importc: "_aligned_malloc", header: "<malloc.h>".}

  proc c_aligned_free(mem: pointer)
    {.importc: "_aligned_free", header: "<malloc.h>".}

else:
  proc posix_memalign(memptr: ptr pointer; alignment, size: csize_t): cint
    {.importc: "posix_memalign", header: "<stdlib.h>".}

  proc c_free(mem: pointer)
    {.importc: "free", header: "<stdlib.h>".}

proc allocAligned*(size, alignment: int): pointer =
  doAssert size >= 0
  doAssert alignment > 0
  doAssert (alignment and (alignment - 1)) == 0,
    "alignment must be a power of two"

  when defined(windows):
    result = c_aligned_malloc(csize_t(size), csize_t(alignment))
    if result == nil:
      raise newException(OutOfMemDefect, "aligned allocation failed")

  else:
    var p: pointer = nil

    # POSIX requires alignment to be:
    # - power of two
    # - multiple of sizeof(pointer)
    let minAlign = sizeof(pointer)
    let realAlign = max(alignment, minAlign)

    let rc = posix_memalign(addr p, csize_t(realAlign), csize_t(size))
    if rc != 0:
      raise newException(OutOfMemDefect, "aligned allocation failed")

    result = p


proc deallocAligned*(p: pointer) =
  if p == nil:
    return

  when defined(windows):
    c_aligned_free(p)
  else:
    c_free(p)