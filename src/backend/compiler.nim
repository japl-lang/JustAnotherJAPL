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
import meta/ast
import meta/errors
import meta/bytecode
import ../config


import strformat
import parseutils


export ast
export bytecode


type
    
    Local = ref object
        name: ASTNode
        isStatic: bool
        isPrivate: bool
        depth: int

    Compiler* = ref object
        chunk: Chunk
        ast: seq[ASTNode]
        enclosing: Compiler
        current: int
        file: string
        locals: seq[Local]
        scopeDepth: int
        currentFunction: FunDecl
    

proc initCompiler*(): Compiler =
    ## Initializes a new Compiler object
    new(result)
    result.ast = @[]
    result.current = 0
    result.file = ""
    result.locals = @[]
    result.scopeDepth = 0
    result.currentFunction = nil


proc peek(self: Compiler, distance: int = 0): ASTNode =
    ## Peeks at the AST node at the given distance.
    ## If the distance is out of bounds, a nil
    ## AST node is returned. A negative distance may
    ## be used to retrieve previously consumed
    ## AST nodes
    if self.ast.high() == -1 or self.current + distance > self.ast.high() or self.current + distance < 0:
        result = nil
    else:
        result = self.ast[self.current + distance]


proc done(self: Compiler): bool =
    ## Returns if the compiler is done
    ## compiling
    result = self.current > self.ast.high()


proc step(self: Compiler): ASTNode =
    ## Steps n nodes into the input,
    ## returning the last consumed one
    result = self.peek()
    if not self.done():
        self.current += 1


proc error(self: Compiler, message: string) =
    ## Raises a formatted CompileError exception
    let tok = if not self.done(): self.peek().token else: self.peek(-1).token
    raise newException(CompileError, &"A fatal error occurred while compiling '{self.file}', line {tok.line} at '{tok.lexeme}' -> {message}")


proc emitByte(self: Compiler, byt: OpCode|uint8) =
    ## Emits a single bytecode instruction and writes it
    ## to the current chunk being compiled
    when DEBUG_TRACE_COMPILER:
        echo &"DEBUG - Compiler: Emitting {$byt}"
    self.chunk.write(uint8 byt, self.peek(-1).token.line)


proc emitBytes(self: Compiler, byt1: OpCode|uint8, byt2: OpCode|uint8) =
    ## Emits multiple bytes instead of a single one, this is useful
    ## to emit operators along with their operands or for multi-byte
    ## instructions that are longer than one byte
    self.emitByte(uint8 byt1)
    self.emitByte(uint8 byt2)


proc emitBytes(self: Compiler, bytarr: array[3, uint8]) =
    ## Handy helper method to write an array of 3 bytes into
    ## the current chunk, calling emiteByte(s) on each of its
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


proc literal(self: Compiler) =
    ## Emits instructions for literals such
    ## as singletons, strings, numbers and
    ## collections
    if self.peek().kind != NodeKind.exprStmt or not ExprStmt(self.peek()).expression.isLiteral():
        self.error(&"invalid or corrupted AST node '{self.peek()}' ({self.peek().kind})")
    let stomp = LiteralExpr(ExprStmt(self.step()).expression)
    case stomp.kind:
        of trueExpr:
            self.emitByte(True)
        of falseExpr:
            self.emitByte(False)
        of nilExpr:
            self.emitByte(Nil)
        of infExpr:
            self.emitByte(OpCode.Inf)
        of nanExpr:
            self.emitByte(OpCode.Nan)
        # The optimizer will emit warning
        # for overflowing numbers. Here, we
        # treat them as errors
        of intExpr:
            var x: int
            var y = IntExpr(stomp)
            try:
                assert parseInt(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.error("integer value out of range")
            self.emitConstant(y)
        # Even though most likely the optimizer
        # will collapse all these other literals
        # to nodes of kind intExpr, that can be
        # disabled. This also allows us to catch
        # overflow errors before running any code
        of hexExpr:
            var x: int
            var y = HexExpr(stomp)
            try:
                assert parseHex(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.error("integer value out of range")
            self.emitConstant(y)
        of binExpr:
            var x: int
            var y = BinExpr(stomp)
            try:
                assert parseBin(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.error("integer value out of range")
        of octExpr:
            var x: int
            var y = OctExpr(stomp)
            try:
                assert parseOct(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.error("integer value out of range")
        of floatExpr:
            var x: float
            var y = FloatExpr(stomp)
            try:
                assert parseFloat(y.literal.lexeme, x) == len(y.literal.lexeme)
            except ValueError:
                self.error("floating point value out of range")             
        else:
            discard


proc expression(self: Compiler) =
    self.literal()


proc expressionStatement(self: Compiler) =
    self.expression()


proc statement(self: Compiler) =
    self.expressionStatement()


proc declaration(self: Compiler) =
    self.statement()


proc compile*(self: Compiler, ast: seq[ASTNode], file: string): Chunk =
    self.chunk = newChunk()
    self.ast = ast
    self.file = file
    self.locals = @[]
    self.scopeDepth = 0
    self.currentFunction = nil
    self.current = 0
    while not self.done():
        self.declaration()
        self.current += 1
    result = self.chunk