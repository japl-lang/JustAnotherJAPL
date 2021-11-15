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
import meta/token
import meta/ast
import meta/errors
import meta/bytecode
import ../config
import ../util/multibyte


import strformat
import parseutils
import sequtils


export ast
export bytecode
export token
export multibyte


type    
    Name = ref object
        ## A wrapper around declared names.
        ## Depth indicates to which scope
        ## the variable belongs, zero meaning
        ## the global one. Note that all names
        ## are resolved statically unless the
        ## dynamic specifier is used, hence if
        ## the compiler cannot resolve a name
        ## at compile-time it will error out even
        ## if everything would be fine at runtime
        name: ASTNode
        isStatic: bool
        isPrivate: bool
        depth: int

    Compiler* = ref object
        ## A wrapper around the compiler's state
        chunk: Chunk
        ast: seq[ASTNode]
        enclosing: Compiler
        current: int
        file: string
        names: seq[Name]
        scopeDepth: int
        currentFunction: FunDecl
    

proc initCompiler*(): Compiler =
    ## Initializes a new Compiler object
    new(result)
    result.ast = @[]
    result.current = 0
    result.file = ""
    result.names = @[]
    result.scopeDepth = 0
    result.currentFunction = nil



## Forward declarations
proc expression(self: Compiler, node: ASTNode)



proc peek(self: Compiler, distance: int = 0): ASTNode =
    ## Peeks at the AST node at the given distance.
    ## If the distance is out of bounds, the last
    ## AST node in the tree is returned. A negative
    ## distance may be used to retrieve previously
    ## consumed AST nodes
    if self.ast.high() == -1 or self.current + distance > self.ast.high() or self.current + distance < 0:
        result = self.ast[^1]
    else:
        result = self.ast[self.current + distance]


proc done(self: Compiler): bool =
    ## Returns if the compiler is done
    ## compiling
    result = self.current > self.ast.high()


proc check(self: Compiler, kind: NodeKind): bool =
    ## Returns if the current node is of the
    ## expected kind
    if self.done():
        return false
    return self.peek().kind == kind


proc check(self: Compiler, kinds: openarray[NodeKind]): bool =
    ## Returns if the current node's kind matches any
    ## of the given ones. Bails out at the first match
    for kind in kinds:
        if self.check(kind):
            return true
    return false


proc step(self: Compiler): ASTNode =
    ## Steps to the next node and returns
    ## the consumed one
    result = self.peek()
    if not self.done():
        self.current += 1


proc match(self: Compiler, kind: NodeKind): bool =
    ## Same as self.check(), but it calls self.step()
    ## internally if self.check() returns true
    if self.check(kind):
        discard self.step()
        return true
    return false


proc match(self: Compiler, kinds: openarray[NodeKind]): bool =
    ## Same as match, but can match more than one node
    ## kind at a time
    for kind in kinds:
        if self.match(kind):
            return true
    return false


proc error(self: Compiler, message: string) =
    ## Raises a formatted CompileError exception
    let tok = self.peek().token
    raise newException(CompileError, &"A fatal error occurred while compiling '{self.file}', line {tok.line} at '{tok.lexeme}' -> {message}")


proc emitByte(self: Compiler, byt: OpCode|uint8) =
    ## Emits a single byte, writing it to
    ## the current chunk being compiled
    when DEBUG_TRACE_COMPILER:
        echo &"DEBUG - Compiler: Emitting {$byt}"
    self.chunk.write(uint8 byt, self.peek().token.line)


proc emitBytes(self: Compiler, byt1: OpCode|uint8, byt2: OpCode|uint8) =
    ## Emits multiple bytes instead of a single one, this is useful
    ## to emit operators along with their operands or for multi-byte
    ## instructions that are longer than one byte
    self.emitByte(uint8 byt1)
    self.emitByte(uint8 byt2)


proc emitBytes(self: Compiler, bytarr: array[3, uint8]) =
    ## Handy helper method to write an array of 3 bytes into
    ## the current chunk, calling emitByte on each of its
    ## elements
    self.emitBytes(bytarr[0], bytarr[1])
    self.emitByte(bytarr[2])


proc makeConstant(self: Compiler, val: ASTNode): array[3, uint8] =
    ## Adds a constant to the current chunk's constant table
    ## and returns its index as a 3-byte array of uint8s
    result = self.chunk.addConstant(val)


proc emitConstant(self: Compiler, obj: ASTNode) =
    ## Emits a LoadConstant instruction along
    ## with its operand
    self.emitByte(LoadConstant)
    self.emitBytes(self.makeConstant(obj))


proc literal(self: Compiler, node: ASTNode) =
    ## Emits instructions for literals such
    ## as singletons, strings, numbers and
    ## collections
    case node.kind:
        of trueExpr:
            self.emitByte(OpCode.True)
        of falseExpr:
            self.emitByte(OpCode.False)
        of nilExpr:
            self.emitByte(OpCode.Nil)
        of infExpr:
            self.emitByte(OpCode.Inf)
        of nanExpr:
            self.emitByte(OpCode.Nan)
        of strExpr:
            self.emitConstant(node)
        # The optimizer will emit warning
        # for overflowing numbers. Here, we
        # treat them as errors
        of intExpr:
            var x: int
            var y = IntExpr(node)
            try:
                assert parseInt(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.error("integer value out of range")
            self.emitConstant(y)
        # Even though most likely the optimizer
        # will collapse all these other literals
        # to nodes of kind intExpr, that can be
        # disabled. This also allows us to catch
        # basic overflow errors before running any code
        of hexExpr:
            var x: int
            var y = HexExpr(node)
            try:
                assert parseHex(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.error("integer value out of range")
            self.emitConstant(newIntExpr(Token(lexeme: $x, line: y.token.line, pos: (start: y.token.pos.start, stop: y.token.pos.start + len($x)))))
        of binExpr:
            var x: int
            var y = BinExpr(node)
            try:
                assert parseBin(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.error("integer value out of range")
            self.emitConstant(newIntExpr(Token(lexeme: $x, line: y.token.line, pos: (start: y.token.pos.start, stop: y.token.pos.start + len($x)))))
        of octExpr:
            var x: int
            var y = OctExpr(node)
            try:
                assert parseOct(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.error("integer value out of range")
            self.emitConstant(newIntExpr(Token(lexeme: $x, line: y.token.line, pos: (start: y.token.pos.start, stop: y.token.pos.start + len($x)))))
        of floatExpr:
            var x: float
            var y = FloatExpr(node)
            try:
                assert parseFloat(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.error("floating point value out of range")
            self.emitConstant(y)
        of listExpr:
            var y = ListExpr(node)
            for member in y.members:
                self.expression(member)
            self.emitByte(BuildList)
            self.emitBytes(y.members.len().toTriple())  # 24-bit integer, meaning list literals can have up to 2^24 elements
        of tupleExpr:
            var y = TupleExpr(node)
            for member in y.members:
                self.expression(member)
            self.emitByte(BuildTuple)
            self.emitBytes(y.members.len().toTriple())
        of setExpr:
            var y = SetExpr(node)
            for member in y.members:
                self.expression(member)
            self.emitByte(BuildSet)
            self.emitBytes(y.members.len().toTriple())
        of dictExpr:
            var y = DictExpr(node)
            for (key, value) in zip(y.keys, y.values):
                self.expression(key)
                self.expression(value)
            self.emitByte(BuildDict)
            self.emitBytes(y.keys.len().toTriple())
        else:
            self.error(&"invalid AST node of kind {node.kind} at literal(): {node} (This is an internal error and most likely a bug)")


proc unary(self: Compiler, node: UnaryExpr) =
    ## Compiles unary expressions such as negation or
    ## bitwise inversion
    self.expression(node.a)  # Pushes the operand onto the stack
    case node.operator.kind:
        of Minus:
            self.emitByte(UnaryNegate)
        of Plus:
            discard    # Unary + does nothing
        of TokenType.LogicalNot:
            self.emitByte(OpCode.LogicalNot)
        of Tilde:
            self.emitByte(UnaryNot)
        else:
            self.error(&"invalid AST node of kind {node.kind} at unary(): {node} (This is an internal error and most likely a bug)")


proc binary(self: Compiler, node: BinaryExpr) =
    ## Compiles all binary expressions

    # These two lines prepare the stack by pushing the
    # opcode's operands onto it
    self.expression(node.a)
    self.expression(node.b)
    case node.operator.kind:
        of Plus:
            self.emitByte(BinaryAdd)
        of Minus:
            self.emitByte(BinarySubtract)
        of Asterisk:
            self.emitByte(BinaryMultiply)
        of DoubleAsterisk:
            self.emitByte(BinaryPow)
        of Percentage:
            self.emitByte(BinaryMod)
        of FloorDiv:
            self.emitByte(BinaryFloorDiv)
        of Slash:
            self.emitByte(BinaryDivide)
        of Ampersand:
            self.emitByte(BinaryAnd)
        of Caret:
            self.emitByte(BinaryXor)
        of Pipe:
            self.emitByte(BinaryOr)
        of As:
            self.emitByte(BinaryAs)
        of Is:
            self.emitByte(BinaryIs)
        of IsNot:
            self.emitByte(BinaryIsNot)
        of Of:
            self.emitByte(BinaryOf)
        of RightShift:
            self.emitByte(BinaryShiftRight)
        of LeftShift:
            self.emitByte(BinaryShiftLeft)
        # TODO: In-place operations (requires variables)
        else:
            self.error(&"invalid AST node of kind {node.kind} at binary(): {node} (This is an internal error and most likely a bug)")


proc expression(self: Compiler, node: ASTNode) =
    ## Compiles all expressions
    case node.kind:
        of unaryExpr:
            self.unary(UnaryExpr(node))
        of binaryExpr:
            self.binary(BinaryExpr(node))
        of intExpr, hexExpr, binExpr, octExpr, strExpr, falseExpr, trueExpr, infExpr, nanExpr, floatExpr:
            self.literal(LiteralExpr(node))
        of tupleExpr, setExpr, listExpr:
            self.literal(ListExpr(node))
        of dictExpr:
            self.literal(DictExpr(node))
        else:
            self.error(&"invalid AST node of kind {node.kind} at expression(): {node} (This is an internal error and most likely a bug)")  # TODO


proc statement(self: Compiler, node: ASTNode) =
    ## Compiles all statements
    case self.peek().kind:
        of exprStmt:
            self.expression(ExprStmt(node).expression)
            self.emitByte(Pop)
        else:
            self.error(&"invalid AST node of kind {node.kind} at statement(): {node} (This is an internal error and most likely a bug)")  # TODO


proc declaration(self: Compiler, node: ASTNode) =
    ## Compiles all declarations
    case node.kind:
        of classDecl, funDecl:
            discard  # TODO
        else:
            self.statement(node)


proc compile*(self: Compiler, ast: seq[ASTNode], file: string): Chunk =
    ## Compiles a sequence of AST nodes into a chunk
    ## object
    self.chunk = newChunk()
    self.ast = ast
    self.file = file
    self.names = @[]
    self.scopeDepth = 0
    self.currentFunction = nil
    self.current = 0
    while not self.done():
        self.declaration(self.step())
    if self.ast.len() > 0:
        # *Technically* an empty program is a valid program
        self.emitByte(OpCode.Return)   # Exits the VM's main loop when used at the global scope
    result = self.chunk
