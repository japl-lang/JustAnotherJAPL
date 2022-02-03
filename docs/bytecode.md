# JAPL - Bytecode Serialization Standard

## Rationale
This document aims to lay down a simple, extensible and linear format for serializing and deserializing
compiled JAPL code to a file-like buffer.

Once a JAPL source file (i.e. one with a ".jpl" extension, without quotes) has been successfully compiled to bytecode, the compiler dumps the resulting linear stream of bytes to a ".japlc" file (without quotes, which stands for __JAPL C__ompiled), which we will call "object file" (without quotes) in this document. The name of the object file will be the same of the original source file, and its structure is rigorously described in this document.

The main reason to serialize bytecode to a file is for porting JAPL code to other machines, but also to avoid processing the same file every time if it hasn't changed, therefore using it as a sort of cache. If this cache-like behavior is abused though, it may lead to unexpected behavior, hence we define how the JAPL toolchain will deal with local object files. These object files are stored inside `~/.cache/japl` under *nix systems and `C:\Windows\Temp\japl` under Windows systems.

When JAPL finds an existing object file whose name matches the one of the source file that has to be ran (both filenames are stripped of their respective file extension), it will skip processing the source file and use the existing object file only and only if:

- The object file has been produced by the same JAPL version as the running interpreter: the 3-byte version header, the branch name and the commit hash must be the same for this check to succeed
- The object file is not older than an hour (this delay can be customized with the `--cache-delay` option)
- The SHA256 checksum of the source file matches the SHA256 checksum contained in the object file

If any of those checks fail, the object file is discarded and subsequently replaced by an updated version after the compiler is done processing the source file again (unless the `--nodump` switch is used, in which case no bytecode caching occurs). Since none of those checks are absolutely bulletproof, a `--nocache` option can be provided to the JAPL executable to instruct it to not load any already existing object files.


## Disclaimer
----------------------------------------------
The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in [RFC2119](https://datatracker.ietf.org/doc/html/rfc2119).

Literals in this document will be often surrounded by double quotes to make it obvious they're not part of a sentence. To
avoid ambiguity, this document will always specify explicitly if double quotes need to be considered as part of a term or not,
which means that if it is not otherwise stated they are to be considered part of said term. In addition to quotes, literals
may be formatted in monospace to make them stand out more in the document.

__Note__: The conventions about number literals described in the document laying out the formal grammar for JAPL also apply in this specification

## Compile-time type specifiers

To distinguish the different kinds of values that JAPL can represent at compile time, type specifiers are prepended to a given series of bytes to tell the deserializer what kind of object that specific sequence should deserialize into. It is important that each compile-time object specifies the size of its value in bytes using a 3-byte (24 bit) integer (referred to as "size specifier" from now on, without quotes), after the type specifier. The following sections about object representation assume the appropriate type and size specifiers have been used and will therefore omit them to avoid repetition. Some types (such as singletons) are encoded with a dedicated bytecode instruction rather than as a constant (booleans, nan and inf are notable examples of this).

Below a list of all type specifiers:
- `0x0` -> Identifier
- `0x1` -> Number
- `0x2` -> String
- `0x3` -> List literal (An heterogeneous dynamic array)
- `0x4` -> Set literal  (An heterogeneous and unordered dynamic array without duplicates. Mirrors the mathematical definition of a set)
- `0x5` -> Dictionary literal  (An associative array, also known as mapping)
- `0x6` -> Tuple literal (An heterogeneous static array)
- `0x7` -> Function declaration
- `0x8` -> Class declaration
- `0x9` -> Variable declaration. Note that constants are replaced during compilation with their corresponding literal value, therefore they are represented as literals in the constants section and are not compiled as variable declarations.
- `0x10` -> Lambda declarations (aka anonymous functions)


## Object representation

### Numbers

For simplicity purposes, numbers in object files are serialized as strings of decimal digits and optionally a dot followed by 1 or more decimal digits (for floats). The number `2.718`, for example, would just be serialized as the string `"2.718"` (without quotes). JAPL supports scientific notation such as `2e3`, but numbers in this form are collapsed to their decimal representation before being written to a file, therefore `2e3` becomes `2000.0`. Other decimal number representations such as hexadecimal, binary and octal are also converted to base 10 during compilation (or during the optimization process, if optimizations are enabled).

### Strings

Strings are a little more complex than numbers because JAPL supports string modifiers. The first byte of a string object represents its modifier, and can be any of:

- `0x00` -> No modifier
- `0x01` -> Byte string (begins with a "b", without quotes, before the quote)
- `0x02` -> Format string (begins with an "f", without quotes, before the quote)

The "r" (without quotes) string modifier, used to mark raw strings where escape sequences are not interpreted, does not need to have an explicit code because it is already interpreted by the tokenizer and has no other compile-time meaning. Note that in format strings, values are interpolated in them by using matching pairs of braces enclosing an expression and that the same name resolution strategy and scoping rules as for the rest of JAPL apply.

After the modifier follows the string encoded in UTF-8, __without__ quotes.


### List-like collections (sets, lists and tuples)
List-like collections (or _sequences_)-- namely sets, lists and tuples-- encode their length first: for lists and sets this only denotes the _starting_ size of the container, while a tuple's size is fixed once it is created. The length may be 0, in which case it is interpreted as the sequence being empty; After the length, which expresses the __number of elements__ in the collection (just the count!), follows a number of compile-time objects equal to the specified length, with their respective encoding.

__TODO__: Currently the compiler does not emit constant instructions for collections using only constants: it will just emit a bunch of `LoadConstant` instructions and
then a `BuildList` opcode with the length of the container as argument, so this section and the one below it are currently not relevant nor implemented yet.

### Mappings (or associative arrays)

Mappings (also called _associative arrays_ or, more informally, _dictionaries_) also encode their length first, but the difference lies in the element list that follows it: instead of there being n elements, with n being the length of the map, there are n _pairs_  (hence 2n elements) of objects that represent the key-value relation in the map.

## File structure

### File headers

An object file starts with the headers, namely:

- A 13-byte constant string with the value `"JAPL_BYTECODE"` (without quotes) encoded as a sequence of integers corresponding to their value in the ASCII table
- A 3-byte version header composed of 3 unsigned integers representing the major, minor and patch version of the compiler used to generate the file, respectively. JAPL follows the SemVer standard for versioning
- A string representing the branch name of the git repo from which JAPL was compiled, prepended with its size represented as a single 8-bit unsigned integer. Due to this encoding the branch name can't be longer than 256 characters, which is a length deemed appropriate for this purpose
- A 40 bytes hexadecimal string, pinpointing the version of the compiler down to the exact commit hash in the JAPL repository, particularly useful when testing development versions
- An 8 byte (64 bit) UNIX timestamp (starting from the Unix Epoch of January 1st 1970 at 00:00), representing the date and time when the file was created
- A 32 byte SHA256 checksum of the source file's contents, used to track file changes

### Constant section

This section of the file follows the headers and is meant to store all constants needed upon startup by the JAPL virtual machine. For example, the code `var x = 1;` would have the number one as a constant. Constants are just an ordered sequence of compile-time types as described in the sections above. The constant section's end is marked with
the byte `0x59`.

### Code section

After the headers and the constant section follows the code section, which stores the actual bytecode instructions the compiler has emitted. They're encoded as a linear sequence of bytes. The code section's size is fixed and is encoded as a 3-byte (24 bit) integer right after the constant section's end marker, limiting the maximum number of bytecode instructions per bytecode file to 16777216.

### Modules

When compiling source files, one object file is produced per source file. Since JAPL allows explicit visibility specifiers that alter the way namespaces are built at runtime (and, partially, resolved at compile-time) by selectively exporting (or not exporting) symbols to other modules, these directives need to be specified in the bytecode file (TODO).