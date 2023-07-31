## FakeBash

FakeBash is a basic shell that I wrote to learn Zig. The code sucks so avoid using as a reference for your project.

### Input handling
FakeBash handles input by setting your terminal in raw mode, which allows us to support escape keys and later arrow keys (as well as SHIFT-TAB and function keys), right now the shell only supports ascii.

### Compiling

#### Requirements
- git
- zig 0.11

#### Howto
- clone the repository: `git clone https://github.com/0x454d505459/fakeBash.git`
- cd into it `cd fakeBash`
- compile a debug binary `zig build-exe shell.zig` (I haven't set up a build script yet)

### Colors
Colors are comming, some day
