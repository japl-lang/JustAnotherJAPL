# NimVM - A stack-based bytecode virtual machine written in Nim
A basic programming language written in Nim

## Project structure

The project is split into several directories and submodules:
- `build.py` -> The build script (TODO, not pushed yet)
- `docs` -> Contains markdown files with the various specifications for NimVM (bytecode, grammar, etc)
- `src` -> Contains source files
  - `src/backend` -> Contains the backend of the language such as the parser, compiler and optimizer
    - `src/meta` -> Contains meta-structures used during compilation and parsing
  - `src/frontend` -> Contains the runtime environment of NimVM
    - `src/frontend/types` -> Contains the type system
  - `src/memory` -> Contains NimVM's allocator and memory manager



## Language design

NimVM is a generic stack-based bytecode VM implementation, meaning that source files are compiled into an
imaginary instruction set for which all required operations are implemented in a virtual machine. NimVM
uses a triple-pass compiler where the input is first tokenized and parsed into an AST, then optimized and
eventually translated to bytecode.

The compilation toolchain has been designed as follows:
- First, the input is tokenized. This process aims to break down the source input into a sequence of easier to
    process tokens for the next step. The lexer (or tokenizer) detects basic syntax errors like unterminated
    string literals and invalid usage of unknown tokens (for example UTF-8 runes)
- Then, the tokens are fed into a parser. The parser recursively traverses the list of tokens coming from the lexer
  and builds a higher-level structure called an Abstract Syntax Tree-- or AST for short-- and also catches the rest of
  static or syntax errors such as illegal statement usage (for example return outside a function), malformed expressions
  and declarations and much more
- After the AST has been built, it goes trough the optimizer. As the name suggests, this step aims to perform a few optimizations,
  namely:
  - constant folding (meaning 1 + 2 will be replaced with 3 instead of producing 2 constant opcodes and 1 addition opcode)
  - global name resolution. This is possible because NimVM's syntax only allows for globals to be defined in a way that
    is statically inferrable, so "name error" exceptions can be caught before any code is even ran.
  - throw warnings for things like unreachable code after return statements (optional).

    The optimization step is entirely optional and enabled by default
- Once the optimizater is done, the compiler takes the AST and compiles it to bytecode for it to be later interpreted
  by our virtual machine implementation


## Language syntax

NimVM uses a syntax mostly inspired from C and Java, although some influences come from Python as well.

## Credits

NimVM was inspired by Bob Nystrom's amazing [Crafting Interpreters](https://craftinginterpreters.com) book
