# Raspberry Pi Pico SDK for Nim

This library provides the library and build system necessary to write programs for RP2040 based devices (such as the Raspberry Pi Pico) in the [Nim](https://nim-lang.org/) programming language

The libary provides wrappers for the original [Raspberry Pi Pico SDK](https://github.com/raspberrypi/pico-sdk). Currently, standard library features such as GPIO are supported. Libraries such as TinyUSB are in development.

## Table of Contents

[Setup](##Setup)

[Building](##Building)

[Examples](examples)

[Contributing](##Contributing)

[License](LICENSE)

## Setup

**The following steps will install piconim and create a new project**

1. First, you will need to have the Nim compiler installed. If you don't already 
have it, consider using [choosenim](https://github.com/dom96/choosenim)

2. Since this is just a wrapper for the original 
[pico-sdk](https://github.com/raspberrypi/pico-sdk), you will need to install the C 
library [dependencies](https://github.com/raspberrypi/pico-sdk#quick-start-your-own-project) 
(Step 1 in the quick start section). On raspbian/debian/ubuntu, you may install by:

    ```bash
    sudo apt install cmake gcc-arm-none-eabi libnewlib-arm-none-eabi build-essential libstdc++-arm-none-eabi-newlib
    ```

3. Install `picostdlib`:

    ```bash
    nimble install https://github.com/beef331/picostdlib
    ```

4. Create a nim pico project from a template:

    ```bash
    piconim create <project-name>
    ```
    
    to create a new project directory from a template. This will create a new folder, so make 
    sure you are in the parent folder. Use the `--overwrite` flag if you wish to overwrite 
    and existing folder

5. change into the project directory and run `piconim init`

    ```bash
    cd <project-name>
    ```
    
    ```bash
    piconim init ...
    ```
    
    (`...`) indicates you can provide options to the subcommand, such as:
    
    - (--sdk, -s) -> specify the path to a locally installed `pico-sdk` repository, 
        ex.  `--sdk:/home/casey/pico-sdk`
    - (--nimbase, -n) -> similarly, you can provide the path to a locally installed 
        `nimbase.h` file. Otherwise, the program attempts to download the file from
        the nim-lang github repository. ex. `-n:/path/to/nimbase.h`
        
     If you have moved your pico-sdk folder or updated/changed your nim compiler version, 
     then you should rerun `piconim init`

The project is now ready. you can edit the file `src/<project-name>.nim` to your liking. follow 
the next steps to build the `.uf2` that will be copied over to your pico

## Building

Now you can work on your project. When you are ready to build the `.uf2` file 
(which will be copied to the Raspberry Pi Pico), you can use the `build` subcommand:

```bash
piconim build <main-program>
```

Where `<main-program>` is the main module in your `src` folder. (ex. `myProject.nim`). 
You can also specify an output directory, otherwise it will be placed in `csource/builds`



## Contributing

Please contribute.
