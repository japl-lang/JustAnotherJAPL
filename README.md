# NimVM
A basic programming language written in Nim

## Project structure

The project is split into several directories and submodules to ease human inspection:
- `README.md` -> This file here (lol)
- `docs` -> Contains markdown files with the various specifications for NimVM (bytecode, grammar, etc)
    - `docs/bytecode.md` -> Lays out the bytecode specification for NimVM as well as serialization guidelines
    - `docs/grammar.md` -> Formal grammar specification in EBNF syntax
- `src` -> Contains source files
    - `src/main.nim` -> This is the main executable for NimVM (REPL, run files, etc.)
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

