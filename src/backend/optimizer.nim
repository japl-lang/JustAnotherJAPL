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
import meta/token


import parseutils


type
    WarningKind* = enum
        unreachableCode,
        localShadowsGlobal,
        isWithALiteral,
        equalityWithSingleton,
        valueOverflow,
        valueUnderflow,
        implicitConversion

    Warning* = ref object
        kind*: WarningKind
        node*: ASTNode

    Optimizer* = ref object
        constantFolding: bool
        emitWarnings: bool
        warnings: seq[Warning]
        dryRun: bool


proc initOptimizer*(self: Optimizer = nil, constantFolding = true, emitWarnings = true, dryRun = false): Optimizer =
    ## Initializes a new optimizer object
    ## or resets the state of an existing one
    if self != nil:
        result = self
    new(result)
    result.constantFolding = constantFolding
    result.emitWarnings = emitWarnings
    result.dryRun = dryRun


proc newWarning(self: Optimizer, kind: WarningKind, node: ASTNode) =
    self.warnings.add(Warning(kind: kind, node: node))


proc checkConstants(self: Optimizer, node: ASTNode): ASTNode =
    ## Performs some checks on constant AST nodes such as
    ## integers. This method converts all of the different
    ## integer forms (binary, octal and hexadecimal) to
    ## decimal integers. Overflows are checked here too
    case node.kind:
        of intExpr:
            var x: int
            var y = IntExpr(node)
            assert parseInt(y.literal.lexeme, x) == len(y.literal.lexeme)
            result = node
        of hexExpr:
            var x: int
            var y = HexExpr(node)
            assert parseHex(y.literal.lexeme, x) == len(y.literal.lexeme)
            result = ASTNode(IntExpr(kind: intExpr, literal: Token(kind: Integer, lexeme: $x, line: y.literal.line, pos: (start: y.literal.pos.start, stop: len($x)))))
        of binExpr:
            var x: int
            var y = BinExpr(node)
            assert parseBin(y.literal.lexeme, x) == len(y.literal.lexeme)
            result = ASTNode(IntExpr(kind: intExpr, literal: Token(kind: Integer, lexeme: $x, line: y.literal.line, pos: (start: y.literal.pos.start, stop: len($x)))))
        of octExpr:
            var x: int
            var y = OctExpr(node)
            assert parseOct(y.literal.lexeme, x) == len(y.literal.lexeme)
            result = ASTNode(IntExpr(kind: intExpr, literal: Token(kind: Integer, lexeme: $x, line: y.literal.line, pos: (start: y.literal.pos.start, stop: len($x)))))
        of floatExpr:
            var x: float
            var y = FloatExpr(node)
            assert parseFloat(y.literal.lexeme, x) == len(y.literal.lexeme)
            result = ASTNode(IntExpr(kind: intExpr, literal: Token(kind: Integer, lexeme: $x, line: y.literal.line, pos: (start: y.literal.pos.start, stop: len($x)))))
        else:
            result = node


proc foldConstants(self: Optimizer, node: ASTNode): ASTNode =
    ## Attempts to perform constant folding if it is feasible
    ## and if the self.constantFolding field is set to true.
    
    if not self.constantFolding:
        return node


proc optimizeUnary(self: Optimizer, node: UnaryExpr): ASTNode =
    ## Attempts to optimize unary expressions
    result = node


proc optimizeBinary(self: Optimizer, node: BinaryExpr): ASTNode =
    ## Attempts to optimize binary expressions
    var a, b: ASTNode
    a = self.checkConstants(node.a)
    b = self.checkConstants(node.b)
    if a.kind == intExpr and b.kind == intExpr:
        result = ASTNode(BinaryExpr(kind: binaryExpr, a: a, b: b, operator: node.operator))
    result = node


proc optimizeNode(self: Optimizer, node: ASTNode): ASTNode =
    ## Analyzes an AST node and attempts to perform
    ## optimizations on it. If no optimization can be
    ## applied, the same node is returned
    case node.kind:
        of exprStmt:
            result = self.optimizeNode(ExprStmt(node).expression)
        of intExpr, hexExpr, octExpr, binExpr, floatExpr, strExpr:
            result = self.checkConstants(node)
        of unaryExpr:
            result = self.optimizeUnary(UnaryExpr(node))
        of binaryExpr:
            result = self.optimizeBinary(BinaryExpr(node))
        of groupingExpr:
            result = self.optimizeNode(GroupingExpr(node).expression)
        else:
            result = node


proc optimize*(self: Optimizer, tree: seq[ASTNode]): tuple[tree: seq[ASTNode], warnings: seq[Warning]] =
    ## Runs the optimizer on the given source
    ## tree and returns a new optimized tree
    ## as well as a list of warnings that may
    ## be of interest. Depending on whether any
    ## optimization could be performed, the output
    ## may be identical to the input. If self.dryRun
    ## is set to true, no optimization is performed,
    ## but warnings and log messages are still
    ## generated
    var newTree: seq[ASTNode] = @[]
    for node in tree:
        newTree.add(self.optimizeNode(node))
    result = (tree: newTree, warnings: self.warnings)