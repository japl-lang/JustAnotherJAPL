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
import backend/lexer
import backend/parser
import backend/optimizer
import backend/compiler
import util/debugger
import backend/serializer


import strformat
import strutils
import sequtils
import times
import nimSHA2


proc hook() {.noconv.} =
    quit(1)


proc main() =
    var source: string
    const filename = "test.jpl"
    var tokens: seq[Token]
    var tree: seq[ASTNode]
    var optimized: tuple[tree: seq[ASTNode], warnings: seq[Warning]]
    var compiled: Chunk
    var serialized: Serialized
    var serializedRaw: seq[byte]
    var lexer = initLexer()
    var parser = initParser()
    var optimizer = initOptimizer(foldConstants=false)
    var compiler = initCompiler()
    var serializer = initSerializer()
    var hashMatches: bool
    var compileDate: string

    echo "NimVM REPL\n"
    while true:
        try:
            stdout.write(">>> ")
            source = stdin.readLine()
        except IOError:
            echo ""
            break

        echo &"Processing: '{source}'\n"
        try:
            tokens = lexer.lex(source, filename)
            echo "Tokenization step: "
            for token in tokens:
                echo "\t", token
            echo ""

            tree = parser.parse(tokens, filename)

            # We run this now because the optimizer
            # acts in-place on the AST so if we printed
            # it later the parsed tree would equal the
            # optimized one!
            echo "Parsing step: "
            for node in tree:
                echo "\t", node
            echo ""

            optimized = optimizer.optimize(tree)

            echo "Optimization step:"
            for node in optimized.tree:
                echo "\t", node
            echo ""

            stdout.write(&"Produced warnings: ")
            if optimized.warnings.len() > 0:
                echo ""
                for warning in optimized.warnings:
                    echo "\t", warning
            else:
                stdout.write("No warnings produced\n")
            echo ""

            compiled = compiler.compile(optimized.tree, filename)
            echo "Compilation step:"
            stdout.write("\t")
            echo &"""Raw byte stream: [{compiled.code.join(", ")}]"""
            echo "\n\nBytecode disassembler output below:\n"
            disassembleChunk(compiled, filename)
            echo ""
            
            serializedRaw = serializer.dumpBytes(compiled, source, filename)
            echo "Serialization step: "
            stdout.write("\t")
            echo &"""Raw hex output: {serializedRaw.mapIt(toHex(it)).join("").toLowerAscii()}"""
            echo ""

            serialized = serializer.loadBytes(serializedRaw)
            hashMatches = if computeSHA256(source).toHex().toLowerAscii() == serialized.fileHash: true else: false
            echo "Deserialization step:"
            echo &"\t\t- File hash: {serialized.fileHash} (matches: {hashMatches})"
            echo &"\t\t- JAPL version: {serialized.japlVer.major}.{serialized.japlVer.minor}.{serialized.japlVer.patch} (commit {serialized.commitHash[0..7]} on branch {serialized.japlBranch})"
            compileDate = fromUnix(serialized.compileDate).format("d/M/yyyy H:mm:ss")
            echo &"\t\t- Compilation date & time: {compileDate}"
        except:
            raise
            echo &"A Nim runtime exception occurred: {getCurrentExceptionMsg()}"
            continue



when isMainModule:
    setControlCHook(hook)
    main()
