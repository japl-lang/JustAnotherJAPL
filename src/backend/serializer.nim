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
import meta/token
import ../config
import ../util/multibyte

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
    raise newException(SerializationError, &"A fatal error occurred while (de)serializing '{self.filename}' -> {message}")


proc initSerializer*(self: Serializer = nil): Serializer =
    new(result)
    if self != nil:
        result = self
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


proc bytesToInt(self: Serializer, input: array[3, byte]): int =
    copyMem(result.addr, input.unsafeAddr, sizeof(byte) * 3)


proc extend[T](s: var seq[T], a: openarray[T]) =
    ## Extends s with the elements of a
    for e in a:
        s.add(e)


proc writeHeaders(self: Serializer, stream: var seq[byte], file: string) = 
    ## Writes the JAPL bytecode headers in-place into a byte stream
    stream.extend(self.toBytes(BYTECODE_MARKER))
    stream.add(byte(JAPL_VERSION.major))
    stream.add(byte(JAPL_VERSION.minor))
    stream.add(byte(JAPL_VERSION.patch))
    stream.add(byte(len(JAPL_BRANCH)))
    stream.extend(self.toBytes(JAPL_BRANCH))
    if len(JAPL_COMMIT_HASH) != 40:
        self.error("the commit hash must be exactly 40 characters long")
    stream.extend(self.toBytes(JAPL_COMMIT_HASH))
    stream.extend(self.toBytes(getTime().toUnixFloat().int()))
    stream.extend(self.toBytes(computeSHA256(file)))


proc writeConstants(self: Serializer, stream: var seq[byte]) =
    ## Writes the constants table in-place into the given stream
    for constant in self.chunk.consts:
        case constant.kind:
            of intExpr, floatExpr:
                stream.add(0x1)
                stream.extend(len(constant.token.lexeme).toTriple())
                stream.extend(self.toBytes(constant.token.lexeme))
            of strExpr:
                stream.add(0x2)
                var temp: seq[byte] = @[]
                var strip: int = 2
                var offset: int = 1
                case constant.token.lexeme[0]:
                    of 'f':
                        strip = 3
                        inc(offset)
                        temp.add(0x2)
                    of 'b':
                        strip = 3
                        inc(offset)
                        temp.add(0x1)
                    else:
                        strip = 2
                        temp.add(0x0)
                stream.extend((len(constant.token.lexeme) - strip).toTriple())  # Removes the quotes from the length count as they're not written
                stream.extend(temp)
                stream.add(self.toBytes(constant.token.lexeme[offset..^2]))
            of identExpr:
                stream.add(0x0)
                stream.extend(len(constant.token.lexeme).toTriple())
                stream.add(self.toBytes(constant.token.lexeme))
            of trueExpr:
                stream.add(0xC)
            of falseExpr:
                stream.add(0xD)
            of nilExpr:
                stream.add(0xF)
            of nanExpr:
                stream.add(0xA)
            of infExpr:
                stream.add(0xB)
            else:
                self.error(&"unknown constant kind in chunk table ({constant.kind})")
    stream.add(0x59)  # End marker


proc readConstants(self: Serializer, stream: seq[byte]): int =
    ## Reads the constant table from the given stream and
    ## adds each constant to the chunk object (note: most compile-time
    ## information such as the original token objects and line info is lost when
    ## serializing the data, so those fields are set to nil or some default
    ## value). Returns the number of bytes that were processed in the stream
    var stream = stream
    var count: int = 0
    while true:
        case stream[0]:
            of 0x59:
                inc(count)
                break
            of 0x2:
                stream = stream[1..^1]
                let size = self.bytesToInt([stream[0], stream[1], stream[2]])
                stream = stream[3..^1]
                var s = newStrExpr(Token(lexeme: ""))
                case stream[0]:
                    of 0x0:
                        discard
                    of 0x1:
                        s.token.lexeme.add("b")
                    of 0x2:
                        s.token.lexeme.add("f")
                    else:
                        self.error(&"unknown string modifier in chunk table (0x{stream[0].toHex()}")
                stream = stream[1..^1]
                s.token.lexeme.add("\"")
                for i in countup(0, size - 1):
                    s.token.lexeme.add(cast[char](stream[i]))
                s.token.lexeme.add("\"")
                stream = stream[size..^1]
                self.chunk.consts.add(s)
                inc(count, size + 5)
            of 0x1:
                stream = stream[1..^1]
                inc(count)
                let size = self.bytesToInt([stream[0], stream[1], stream[2]])
                stream = stream[3..^1]
                inc(count, 3)
                var tok: Token = new(Token)
                tok.lexeme = self.bytesToString(stream[0..<size])
                if "." in tok.lexeme:
                    tok.kind = Float
                    self.chunk.consts.add(newFloatExpr(tok))
                else:
                    tok.kind = Integer
                    self.chunk.consts.add(newIntExpr(tok))
                stream = stream[size..^1]
                inc(count, size)
            of 0x0:
                stream = stream[1..^1]
                let size = self.bytesToInt([stream[0], stream[1], stream[2]])
                stream = stream[3..^1]
                discard self.chunk.addConstant(newIdentExpr(Token(lexeme: self.bytesToString(stream[0..<size]))))
                inc(count, size + 4)
            of 0xC:
                discard self.chunk.addConstant(newTrueExpr(nil))
                stream = stream[1..^1]
                inc(count)
            of 0xD:
                discard self.chunk.addConstant(newFalseExpr(nil))
                stream = stream[1..^1]
                inc(count)
            of 0xF:
                discard self.chunk.addConstant(newNilExpr(nil))
                stream = stream[1..^1]
                inc(count)
            of 0xA:
                discard self.chunk.addConstant(newNaNExpr(nil))
                stream = stream[1..^1]
                inc(count)
            of 0xB:
                discard self.chunk.addConstant(newInfExpr(nil))
                stream = stream[1..^1]
                inc(count)
            else:
                self.error(&"unknown constant kind in chunk table (0x{stream[0].toHex()})")
    result = count


proc writeCode(self: Serializer, stream: var seq[byte]) =
    ## Writes the bytecode from the given chunk to the given source
    ## stream
    stream.extend(self.chunk.code.len.toTriple())
    stream.extend(self.chunk.code)


proc readCode(self: Serializer, stream: seq[byte]): int =
    ## Reads the bytecode from a given stream and writes
    ## it into the given chunk
    let size = [stream[0], stream[1], stream[2]].fromTriple()
    var stream = stream[3..^1]
    for i in countup(0, int(size) - 1):
        self.chunk.code.add(stream[i])
    assert len(self.chunk.code) == int(size)
    return int(size)


proc dumpBytes*(self: Serializer, chunk: Chunk, file, filename: string): seq[byte] =
    ## Dumps the given bytecode and file to a sequence of bytes and returns it.
    ## The file argument must be the actual file's content and is needed to compute its SHA256 hash.
    self.file = file
    self.filename = filename
    self.chunk = chunk
    self.writeHeaders(result, self.file)
    self.writeConstants(result)
    self.writeCode(result)


proc loadBytes*(self: Serializer, stream: seq[byte]): Serialized =
    ## Loads the result from dumpBytes to a Serializer object
    ## for use in the VM or for inspection
    discard self.initSerializer()
    new(result)
    result.chunk = newChunk()
    self.chunk = result.chunk
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
        stream = stream[32..^1]
        stream = stream[self.readConstants(stream)..^1]
        stream = stream[self.readCode(stream)..^1]
    except IndexDefect:
        self.error("truncated bytecode file")
    except AssertionDefect:
        self.error("corrupted bytecode file")
    















