# Copyright 2020 Mattia Giambirtone
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
        japlVer*: string
        japlBranch*: string
        commitHash*: string
        chunk*: Chunk


proc error(self: Serializer, message: string) =
    ## Raises a formatted SerializationError exception
    raise newException(SerializationError, &"A fatal error occurred while serializing '{self.filename}' -> {message}")


proc initSerializer*(): Serializer =
    new(result)
    result.file = ""
    result.filename = ""
    result.chunk = nil


proc dumpBytes*(self: Serializer, chunk: Chunk, file, filename: string): seq[byte] =
    ## Dumps the given bytecode and file to a sequence of bytes and returns it.
    ## The file's content is needed to compute its SHA256 hash.
    self.file = file
    self.filename = filename
    self.chunk = chunk
    for c in "JAPL_BYTECODE":
        result.add(byte(c))
    result.add(byte(len(JAPL_BRANCH)))
    for c in JAPL_BRANCH:
        result.add(byte(c))
    if len(JAPL_COMMIT_HASH) != 40:
        self.error("the commit hash must be exactly 40 characters long")
    for c in JAPL_COMMIT_HASH:
        result.add(byte(c))
    for b in cast[array[8, uint8]](getTime().toUnixFloat().int()):
        result.add(b)
    for c in computeSHA256(file):
        result.add(byte(c))


proc dumpHex*(self: Serializer, chunk: Chunk, file, filename: string): string =
    ## Wrapper of dumpBytes that returns a hex string (using strutils.toHex)
    ## instead of a seq[byte]
    for b in self.dumpBytes(chunk, file, filename):
        result.add(toHex(b))
