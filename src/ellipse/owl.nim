# API around the owl programming language (development name crow)

import std/streams

import pkg/owl as owl
export owl

proc toOwl*(n: SomeNumber): Value =
  result = owl.number(float64(when n is SomeInteger: n.toFloat() else: n))

proc fromOwl*(v: Value, n: var SomeNumber) =
  assert(v.kind == Number)
  when n is SomeInteger:
    n = v.number.toString()
  else:
    n = v.number

proc readOwl*(stream: Stream, filename: string): owl.Value =
  var evaluator = Evaluator.init()
  evaluator.exec(owl.parse(stream.readAll(), filename))

when isMainModule:
  var
    f: float64
  toOwl(3.1415926).fromOwl(f)
  echo f

