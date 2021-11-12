# Copyright 2021 Mattia Giambirtone
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


proc hook() {.noconv.} =
    quit(1)


proc main() =
    var source: string
    const filename = "test.jpl"
    var tokens: seq[Token]
    var tree: seq[ASTNode]
    var optimized: tuple[tree: seq[ASTNode], warnings: seq[Warning]]
    var compiled: Chunk
    var serializedBytes: seq[byte]
    var lexer = initLexer()
    var parser = initParser()
    var optimizer = initOptimizer(foldConstants=true)
    var compiler = initCompiler()
    var serializer = initSerializer()

    var japlBranch = ""
    var japlVersion = ""
    var japlCommitHash = ""
    var fileHash = ""
    var compileDate = 0
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
            echo &"\tRaw byte stream: [{compiled.code.join(\", \")}]"
            echo "\tBytecode disassembler output below:\n"
            disassembleChunk(compiled, filename)
            echo ""
            
            serializedBytes = serializer.dumpBytes(compiled, source, filename)
            echo "(De)Serialization step:"
            echo "\t"
            echo &"\tRaw byte stream: [{serializedBytes.join(\", \")}]"
        except:
            echo &"A Nim runtime exception occurred: {getCurrentExceptionMsg()}"
            continue



when isMainModule:
    setControlCHook(hook)
    main()