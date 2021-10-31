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

export ast


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
    

proc newCompiler*(): Compiler =
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
    result = self.current >= self.ast.high()


proc step(self: Compiler): ASTNode =
    ## Steps n nodes into the input,
    ## returning the last consumed one
    result = self.peek()
    if not self.done():
        self.current += 1


proc error(self: Compiler, message: string) =
    ## Raises a formatted CompileError exception
    var errorMessage: string
    case self.peek().kind:
        of floatExpr, intExpr, identExpr:
            errorMessage = &"A fatal error occurred while compiling '{self.file}', line {LiteralExpr(self.peek()).literal.line} at '{LiteralExpr(self.peek()).literal.lexeme}' -> {message}"
        else:
            discard
    raise newException(CompileError, errorMessage)


proc emitByte(self: Compiler, byt: OpCode|uint8) =
    ## Emits a single bytecode instruction and writes it
    ## to the current chunk being compiled
    when DEBUG_TRACE_COMPILER:
        stdout.write(&"DEBUG - Compiler: Emitting {$byt} (uint8 value of {$(uint8 byt)}")
        if byt.int() <= OpCode.high().int():
          stdout.write(&"; opcode value of {$byt.OpCode}")
        stdout.write(")\n")
    self.chunk.write(uint8 byt, self.peek().token.line)


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


proc compile*(self: Compiler, ast: seq[ASTNode], file: string): Chunk =
    self.chunk = newChunk()
    self.ast = ast
    self.file = file
    self.locals = @[]
    self.scopeDepth = 0
    self.currentFunction = nil
    result = self.chunk