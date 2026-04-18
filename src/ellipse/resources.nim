import std/[tables, typetraits]

type
  AbstractResourceBuffer* = ref object of RootObj
  ResourceBuffer*[T] = ref object of AbstractResourceBuffer
    data: Table[string, T]    

  Resources* = object
    buffers: Table[string, AbstractResourceBuffer]

proc add*[T](resources: var Resources, id: string, res: sink T) =
  let tn = name(T)
  if not resources.buffers.hasKey(tn):
    resources.buffers[tn] = AbstractResourceBuffer(ResourceBuffer[T]())
  var buff = cast[ResourceBuffer[T]](resources.buffers[tn])
  buff.data[id] = res

proc get*[T](resources: Resources, _: typedesc[T], id: string): lent T =
  let tn = name(T)
  if not resources.buffers.hasKey(tn):
    raise CatchableError.newException("Unknown resource type: " & tn)
  var buff = cast[ResourceBuffer[T]](resources.buffers[tn])
  result = buff.data[id]
