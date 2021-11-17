# Copyright 2021 Mattia Giambirtone & All Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
import meta/ast
import meta/errors
import meta/bytecode
import ../config


import strformat
import strutils
import nimSHA2
import times


export ast

type
    Serializer* = ref object
        file: string
        filename: string
        chunk: Chunk
    Serialized* = ref object
        ## Wrapper returned by 
        ## the Serializer.read*
        ## procedures to store
        ## metadata
        fileHash*: string
        japlVer*: tuple[major, minor, patch: int]
        japlBranch*: string
        commitHash*: string
        compileDate*: int
        chunk*: Chunk


proc `$`*(self: Serialized): string =
    result = &"Serialized(fileHash={self.fileHash}, version={self.japlVer.major}.{self.japlVer.minor}.{self.japlVer.patch}, branch={self.japlBranch}), commitHash={self.commitHash}, date={self.compileDate}, chunk={self.chunk[]}"


proc error(self: Serializer, message: string) =
    ## Raises a formatted SerializationError exception
    raise newException(SerializationError, &"A fatal error occurred while serializing '{self.filename}' -> {message}")


proc initSerializer*(): Serializer =
    new(result)
    result.file = ""
    result.filename = ""
    result.chunk = nil


## Basic routines and helpers to convert various objects from and to to their byte representation

proc toBytes(self: Serializer, s: string): seq[byte] =
    for c in s:
        result.add(byte(c))


proc toBytes(self: Serializer, s: int): array[8, uint8] =
    result = cast[array[8, uint8]](s)


proc toBytes(self: Serializer, d: SHA256Digest): seq[byte] =
    for b in d:
        result.add(b)


proc bytesToString(self: Serializer, input: seq[byte]): string =
    for b in input:
        result.add(char(b))


proc bytesToInt(self: Serializer, input: array[8, byte]): int =
    copyMem(result.addr, input.unsafeAddr, sizeof(int))


proc extend[T](s: var seq[T], a: openarray[T]) =
    ## Extends s with the elements of a
    for e in a:
        s.add(e)


proc dumpBytes*(self: Serializer, chunk: Chunk, file, filename: string): seq[byte] =
    ## Dumps the given bytecode and file to a sequence of bytes and returns it.
    ## The file argument must be the actual file's content and is needed to compute its SHA256 hash.
    self.file = file
    self.filename = filename
    self.chunk = chunk
    result.extend(self.toBytes(BYTECODE_MARKER))
    result.add(byte(JAPL_VERSION.major))
    result.add(byte(JAPL_VERSION.minor))
    result.add(byte(JAPL_VERSION.patch))
    result.add(byte(len(JAPL_BRANCH)))
    result.extend(self.toBytes(JAPL_BRANCH))
    if len(JAPL_COMMIT_HASH) != 40:
        self.error("the commit hash must be exactly 40 characters long")
    result.extend(self.toBytes(JAPL_COMMIT_HASH))
    result.extend(self.toBytes(getTime().toUnixFloat().int()))
    result.extend(self.toBytes(computeSHA256(file)))
    for constant in chunk.consts:
        case constant.kind:
            of intExpr, floatExpr:
                result.add(0x1)
                result.add(byte(len(constant.token.lexeme)))
                result.extend(self.toBytes(constant.token.lexeme))
            of strExpr:
                var strip: int = 2
                var offset: int = 1
                result.add(0x2)
                case constant.token.lexeme[0]:
                    of 'f':
                        strip = 3
                        inc(offset)
                        result.add(0x2)
                    of 'b':
                        strip = 3
                        inc(offset)
                        result.add(0x1)
                    else:
                        strip = 2
                        result.add(0x0)
                result.add(byte(len(constant.token.lexeme) - offset))  # Removes the quotes from the length count as they're not written
                result.add(self.toBytes(constant.token.lexeme[offset..^2]))
            of identExpr:
                result.add(0x2)
                result.add(0x0)
                result.add(byte(len(constant.token.lexeme)))
                result.add(self.toBytes(constant.token.lexeme))
            of trueExpr:
                result.add(0xC)
            of falseExpr:
                result.add(0xD)
            of nilExpr:
                result.add(0xF)
            of nanExpr:
                result.add(0xA)
            of infExpr:
                result.add(0xB)
            else:
                self.error(&"unknown constant kind in chunk table ({constant.kind})")


proc loadBytes*(self: Serializer, stream: seq[byte]): Serialized =
    ## Loads the result from dumpBytes to a Serializer object
    ## for use in the VM or for inspection
    new(result)
    result.chunk = newChunk()
    var stream = stream
    try:
        if stream[0..<len(BYTECODE_MARKER)] != self.toBytes(BYTECODE_MARKER):
            self.error("malformed bytecode marker")
        stream = stream[len(BYTECODE_MARKER)..^1]
        result.japlVer = (major: int(stream[0]), minor: int(stream[1]), patch: int(stream[2]))
        stream = stream[3..^1]
        let branchLength = stream[0]
        stream = stream[1..^1]
        result.japlBranch = self.bytesToString(stream[0..<branchLength])
        stream = stream[branchLength..^1]
        result.commitHash = self.bytesToString(stream[0..<40]).toLowerAscii()
        stream = stream[40..^1]
        result.compileDate = self.bytesToInt([stream[0], stream[1], stream[2], stream[3], stream[4], stream[5], stream[6], stream[7]])
        stream = stream[8..^1]
        result.fileHash = self.bytesToString(stream[0..<32]).toHex().toLowerAscii()
    except IndexDefect:
        self.error("truncated bytecode file")
    















