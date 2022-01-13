import std/[strformat, strutils, os, osproc, httpclient, terminal, strscans]
import commandant

type
  SubCommand = enum
    Create, Init, Build, Err
  MsgType = enum
    Error, Info, Verifying, Success, Building


proc printMessage(subcommand: SubCommand, msgType: MsgType, msg: string) =
  ## prints a colourful message to the console, `Success` and Error` are handled
  ## differently. `Error` will also terminate the program.
  
  const p1 = "Pico-Nim: "
  if msgType == Success:
    echo ansiForegroundColorCode(fgBlue), ansiStyleCode(styleBright), p1, 
      ansiForegroundColorCode(fgCyan), $subcommand, ": ", 
      ansiForegroundColorCode(fgGreen), $msgType, ": ",
      ansiForegroundColorCode(fgWhite), msg, ansiResetCode
  elif msgType == Error:
    echo ansiForegroundColorCode(fgBlue), ansiStyleCode(styleBright), p1, 
      ansiForegroundColorCode(fgCyan), $subcommand, ": ", 
      ansiForegroundColorCode(fgRed), $msgType, ": ",
      ansiForegroundColorCode(fgWhite), msg, ansiResetCode
    quit 1
  else:
    echo ansiForegroundColorCode(fgBlue), ansiStyleCode(styleBright), p1, 
      ansiForegroundColorCode(fgCyan), $subcommand, ": ", 
      ansiForegroundColorCode(fgYellow), $msgType, ": ",
      ansiForegroundColorCode(fgWhite), msg, ansiResetCode


proc createProject(projectPath: string, overwrite: bool) =
  ## Creates a nim pico project by copying the picostdlib template folder.

  const startMsg = "Create raspberry pi pico projects using Nim!"
  printMessage(Create, Info, startMsg)

  # check if name is valid filename
  printMessage(Create, Verifying, "Project Name")
  if not projectPath.isValidFilename():
    printMessage(Create, Error, fmt"provided --name argument will not work as filename: {projectPath}")

  # check if the name already has a directory with the same name
  if dirExists(joinPath(getCurrentDir(), projectPath)) and overwrite == false:
    printMessage(Create, Error, fmt"provided project name ({projectPath}) already has directory, use --overwrite if you wish to replace contents")

  # copy the template over to the current directory
  printMessage(Create, Info, "Copying template from `picostdlib`.")
  let
    sourcePath = joinPath(getAppDir(), "template")
    name = projectPath.splitPath.tail
  discard existsOrCreateDir(projectPath)
  try: copyDir(sourcePath, projectPath)
  except OSError: printMessage(Create, Error, "Could not copy template folder.")
  
  # rename nim file
  printMessage(Create, Info, "Renaming files to project name.")
  try:
    moveFile(projectPath / "src/blink.nim", projectPath / fmt"src/{name}.nim")
    moveFile(projectPath / "template.nimble", projectPath /
        fmt"{name}.nimble")
  except OSError:
    printMessage(Create, Error, "Could not rename `.nim` files.")

  # change all instances of template `blink` to the project name
  printMessage(Create, Info, "Rewriting `csource/CMakeLists.txt`.")
  let cmakelists = (projectPath / "/csource/CMakeLists.txt")
  try:
    cmakelists.writeFile cmakelists.readFile.replace("blink", name) 
  except IOError: 
    printMessage(Create, Error, "Could not rewrite `csource/CMakeLists.txt`.")

  printMessage(Create, Success, " Project successfully created!")
 

proc initProject(sdk: string = "", nimbase: string = "") =
  ## Initialize the projects dependencies:
  ## 
  ## - sdk, if option is not provided a value, the sdk will be downloaded into
  ##   the project folder
  ## - nimbase, by default, tries to download the version of nimbase that 
  ##   matches the users nim version
  ## 
  ## If you have moved your pico-sdk folder or updated/changed your nim compiler
  ## version, then you should rerun `piconim init`.
  
  proc getActiveNimVersion: string =
    ## Get the active nim version from the terminal.
    
    let res = execProcess("nim -v")
    if not res.scanf("Nim Compiler Version $+[", result):
      result = NimVersion
    result.removeSuffix(' ')

  proc downloadNimbase(path: string): bool =
    ## Attempts to download the nimbase file from the Nim-Lang github repo
    ## and if it fails returns false.

    let
      nimVer = getActiveNimVersion()
      downloadPath = fmt"https://raw.githubusercontent.com/nim-lang/Nim/v{nimVer}/lib/nimbase.h"
    try:
      let client = newHttpClient()
      client.downloadFile(downloadPath, path)
      result = true
    except: echo getCurrentExceptionMsg()

  const startMsg = "Initializing project sdk and nimbase path"
  printMessage(Init, Info, startMsg)

  let projectPath = getCurrentDir()
  
  if sdk != "":
    printMessage(Init, Verifying, "Provided --sdk option.")
    # check if the sdk option path exists and has the appropriate cmake file (very basic check...)
    if not sdk.dirExists():
      printMessage(Init, Error, fmt"could not find an existing directory with the provided --sdk argument : {sdk}")

    if not fileExists(fmt"{sdk}/pico_sdk_init.cmake"):
      printMessage(Init, Error, fmt"directory provided with --sdk argument does not appear to be a valid pico-sdk library: {sdk}")

  if nimbase != "":
    printMessage(Init, Verifying, "Provided --nimbase option.")
    if not nimbase.fileExists():
      printMessage(Init, Error, fmt"could not find an existing `nimbase.h` file using provided --nimbase argument : {nimbase}")

    let (_, name, ext) = nimbase.splitFile()
    if name != "nimbase" or ext != ".h":
      printMessage(Init, Error, fmt"invalid filename or extension (expecting `nimbase.h`, recieved `{name}{ext}`")

  # get nimbase.h file from github
  if nimbase == "":
    let nimVer = getActiveNimVersion()
    printMessage(Init, Verifying, fmt"Nimbase dependency on https://raw.githubusercontent.com/nim-lang/Nim/v{nimVer}/lib/nimbase.h")
    let nimbaseError = downloadNimbase(projectPath / "csource/nimbase.h")
    if not nimbaseError:
      printMessage(Init, Error, fmt"failed to download `nimbase.h` from nim-lang repository, use --nimbase:<path> to specify a local file")
  else:
    try:
      copyFile(nimbase, (projectPath / "csource/nimbase.h"))
    except OSError:
      printMessage(Init, Error, "failed to copy provided nimbase.h file")

  printMessage(Init, Info, "Running `cmake`")
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
    printMessage(Init, Error, fmt"cmake exited with error code: {cmakeExit}")
  
  printMessage(Init, Success, " Project successfully initialized!")


proc buildProject(program: string, output = "") =
  ## Build the `.uf2` file via the main program specified as an argument
  # TODO - support user-defined output dirs

  type
    LinkableLib = enum
      stdio = "pico_stdlib"
      multicore = "pico_multicore"
      adc = "hardware_adc"
      pio = "hardware_pio"
      dma = "hardware_dma"
      i2c = "hardware_i2c"
      rtc = "hardware_rtc"
      uart = "hardware_uart"
      spi = "hardware_spi"
      clock = "hardware_clocks"
      reset = "hardware_resets"
      flash = "hardware_flash"
      pwm = "hardware_pwm"
      interp = "hardware_interp"

  proc getLinkedLib(fileName: string): set[LinkableLib] =
    ## Iterates over lines searching for includes adding to result
    
    let file = open(fileName)
    for line in file.lines:
      if not line.startsWith("typedef"):
        var incld = ""
        if line.scanf("""#include "$+.""", incld) or line.scanf("""#include <$+.""", incld):
          let incld = incld.replace('/', '_')
          try:
            result.incl parseEnum[LinkableLib](incld)
          except: discard
      else:
        break
    close file


  proc addLinkLibs(program: string) =
    ## add the library links to the `pico_libraries.cmake` file, which will be 
    ## included in the `CMakeLists.txt file before `make` is run in the `build`
    ## subcommand.

    discard tryRemoveFile("csource/pico_nim_import.cmake.tmp")
    const
      inFile = "csource/pico_nim_import.cmake"
      outFile = "csource/pico_nim_import.cmake.tmp"
      startLn = "target_link_libraries(${CMAKE_PROJECT_NAME} "

    var libs: set[LinkableLib]
    for kind, path in walkDir("csource/build/nimcache"):
      if kind == pcFile and path.endsWith(".c"):
        libs.incl getLinkedLib(path)


    var f = open(outFile, fmWrite)
    for lib in libs:
      f.writeLine(startLn & $lib & ")")
    
    moveFile(outFile, inFile)
    discard tryRemoveFile("csource/pico_nim_import.cmake.tmp")


  printMessage(Build, Info, "Building `.uf2` file using `make`.")
  
  # validate build inputs 
  printMessage(Build, Verifying, "Provided program argument")
  if not program.endsWith(".nim"):
    printMessage(Build, Error, fmt"Provided main program argument is not a nim file: {program}")
  if not fileExists(fmt"src/{program}"):
    printMessage(Build, Error, fmt"Provided main program argument does not exist: {program}")
  
  if output != "":
    printMessage(Build, Verifying, "Provided program --output option")
    if not dirExists(output):
      printMessage(Build, Error, fmt"Provided output option is not a valid directory: {output}")

  # remove previous builds
  printMessage(Build, Info, "Removing previous builds.")
  let nimcache = "csource" / "build" / "nimcache"
  try:
    for kind, file in walkDir(nimcache):
      if kind == pcFile and file.endsWith(".c"):
        removeFile(file)
  except OSError:
    printMessage(Build, Error, "Unable to remove previous builds.")

  # compile the nim program to .c file
  printMessage(Build, Info, "Compiling Nim files to `c` files, placing in nimcache.")
  let compileError = execCmd(fmt"nim c -c --nimcache:{nimcache} --gc:arc --cpu:arm --os:any -d:release -d:useMalloc ./src/{program}")
  if not compileError == 0:
    printMessage(Build, Error, fmt"Unable to compile the provided nim program: {program}")

  # rename the .c file
  printMessage(Build, Info, "Renaming nimcache files.")
  try:
    moveFile((nimcache / fmt"@m{program}.c"), (nimcache / fmt"""{program.replace(".nim")}.c"""))
  except OSError:
    printMessage(Build, Error, "Unable to rename nimcache files.")

  # add library links to cmake
  printMessage(Build, Info, "Checking pico-sdk imports, adding library links.")
  addLinkLibs(program)

  # update file timestamps
  printMessage(Build, Info, "Updating file timestamps.")
  when not defined(windows):
    let touchError1 = execCmd("touch csource/CMakeLists.txt")
    let touchError2 = execCmd("touch csource/pico_nim_import.cmake")
    if touchError1 == 1 or touchError2 == 1:
      printMessage(Build, Error, "Unable to update file timestamps")
  when defined(windows):
    let copyError = execCmd("copy /b csource/CMakeLists.txt +,,")
    let copyError = execCmd("copy /b csource/pico_nim_import.cmake +,,")
    if copyError1 == 1 or copyError2 == 1:
      printMessage(Build, Error, "Unable to update file timestamps")
  
  # run make
  printMessage(Build, Info, "Building via `make`")
  let makeError = execCmd("make -C csource/build")
  if makeError != 0:
    printMessage(Build, Error, fmt"make exited with error code: {makeError}")

  printMessage(Build, Success, "Project successfully built!")
  printMessage(Build, Info, fmt"""csource/build/{program.replace(".nim")}.uf2 can be copied to your pico.""")

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

  if create:
    createProject(name, overwriteTemplate)
  elif init:
    initProject(sdk, nimbase)
  elif build:
    buildProject(mainProgram, output)
  else:
    printMessage(Err, Error, "invalid subcommand")

