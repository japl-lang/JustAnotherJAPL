# NimVM - Bytecode Serialization Standard

## Rationale
This document aims to lay down a simple, extensible and linear format for serializing and deserializing
compiled NimVM's code to a buffer (be it an actual OS file or an in-memory stream).

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

To distinguish the different kinds of values that JAPL can represent at compile time, type specifiers are prepended to a given series of bytes to tell the deserializer what kind of object that specific sequence should deserialize into. It is important that each compile-time object specifies the size of its value in bytes (referred to as "size specifier" from now on, without quotes), after the type specifier. The following sections about object representation assume the appropriate type and size specifiers have been used and will therefore omit them to avoid repetition. Some types (such as singletons) do not need a size specifier as they're only one byte long: these cases are an exception rather than the rule and are explicitly marked as such in this document.

Below a list of all type specifiers:

- `0xC` -> true*
- `0xD` -> false*
- `0xF` -> nil*
- `0xA` -> nan*
- `0xB` -> inf*
- `0x01` -> Number
- `0x02` -> String
- `0x03` -> List literal (An heterogeneous dynamic array)
- `0x04` -> Set literal  (An heterogeneous dynamic array without duplicates. Mirrors the mathematical definition of a set)
- `0x05` -> Dictionary literal  (An associative array, also known as mapping)
- `0x06` -> Tuple literal (An heterogeneous, static array)
- `0x07` -> Function declaration
- `0x08` -> Class declaration
- `0x09` -> Variable declaration. Note that constants are replaced during compilation with their corresponding literal value, therefore they are represented as literals in the constants section and are not compiled as variable declarations.
- `0x10` -> Lambda declarations (aka anonymous functions)


__Note__: The types whose name is followed by an asterisk require no size specifier, as they're 1 byte long and adding one would only waste space.

### Object representation

#### Numbers

For simplicity purposes, numbers in object files are serialized as strings of decimal digits and optionally a dot followed by 1 or more decimal digits (for floats). The number `2.718`, for example, would just be serialized as the string `"2.718"` (without quotes). JAPL supports scientific notation such as `2e3`, but numbers in this form are collapsed to their decimal representation before being written to a file, therefore `2e3` becomes `2000.0`. Other decimal number representations such as hexadecimal, binary and octal are also converted to base 10 during compilation.

#### Strings

Strings are a little more complex than numbers because JAPL supports string modifiers. The first byte of a string object represents its modifier, and can be any of:

- `0x00` -> No modifier
- `0x01` -> Byte string (begins with a "b", without quotes, before the quote)
- `0x02` -> Format string (begins with an "f", without quotes, before the quote)

The "r" (without quotes) string modifier, used to mark raw strings where escape sequences are not interpreted, does not need to have an explicit code because it is already interpreted by the tokenizer and has no other compile-time meaning. Note that in format strings, values are interpolated in them by using matching pairs of braces enclosing an expression and that the same name resolution strategy is used as for the rest of JAPL.

After the modifier follows the string encoded in UTF-8.


## File structure

Once a JAPL source file (i.e. one with a ".jpl" extension, without quotes) has been successfully compiled to bytecode, the compiler dumps the resulting linear stream of bytes to a ".japlc" file (without quotes, which stands for __JAPL C__ompiled), which we will call "object file" (without quotes) in this document. The name of the object file will be the same of the original source file, and its structure is described below.

### File headers

An object file starts with the headers, namely:

- A 13-byte constant string with the value `"JAPL_BYTECODE"` (without quotes) encoded as a sequence of integers of the ASCII encoding of each character in the string
- A 3-byte version header composed of 3 unsigned integers representing the major, minor and patch version of the compiler used to generate the file, respectively. JAPL follows the SemVer standard for versioning
- A string representing the branch name of the git repo from which JAPL was compiled, prepended with its size represented as a single 8-bit unsigned integer. Due to this encoding the branch name can't be longer than 256 characters, which is a length deemed appropriate for this purpose
- A 40 bytes hexadecimal string, pinpointing the version of the compiler down to the exact commit hash in the JAPL repository, particularly useful when testing development versions
- An 8 byte (64 bit) UNIX timestamp (starting from the Unix Epoch of January 1st 1970 at 00:00), representing the date and time when the file was created
- A 32 bytes SHA256 checksum of the source file's contents, used to track file changes

### Constant section

This section of the file follows the headers and is meant to store all constants needed upon startup by the JAPL virtual machine. For example, the code `var x = 1;` would have the number one as a constant.


## Behavior

The main reason to serialize bytecode to a file is for porting JAPL code to other machines, but also to avoid processing the same file every time if it hasn't changed, therefore using it as a sort of cache. If this cache-like behavior is abused though, it may lead to unexpected behavior, hence we define how the JAPL toolchain will deal with local object files.

When JAPL finds an existing object file whose name matches the one of the source file that has to be ran, it will skip processing the source file and use the existing object file only if:

- The object file has been produced by the same JAPL version as the running interpreter: the 3-byte version header, the branch name and the commit hash must be the same
- The object file is not older than an hour (this delay can be customized)
- The SHA256 checksum of the source file matches the SHA256 checksum contained in the object file

If any of those checks fail, the object file is discarded and subsequently replaced by an updated one after the compiler is done processing the source file again. Since none of those checks are absolutely bulletproof, a `--nocache` option can be provided to the JAPL executable to instruct it to not load nor produce any object files.


