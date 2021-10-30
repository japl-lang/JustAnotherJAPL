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

import strformat

export ast


type
    
    Local = ref object
        name: ASTNode
        isStatic: bool
        isPrivate: bool
        depth: int

    Compiler* = ref object
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

