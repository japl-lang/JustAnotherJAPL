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
import backend/lexer
import backend/parser
import backend/optimizer


import strformat

var source: string
var filename = "test.jpl"
var tokens: seq[Token]
var tree: seq[ASTNode]
var optimized: tuple[tree: seq[ASTNode], warnings: seq[Warning]]

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
        tokens = initLexer().lex(source, filename)
        tree = initParser().parse(tokens, filename)
        optimized = initOptimizer().optimize(tree)
    except:
        echo &"A Nim runtime exception occurred: {getCurrentExceptionMsg()}"
        continue

    echo "Tokenization step: "
    for token in tokens:
        echo "\t", token
    echo ""

    echo &"Parsing step: "
    for node in tree:
        echo "\t", node
    echo ""

    echo &"Optimization step:"
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