import std/[strformat, macros]
const LibFileName* = "linkedLibs.pnim"
template linkLibrary*(lib: static string) =
  ## Used for automatically linking libraries on module import.
  
  # The following is a hack due to not being able to use `std/os` as it's not ported
  # and will not be ported.
  static:
    const
      projPath {.inject.} = getProjectPath()
      name {.inject.} = lib
      op = fmt"""'
import std/[os, strutils]
let path = "{projPath}" / "{LibFileName}"
if fileExists(path):
  var file = readFile(path)
  block add:
    for x in file.splitLines(true):
      if x.startsWith("{name}"):
        break add
    file.add "{name}\n"
    writeFile(path, file)
else:
  writeFile(path, "{name}" & "\n")'
"""
    discard staticexec("nim --verbosity:0 --eval:" & op)
