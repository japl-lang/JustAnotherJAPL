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

## Test module to wire up JAPL components
import backend/lexer
import backend/parser
import backend/optimizer
import backend/compiler
import util/debugger
import backend/serializer
import jale/editor
import jale/templates
import jale/plugin/defaults
import jale/plugin/editor_history
import config


import strformat
import strutils
import sequtils
import times
import nimSHA2


proc getLineEditor: LineEditor =
    result = newLineEditor()
    result.prompt = "=> "
    result.populateDefaults()  # setup default keybindings
    let hist = result.plugHistory()  # create history object
    result.bindHistory(hist)  # set default history keybindings


proc main =
    const filename = "test.jpl"
    var source: string
    var tokens: seq[Token]
    var tree: seq[ASTNode]
    var optimized: tuple[tree: seq[ASTNode], warnings: seq[Warning]]
    var compiled: Chunk
    var serialized: Serialized
    var serializedRaw: seq[byte]
    var keep = true

    var lexer = initLexer()
    var parser = initParser()
    var optimizer = initOptimizer(foldConstants=false)
    var compiler = initCompiler()
    var serializer = initSerializer()
    let lineEditor = getLineEditor()
    lineEditor.bindEvent(jeQuit):
        keep = false

    echo JAPL_VERSION_STRING
    while keep:
        try:
            stdout.write(">>> ")
            source = lineEditor.read()
            if source in ["# clear", "#clear"]:
                echo "\x1Bc" & JAPL_VERSION_STRING
                continue
            elif source == "#exit" or source == "# exit":
                echo "Goodbye!"
                break
            elif source == "":
                continue
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
            echo "Parsing step: "
            for node in tree:
                echo "\t", node
            echo ""

            optimized = optimizer.optimize(tree)
            echo &"Optimization step (constant folding enabled: {optimizer.foldConstants}):"
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
            echo "\nBytecode disassembler output below:\n"
            disassembleChunk(compiled, filename)
            echo ""
            
            serializedRaw = serializer.dumpBytes(compiled, source, filename)
            echo "Serialization step: "
            stdout.write("\t")
            echo &"""Raw hex output: {serializedRaw.mapIt(toHex(it)).join("").toLowerAscii()}"""
            echo ""

            serialized = serializer.loadBytes(serializedRaw)
            echo "Deserialization step:"
            echo &"\t- File hash: {serialized.fileHash} (matches: {computeSHA256(source).toHex().toLowerAscii() == serialized.fileHash})"
            echo &"\t- JAPL version: {serialized.japlVer.major}.{serialized.japlVer.minor}.{serialized.japlVer.patch} (commit {serialized.commitHash[0..8]} on branch {serialized.japlBranch})"
            stdout.write("\t")
            echo &"""- Compilation date & time: {fromUnix(serialized.compileDate).format("d/M/yyyy HH:mm:ss")}"""
            stdout.write(&"\t- Reconstructed constants table: [")
            for i, e in serialized.chunk.consts:
                stdout.write(e)
                if i < len(serialized.chunk.consts) - 1:
                    stdout.write(", ")
            stdout.write("]\n")
            stdout.write(&"\t- Reconstructed bytecode: [")
            for i, e in serialized.chunk.code:
                stdout.write($e)
                if i < len(serialized.chunk.code) - 1:
                    stdout.write(", ")
            stdout.write(&"] (matches: {serialized.chunk.code == compiled.code})\n")
        except:
            echo &"A Nim runtime exception occurred: {getCurrentExceptionMsg()}"


when isMainModule:
    setControlCHook(proc {.noconv.} = quit(1))
    main()
