import commandant
import std/[strformat, strutils, os, osproc, httpclient, terminal, strscans, streams]
import picostdlib/private/linkutils

proc printError(msg: string) =
  echo ansiForegroundColorCode(fgRed), msg, ansiResetCode
  quit 1 # Should not be using this but short lived program


proc addLinkLibs(program: string) =
  discard tryRemoveFile("csource/CMakeLists.txt.tmp")
  const
    inFile = "csource/CMakeLists.txt"
    outFile = "csource/CMakeLists.txt.tmp"
  let
    inBuffer = newFileStream(inFile)
    outBuffer = newFileStream(outFile, fmWrite)
  
  var
    inLinkLib = false
    isLinkLine = false
    projName = ""

  for line in inbuffer.lines:
    if line.startsWith("target_link_libraries"):
      discard line.scanf("target_link_libraries($+ ", projName)
      inLinkLib = true
      isLinkLine = true
    else:
      if inLinkLib: # we're inside the `target_link_library` scope
        if line.contains(")"): # We're at either a new call or end of `target_link_library`
          outBuffer.write("target_link_libraries(")
          outBuffer.write(projName)
          outBuffer.write "\n"
          outBuffer.write(readFile("src" / LibFileName))
          outBuffer.writeLine(")")
          if not isLinkLine and line != ")":
            # Only write line if not `)` and not on same line as target link
            outbuffer.writeLine(line)
          inLinkLib = false
      else:
        outBuffer.writeLine(line)
    isLinkLine = false


  inBuffer.close()
  outBuffer.close()

  moveFile(outFile, inFile)
  discard tryRemoveFile("src" / LibFileName)


proc createProject(projectPath: string, overwrite: bool) =

  # check if name is valid filename
  if not projectPath.isValidFilename():
    printError(fmt"provided --name argument will not work as filename: {projectPath}")

  # check if the name already has a directory with the same name
  if dirExists(joinPath(getCurrentDir(), projectPath)) and overwrite == false:
    printError(fmt"provided project name ({projectPath}) already has directory, use --overwrite if you wish to replace contents")

  # copy the template over to the current directory
  let
    sourcePath = joinPath(getAppDir(), "template")
    name = projectPath.splitPath.tail
  discard existsOrCreateDir(projectPath)
  copyDir(sourcePath, projectPath)
  # rename nim file
  moveFile(projectPath / "src/blink.nim", projectPath / fmt"src/{name}.nim")
  moveFile(projectPath / "template.nimble", projectPath /
      fmt"{name}.nimble")

  # change all instances of template `blink` to the project name
  let cmakelists = (projectPath / "/csource/CMakeLists.txt")
  cmakelists.writeFile cmakelists.readFile.replace("blink", name)   


proc initProject(sdk: string = "", nimbase: string = "") =

  proc getActiveNimVersion: string =
    let res = execProcess("nim -v")
    if not res.scanf("Nim Compiler Version $+[", result):
      result = NimVersion
    result.removeSuffix(' ')

  proc downloadNimbase(path: string): bool =
    ## Attempts to download the nimbase if it fails returns false
    let
      nimVer = getActiveNimVersion()
      downloadPath = fmt"https://raw.githubusercontent.com/nim-lang/Nim/v{nimVer}/lib/nimbase.h"
    try:
      let client = newHttpClient()
      client.downloadFile(downloadPath, path)
      result = true
    except: echo getCurrentExceptionMsg()


  let projectPath = getCurrentDir()
  
  if sdk != "":
    # check if the sdk option path exists and has the appropriate cmake file (very basic check...)
    if not sdk.dirExists():
      printError(fmt"could not find an existing directory with the provided --sdk argument : {sdk}")

    if not fileExists(fmt"{sdk}/pico_sdk_init.cmake"):
      printError(fmt"directory provided with --sdk argument does not appear to be a valid pico-sdk library: {sdk}")

  if nimbase != "":
    if not nimbase.fileExists():
      printError(fmt"could not find an existing `nimbase.h` file using provided --nimbase argument : {nimbase}")

    let (_, name, ext) = nimbase.splitFile()
    if name != "nimbase" or ext != ".h":
      printError(fmt"invalid filename or extension (expecting `nimbase.h`, recieved `{name}{ext}`")

  # get nimbase.h file from github
  if nimbase == "":
    let nimbaseError = downloadNimbase(projectPath / "csource/nimbase.h")
    if not nimbaseError:
      printError(fmt"failed to download `nimbase.h` from nim-lang repository, use --nimbase:<path> to specify a local file")
  else:
    try:
      copyFile(nimbase, (projectPath / "csource/nimbase.h"))
    except OSError:
      printError"failed to copy provided nimbase.h file"


  var cmakeArgs: seq[string]
  if sdk != "":
    cmakeArgs.add fmt"-DPICO_SDK_PATH={sdk}"
  else:
    cmakeArgs.add "-DPICO_SDK_FETCH_FROM_GIT=on"
  cmakeArgs.add ".."

  let buildDir = projectPath / "csource/build"
  discard existsOrCreateDir(buildDir)

  let cmakeProc = startProcess(
    "cmake",
    args=cmakeArgs,
    workingDir=buildDir,
    options={poEchoCmd, poUsePath, poParentStreams}
  )
  let cmakeExit = cmakeProc.waitForExit()
  if cmakeExit != 0:
    printError(fmt"cmake exited with error code: {cmakeExit}")


proc buildProject(program: string, output = "") =

  #validate build inputs 
  if not program.endsWith(".nim"):
    printError(fmt"provided main program argument is not a nim file: {program}")
  if not fileExists(fmt"src/{program}"):
    printError(fmt"provided main program argument does not exist: {program}")
  if output != "":
    if not dirExists(output):
      printError(fmt"provided output option is not a valid directory: {output}")

  let nimcache = "csource" / "build" / "nimcache"
  # remove previous builds
  for kind, file in walkDir(nimcache):
    if kind == pcFile and file.endsWith(".c"):
      removeFile(file)

  # compile the nim program to .c file
  let compileError = execCmd(fmt"nim c -c --nimcache:{nimcache} --gc:arc --cpu:arm --os:any -d:release -d:useMalloc ./src/{program}")
  if not compileError == 0:
    printError(fmt"unable to compile the provided nim program: {program}")

  # rename the .c file
  moveFile((nimcache / fmt"@m{program}.c"), (nimcache / fmt"""{program.replace(".nim")}.c"""))

  # update file timestamps
  addLinkLibs(program)
  when not defined(windows):
    let touchError = execCmd("touch csource/CMakeLists.txt")
  when defined(windows):
    let copyError = execCmd("copy /b csource/CMakeLists.txt +,,")
  # run make
  let makeError = execCmd("make -C csource/build")



# --- MAIN PROGRAM ---
when isMainModule:
  commandline:
    subcommand(create, "create", "c"):
      argument(name, string)
      flag(overwriteTemplate, "overwrite", "O")
    subcommand(init, "init", "i"):
      option(sdk, string, "sdk", "s")
      option(nimbase, string, "nimbase", "n")

    subcommand(build, "build", "b"):
      argument(mainProgram, string)
      option(output, string, "output", "o")

  echo "pico-nim : create raspberry pi pico projects using Nim"

  if create:
    createProject(name, overwriteTemplate)
  elif init:
    initProject(sdk, nimbase)
  elif build:
    buildProject(mainProgram, output)
  else:
    printError("invalid subcommand")

