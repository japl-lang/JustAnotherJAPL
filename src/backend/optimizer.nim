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
import strformat
import strutils
import math


type
    WarningKind* = enum
        unreachableCode,
        nameShadowing,
        isWithALiteral,
        equalityWithSingleton,
        valueOverflow,
        implicitConversion,

    Warning* = ref object
        kind*: WarningKind
        node*: ASTNode

    Optimizer* = ref object
        warnings: seq[Warning]
        foldConstants: bool


proc initOptimizer*(foldConstants: bool = true): Optimizer =
    ## Initializes a new optimizer object
    new(result)
    result.foldConstants = foldConstants
    result.warnings = @[]


proc newWarning(self: Optimizer, kind: WarningKind, node: ASTNode) =
    self.warnings.add(Warning(kind: kind, node: node))


proc `$`*(self: Warning): string = &"Warning(kind={self.kind}, node={self.node})"


# Forward declaration
proc optimizeNode(self: Optimizer, node: ASTNode): ASTNode


proc optimizeConstant(self: Optimizer, node: ASTNode): ASTNode =
    ## Performs some checks on constant AST nodes such as
    ## integers. This method converts all of the different
    ## integer forms (binary, octal and hexadecimal) to
    ## decimal integers. Overflows are checked here too
    if not self.foldConstants:
        return node
    case node.kind:
        of intExpr:
            var x: int
            var y = IntExpr(node)
            try:
                assert parseInt(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.newWarning(valueOverflow, node)
            result = node
        of hexExpr:
            var x: int
            var y = HexExpr(node)
            try:
                assert parseHex(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.newWarning(valueOverflow, node)
                return node
            result = IntExpr(kind: intExpr, literal: Token(kind: Integer, lexeme: $x, line: y.literal.line, pos: (start: -1, stop: -1)))
        of binExpr:
            var x: int
            var y = BinExpr(node)
            try:
                assert parseBin(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.newWarning(valueOverflow, node)
                return node
            result = IntExpr(kind: intExpr, literal: Token(kind: Integer, lexeme: $x, line: y.literal.line, pos: (start: -1, stop: -1)))
        of octExpr:
            var x: int
            var y = OctExpr(node)
            try:
                assert parseOct(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.newWarning(valueOverflow, node)
                return node
            result = IntExpr(kind: intExpr, literal: Token(kind: Integer, lexeme: $x, line: y.literal.line, pos: (start: -1, stop: -1)))
        of floatExpr:
            var x: float
            var y = FloatExpr(node)
            try:
                assert parseFloat(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.newWarning(valueOverflow, node)
                return node
            result = FloatExpr(kind: floatExpr, literal: Token(kind: Float, lexeme: $x, line: y.literal.line, pos: (start: -1, stop: -1)))
        else:
            result = node


proc optimizeUnary(self: Optimizer, node: UnaryExpr): ASTNode =
    ## Attempts to optimize unary expressions
    var a = self.optimizeNode(node.a)
    if self.warnings.len() > 0 and self.warnings[^1].kind == valueOverflow and self.warnings[^1].node == a:
        # We can't optimize further, the overflow will be caught in the compiler
        return UnaryExpr(kind: unaryExpr, a: a, operator: node.operator)
    case a.kind:
        of intExpr:
            var x: int
            discard parseInt(IntExpr(a).literal.lexeme, x)
            case node.operator.kind:
                of Tilde:
                    x = not x
                of Minus:
                    x = -x
                else:
                    discard  # Unreachable
            result = IntExpr(kind: intExpr, literal: Token(kind: Integer, lexeme: $x, line: node.operator.line, pos: (start: -1, stop: -1)))
        of floatExpr:
            var x: float
            discard parseFloat(FloatExpr(a).literal.lexeme, x)
            case node.operator.kind:
                of Minus:
                    x = -x
                else:
                    discard
            result = FloatExpr(kind: floatExpr, literal: Token(kind: Float, lexeme: $x, line: node.operator.line, pos: (start: -1, stop: -1)))
        else:
            discard  # Unreachable


proc optimizeBinary(self: Optimizer, node: BinaryExpr): ASTNode =
    ## Attempts to optimize binary expressions
    var a, b: ASTNode
    a = self.optimizeNode(node.a)
    b = self.optimizeNode(node.b)
    if self.warnings.len() > 0 and self.warnings[^1].kind == valueOverflow and (self.warnings[^1].node == a or self.warnings[^1].node == b):
        # We can't optimize further, the overflow will be caught in the compiler. We don't return the same node
        # because optimizeNode might've been able to optimize one of the two operands and we don't know which
        return BinaryExpr(kind: binaryExpr, a: a, b: b, operator: node.operator)
    if node.operator.kind == DoubleEqual:
        if a.kind in {trueExpr, falseExpr, nilExpr, nanExpr, infExpr}:
            self.newWarning(equalityWithSingleton, a)
        elif b.kind in {trueExpr, falseExpr, nilExpr, nanExpr, infExpr}:
            self.newWarning(equalityWithSingleton, b)
    elif node.operator.kind == Is:
        if a.kind in {strExpr, intExpr, tupleExpr, dictExpr, listExpr, setExpr}:
            self.newWarning(isWithALiteral, a)
        elif b.kind in {strExpr, intExpr, tupleExpr, dictExpr, listExpr, setExpr}:
            self.newWarning(isWithALiteral, b)
    if a.kind == intExpr and b.kind == intExpr:
        # Optimizes integer operations
        var x, y, z: int
        discard parseInt(IntExpr(a).literal.lexeme, x)
        discard parseInt(IntExpr(b).literal.lexeme, y)
        try:
            case node.operator.kind:
                of Plus:
                    z = x + y
                of Minus:
                    z = x - y
                of Asterisk:
                    z = x * y
                of FloorDiv:
                    z = int(x / y)
                of DoubleAsterisk:
                    z = x ^ y
                of Percentage:
                    z = x mod y
                of Caret:
                    z = x xor y
                of Ampersand:
                    z = x and y
                of Pipe:
                    z = x or y
                of Slash:
                    # Special case, yields a float
                    return FloatExpr(kind: intExpr, literal: Token(kind: Float, lexeme: $(x / y), line: IntExpr(a).literal.line, pos: (start: -1, stop: -1)))
                else:
                    result = BinaryExpr(kind: binaryExpr, a: a, b: b, operator: node.operator)
        except OverflowDefect:
            self.newWarning(valueOverflow, node)
            return BinaryExpr(kind: binaryExpr, a: a, b: b, operator: node.operator)
        result = IntExpr(kind: intExpr, literal: Token(kind: Integer, lexeme: $z, line: IntExpr(a).literal.line, pos: (start: -1, stop: -1)))
    elif a.kind == floatExpr or b.kind == floatExpr:
        var x, y, z: float
        if a.kind == intExpr:
            var temp: int
            discard parseInt(IntExpr(a).literal.lexeme, temp)
            x = float(temp)
            self.newWarning(implicitConversion, a)
        else:
            discard parseFloat(FloatExpr(a).literal.lexeme, x)
        if b.kind == intExpr:
            var temp: int
            discard parseInt(IntExpr(b).literal.lexeme, temp)
            y = float(temp)
            self.newWarning(implicitConversion, b)
        else:
            discard parseFloat(FloatExpr(b).literal.lexeme, y)
        # Optimizes float operations
        try:
            case node.operator.kind:
                of Plus:
                    z = x + y
                of Minus:
                    z = x - y
                of Asterisk:
                    z = x * y
                of FloorDiv:
                    z = x / y
                of DoubleAsterisk:
                    z = pow(x, y)
                of Percentage:
                    z = x mod y
                of Slash:
                    z = x / y
                else:
                    result = BinaryExpr(kind: binaryExpr, a: a, b: b, operator: node.operator)
        except OverflowDefect:
            self.newWarning(valueOverflow, node)
            return BinaryExpr(kind: binaryExpr, a: a, b: b, operator: node.operator)
        result = FloatExpr(kind: floatExpr, literal: Token(kind: Float, lexeme: $z, line: LiteralExpr(a).literal.line, pos: (start: -1, stop: -1)))
    elif a.kind == strExpr and b.kind == strExpr:
        var a = StrExpr(a)
        var b = StrExpr(b)
        case node.operator.kind:
            of Plus:
                result = StrExpr(kind: strExpr, literal: Token(kind: String, lexeme: "'" & a.literal.lexeme[1..<(^1)] & b.literal.lexeme[1..<(^1)] & "'", pos: (start: -1, stop: -1)))
            else:
                result = node
    elif a.kind == strExpr and self.optimizeNode(b).kind == intExpr and not (self.warnings.len() > 0 and self.warnings[^1].kind == valueOverflow and self.warnings[^1].node == b):
        var a = StrExpr(a)
        var b = IntExpr(b)
        var bb: int
        discard parseInt(b.literal.lexeme, bb)
        case node.operator.kind:
            of Asterisk:
                result = StrExpr(kind: strExpr, literal: Token(kind: String, lexeme: "'" & a.literal.lexeme[1..<(^1)].repeat(bb) & "'"))
            else:
                result = node
    elif b.kind == strExpr and self.optimizeNode(a).kind == intExpr and not (self.warnings.len() > 0 and self.warnings[^1].kind == valueOverflow and self.warnings[^1].node == a):
        var b = StrExpr(b)
        var a = IntExpr(a)
        var aa: int
        discard parseInt(a.literal.lexeme, aa)
        case node.operator.kind:
            of Asterisk:
                result = StrExpr(kind: strExpr, literal: Token(kind: String, lexeme: "'" & b.literal.lexeme[1..<(^1)].repeat(aa) & "'"))
            else:
                result = node
    else:
        # There's no constant folding we can do!
        result = node


proc optimizeNode(self: Optimizer, node: ASTNode): ASTNode =
    ## Analyzes an AST node and attempts to perform
    ## optimizations on it. If no optimization can be
    ## applied, the same node is returned
    if not self.foldConstants:
        return node
    case node.kind:
        of exprStmt:
            result = newExprStmt(self.optimizeNode(ExprStmt(node).expression))
        of intExpr, hexExpr, octExpr, binExpr, floatExpr, strExpr:
            result = self.optimizeConstant(node)
        of unaryExpr:
            result = self.optimizeUnary(UnaryExpr(node))
        of binaryExpr:
            result = self.optimizeBinary(BinaryExpr(node))
        of groupingExpr:
            # Recursively unnests groups
            result = self.optimizeNode(GroupingExpr(node).expression)
        of callExpr:
            var node = CallExpr(node)
            for i, positional in node.arguments.positionals:
                node.arguments.positionals[i] = self.optimizeNode(positional)
            for i, (key, value) in node.arguments.keyword:
                node.arguments.keyword[i].value = self.optimizeNode(value)
            result = node
        of sliceExpr:
            var node = SliceExpr(node)
            for i, e in node.ends:
                node.ends[i] = self.optimizeNode(e)
            node.slicee = self.optimizeNode(node.slicee)
            result = node
        of tryStmt:
            var node = TryStmt(node)
            node.body = self.optimizeNode(node.body)
            if node.finallyClause != nil:
                node.finallyClause = self.optimizeNode(node.finallyClause)
            if node.elseClause != nil:
                node.elseClause = self.optimizeNode(node.elseClause)
            for i, handler in node.handlers:
                node.handlers[i].body = self.optimizeNode(node.handlers[i].body)
            result = node
        of funDecl:
            var decl = FunDecl(node)
            for i, node in decl.defaults:
                decl.defaults[i] = self.optimizeNode(node)
            result = decl
        of blockStmt:
            var node = BlockStmt(node)
            for i, n in node.code:
                node.code[i] = self.optimizeNode(n)
            result = node
        of varDecl:
            var decl = VarDecl(node)
            decl.value = self.optimizeNode(decl.value)
            result = decl
        of assignExpr:
            var asgn = AssignExpr(node)
            asgn.value = self.optimizeNode(asgn.value)
            result = asgn
        of listExpr:
            var l = ListExpr(node)
            for i, e in l.members:
                l.members[i] = self.optimizeNode(e)
            result = node
        of setExpr:
            var s = SetExpr(node)
            for i, e in s.members:
                s.members[i] = self.optimizeNode(e)
            result = node
        of tupleExpr:
            var t = TupleExpr(node)
            for i, e in t.members:
                t.members[i] = self.optimizeNode(e)
            result = node
        of dictExpr:
            var d = DictExpr(node)
            for i, e in d.keys:
                d.keys[i] = self.optimizeNode(e)
            for i, e in d.values:
                d.values[i] = self.optimizeNode(e)
            result = node
        else:
            result = node


proc optimize*(self: Optimizer, tree: seq[ASTNode]): tuple[tree: seq[ASTNode], warnings: seq[Warning]] =
    ## Runs the optimizer on the given source
    ## tree and returns a new optimized tree
    ## as well as a list of warnings that may
    ## be of interest. The input tree may be
    ## identical to the output tree if no optimization
    ## could be performed. Constant folding can be
    ## turned off by setting foldConstants to false
    ## when initializing the optimizer object
    var newTree: seq[ASTNode] = @[]
    for node in tree:
        newTree.add(self.optimizeNode(node))
    result = (tree: newTree, warnings: self.warnings)