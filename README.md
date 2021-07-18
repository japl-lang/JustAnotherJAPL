# NimVM
A basic programming language written in Nim

## Project structure

The project is split into several directories and submodules to ease human inspection:
- `README.md` -> This file here (lol)
- `docs` -> Contains markdown files with the various specifications for NimVM (bytecode, grammar, etc)
    - `docs/bytecode.md` -> Lays out the bytecode specification for NimVM as well as serialization guidelines
    - `docs/grammar.md` -> Formal grammar specification in EBNF syntax
- `src` -> Contains source files
    - `src/main.nim` -> This is the main executable for NimVM (REPL, run files, etc.), currently not in this repo
    - `src/backend` -> Contains the backend of the language (lexer, parser and compiler)
        - `src/backend/meta` -> Contains meta-structures that are used during parsing and compilation
        - `src/backend/lexer.nim` -> Contains the tokenizer
        - `src/backend/parser.nim` -> Contains the parser
        - `src/backend/compiler.nim` -> Contains the compiler
    - `src/frontend` -> Contains the language's frontend (runtime environment and type system)
        - `src/frontend/types` -> Contains the implementation of the type system
        - `src/frontend/vm.nim` -> Contains the virtual machine (stack-based)
    - `src/util` -> Contains generic utilities used troughout the project
    - `src/util/bytecode` -> Contains the bytecode serializer/deserializer
        - `src/util/bytecode/serializer.nim` -> Contains the bytecode serializer
        - `src/util/bytecode/deserializer.nim` -> Contains the bytecode deserializer
        - `src/util/bytecode/objects.nim` -> Contains object wrappers for bytecode opcodes
    - `src/util/debug.nim` -> Contains the debugger

## Language design

NimVM is a generic stack-based bytecode VM implementation, meaning that source files are compiled into an
imaginary instruction set for which we implemented all the required operations in a virtual machine. NimVM
uses a triple-pass compiler where the input is first tokenized, then parsed into an AST and finally optimized
before being translated to bytecode.

The compilation toolchain has been designed as follows:
- First, the input is tokenized. This process aims to break down the source input into a sequence of easier to
    process tokens for the next step. The lexer (or tokenizer) detects basic syntax errors like unterminated
    string literals and multi-line comments and invalid usage of unknown tokens (for example UTF-8 runes)
- Then, the tokens are fed into a parser. The parser recursively traverses the list of tokens coming from the lexer
  and builds a higher-level structure called an Abstract Syntax Tree-- or AST for short-- and also catches the rest of
  static or syntax errors such as illegal statement usage (for example return outside a function), malformed expressions
  and declarations and much more
- After the AST has been built, it goes trough the optimizer. As the name suggests, this step aims to perform a few optimizations,
  namely:
  - constant folding (meaning 1 + 2 will be replaced with 3 instead of producing 2 constant opcodes and 1 addition opcode)
  - global name resolution. This is possible because NimVM's syntax only allows for globals to be defined in a way that
    is statically inferrable, so "name error" exceptions can be caught before any code is even ran.
  The optimizer also detects attempts to modify a constant's or a let's value at compile-time.
- Once the optimizater is done, the compiler takes the AST and compiles it to bytecode for it to be later interpreted
  by our virtual machine implementation

