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
import algorithm
import parseutils
import sequtils


export ast
export bytecode
export token
export multibyte


type
    Name = ref object
        ## A compile-time wrapper around 
        ## statically resolved names.
        ## Depth indicates to which scope
        ## the variable belongs, zero meaning
        ## the global one
        name: IdentExpr
        owner: string
        depth: int
        isPrivate: bool
        isConst: bool
    
    Loop = object
        ## A "loop object" used
        ## by the compiler to emit
        ## appropriate jump offsets
        ## for continue and break
        ## statements
        start: int
        stop: int

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
        enableOptimizations*: bool
        currentLoop: Loop
    

proc initCompiler*(enableOptimizations: bool = true): Compiler =
    ## Initializes a new Compiler object
    new(result)
    result.ast = @[]
    result.current = 0
    result.file = ""
    result.names = @[]
    result.scopeDepth = 0
    result.currentFunction = nil
    result.enableOptimizations = enableOptimizations



## Forward declarations
proc expression(self: Compiler, node: ASTNode)
proc statement(self: Compiler, node: ASTNode)
proc declaration(self: Compiler, node: ASTNode)
proc peek(self: Compiler, distance: int = 0): ASTNode
## End of forward declarations



## Utility functions

proc error(self: Compiler, message: string) =
    ## Raises a formatted CompileError exception
    let tok = self.peek().token
    raise newException(CompileError, &"A fatal error occurred while compiling '{self.file}', line {tok.line} at '{tok.lexeme}' -> {message}")


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
    ## Returns true if the compiler is done
    ## compiling, false otherwise
    result = self.current > self.ast.high()


proc step(self: Compiler): ASTNode =
    ## Steps to the next node and returns
    ## the consumed one
    result = self.peek()
    if not self.done():
        self.current += 1


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


proc emitBytes(self: Compiler, bytarr: array[2, uint8]) =
    ## Handy helper method to write an array of 2 bytes into
    ## the current chunk, calling emitByte on each of its
    ## elements
    self.emitBytes(bytarr[0], bytarr[1])


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


proc identifierConstant(self: Compiler, identifier: IdentExpr): array[3, uint8] =
    ## Emits an identifier name as a string in the current chunk's constant
    ## table. This is used to load globals declared as dynamic that cannot
    ## be resolved statically by the compiler
    try:
        result = self.makeConstant(identifier)
    except CompileError:
        self.error(getCurrentExceptionMsg())


proc emitJump(self: Compiler, opcode: OpCode): int =
    ## Emits a dummy jump offset to be patched later. Assumes
    ## the largest offset (emits 4 bytes, one for the given jump
    ## opcode, while the other 3 are for the jump offset which is set
    ## to the maximum unsigned 24 bit integer). If the shorter
    ## 16 bit alternative is later found to be better suited, patchJump
    ## will fix this. This function returns the absolute index into the
    ## chunk's bytecode array where the given placeholder instruction was written
    self.emitByte(opcode)
    self.emitBytes((16777215).toTriple())
    result = self.chunk.code.len() - 4


proc patchJump(self: Compiler, offset: int) =
    ## Patches a previously emitted jump
    ## using emitJump. Since emitJump assumes
    ## a long jump, this also shrinks the jump
    ## offset and changes the bytecode instruction if possible
    ## (i.e. jump is in 16 bit range), but the converse is also
    ## true (i.e. it might change a regular jump into a long one)
    let jump: int = self.chunk.code.len() - offset - 4
    if jump > 16777215:
        self.error("cannot jump more than 16777215 bytecode instructions")
    if jump < uint16.high().int:
        case OpCode(self.chunk.code[offset]):
            of LongJumpForwards:
                self.chunk.code[offset] = JumpForwards.uint8()
            of LongJumpBackwards:
                self.chunk.code[offset] = JumpBackwards.uint8()
            of LongJumpIfFalse:
                self.chunk.code[offset] = JumpIfFalse.uint8()
            of LongJumpIfFalsePop:
                self.chunk.code[offset] = JumpIfFalsePop.uint8()     
            else:
                discard  # Unreachable
        self.chunk.code.delete(offset + 1)   # Discards the first byte of the 24 bit integer
        let offsetArray = jump.toDouble()
        self.chunk.code[offset + 1] = offsetArray[0]
        self.chunk.code[offset + 2] = offsetArray[1]
    else:
        case OpCode(self.chunk.code[offset]):
            of JumpForwards:
                self.chunk.code[offset] = LongJumpForwards.uint8()
            of JumpBackwards:
                self.chunk.code[offset] = LongJumpBackwards.uint8()
            of JumpIfFalse:
                self.chunk.code[offset] = LongJumpIfFalse.uint8()
            of JumpIfFalsePop:
                self.chunk.code[offset] = LongJumpIfFalsePop.uint8()     
            else:
                discard  # Unreachable
        let offsetArray = jump.toTriple()
        self.chunk.code[offset + 1] = offsetArray[0]
        self.chunk.code[offset + 2] = offsetArray[1]
        self.chunk.code[offset + 3] = offsetArray[2]

## End of utility functions

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
        of TokenType.LessThan:
            self.emitByte(OpCode.LessThan)
        of TokenType.GreaterThan:
            self.emitByte(OpCode.GreaterThan)
        of TokenType.DoubleEqual:
            self.emitByte(EqualTo)
        of TokenType.LessOrEqual:
            self.emitByte(OpCode.LessOrEqual)
        of TokenType.GreaterOrEqual:
            self.emitByte(OpCode.GreaterOrEqual)
        of TokenType.LogicalAnd:
            self.expression(node.a)
            let jump = self.emitJump(JumpIfFalse)
            self.emitByte(Pop)
            self.expression(node.b)
            self.patchJump(jump)
        of TokenType.LogicalOr:
            self.expression(node.a)
            let jump = self.emitJump(JumpIfTrue)
            self.expression(node.b)
            self.patchJump(jump)
        # TODO: In-place operations
        else:
            self.error(&"invalid AST node of kind {node.kind} at binary(): {node} (This is an internal error and most likely a bug)")


proc declareName(self: Compiler, node: ASTNode) =
    ## Compiles all name declarations (constants, static,
    ## and dynamic)
    case node.kind:
        of varDecl:
            var node = VarDecl(node)
            if not node.isStatic:
                # This emits code for dynamically-resolved variables (i.e. globals declared as dynamic and unresolvable names)
                self.emitByte(DeclareName)
                self.emitBytes(self.identifierConstant(IdentExpr(node.name)))
            else:
                # Statically resolved variable here. Only creates a new StaticName entry
                # so that self.identifier (and, by extension, self.getStaticIndex) emit the
                # proper stack offset
                if self.names.high() > 16777215:
                    # If someone ever hits this limit in real-world scenarios, I swear I'll
                    # slap myself 100 times with a sign saying "I'm dumb". Mark my words
                    self.error("cannot declare more than 16777215 static variables at a time")
                self.names.add(Name(depth: self.scopeDepth, name: IdentExpr(node.name),
                                                isPrivate: node.isPrivate, owner: node.owner, isConst: node.isConst))
        else:
            discard  # TODO: Classes, functions

    
proc varDecl(self: Compiler, node: VarDecl) = 
    ## Compiles variable declarations
    self.expression(node.value)
    self.declareName(node)


proc resolveStatic(self: Compiler, name: IdentExpr, depth: int = self.scopeDepth): Name =
    ## Traverses self.staticNames backwards and returns the
    ## first name object with the given name at the given
    ## depth. The default depth is the current one. Returns
    ## nil when the name can't be found. This helper function
    ## is only useful when detecting a few errors and edge
    ## cases
    for obj in reversed(self.names):
        if obj.name.token.lexeme == name.token.lexeme and obj.depth == depth:
            return obj
    return nil


proc getStaticIndex(self: Compiler, name: IdentExpr): int =
    ## Gets the predicted stack position of the given variable
    ## if it is static, returns -1 if it is to be bound dynamically
    var i: int = self.names.high()
    for variable in reversed(self.names):
        if name.name.lexeme == variable.name.name.lexeme:
            return i
        dec(i)
    return -1


proc identifier(self: Compiler, node: IdentExpr) =
    ## Compiles access to identifiers
    let s = self.resolveStatic(node)
    if s != nil and s.isConst:
        # Constants are emitted as, you guessed it, constant instructions
        # no matter the scope depth. Also, name resolution specifiers do not
        # apply to them (because what would it mean for a constant to be dynamic
        # anyway?)
        self.emitConstant(node)
    else:
        let index = self.getStaticIndex(node)
        if index != -1:
            self.emitByte(LoadFast)   # Static name resolution
            self.emitBytes(index.toTriple())
        else:
            self.emitByte(LoadName)
            self.emitBytes(self.identifierConstant(node))


proc assignment(self: Compiler, node: ASTNode) =
    ## Compiles assignment expressions
    case node.kind:
        of assignExpr:
            var node = AssignExpr(node)
            var name = IdentExpr(node.name)
            let r = self.resolveStatic(name)
            if r != nil and r.isConst:
                self.error("cannot assign to constant")
            # Assignment only encompasses variable assignments
            # so we can ensure the name is a constant
            self.expression(node.value)
            let index = self.getStaticIndex(name)
            if index != -1:
                self.emitByte(UpdateFast)
                self.emitBytes(index.toTriple())
            else:
                self.emitByte(UpdateName)
                self.emitBytes(self.makeConstant(name))
        of setItemExpr:
            discard
            # TODO
        else:
            self.error(&"invalid AST node of kind {node.kind} at assignment(): {node} (This is an internal error and most likely a bug)")


proc beginScope(self: Compiler) =
    ## Begins a new local scope by incrementing the current
    ## scope's depth
    inc(self.scopeDepth)


proc endScope(self: Compiler) = 
    ## Ends the current local scope
    if self.scopeDepth < 0:
        self.error("cannot call endScope with scopeDepth < 0 (This is an internal error and most likely a bug)")
    var popped: int = 0
    for ident in reversed(self.names):
        if not self.enableOptimizations:
            if ident.depth > self.scopeDepth:
                # All variables with a scope depth larger than the current one
                # are now out of scope. Begone, you're now homeless!
                self.emitByte(Pop)
        inc(popped)
    if self.enableOptimizations and popped > 1:
        # If we're popping less than 65535 variables, then
        # we can emit a PopN instruction. This is true for
        # 99.99999% of the use cases of the language (who the
        # hell is going to use 65 THOUSAND local variables?), but
        # if you'll ever use more then JAPL will emit a PopN instruction
        # for the first 65 thousand and change local variables and then
        # emit another batch of plain ol' Pop instructions for the rest
        if popped <= uint16.high().int():
            self.emitByte(PopN)
            self.emitBytes(popped.toTriple())
        else:
            self.emitByte(PopN)
            self.emitBytes(uint16.high().int.toTriple())
            for i in countdown(self.names.high(), popped - uint16.high().int()):
                if self.names[i].depth > self.scopeDepth:
                    self.emitByte(Pop)
    elif popped == 1:
        # We only emit PopN if we're popping more than one value
        self.emitByte(Pop)
    for _ in countup(0, popped - 1):
        discard self.names.pop()
    dec(self.scopeDepth)


proc blockStmt(self: Compiler, node: BlockStmt) =
    ## Compiles block statements, which create a new
    ## local scope.
    self.beginScope()
    for decl in node.code:
        self.declaration(decl)
    self.endScope()


proc ifStmt(self: Compiler, node: IfStmt) =
    ## Compiles if/else statements for conditional
    ## execution of code
    self.expression(node.condition)
    var jumpCode: OpCode
    if self.enableOptimizations:
        jumpCode = JumpIfFalsePop
    else:
        jumpCode = JumpIfFalse
    let jump = self.emitJump(jumpCode)
    if not self.enableOptimizations:
        self.emitByte(Pop)
    self.statement(node.thenBranch)
    self.patchJump(jump)
    if node.elseBranch != nil:
        let jump = self.emitJump(JumpForwards)
        self.statement(node.elseBranch)
        self.patchJump(jump)


proc emitLoop(self: Compiler, begin: int) =
    ## Emits a JumpBackwards instruction with the correct
    ## jump offset
    var offset: int
    case OpCode(self.chunk.code[begin + 1]):   # The jump instruction
        of LongJumpForwards, LongJumpBackwards, LongJumpIfFalse, LongJumpIfFalsePop, LongJumpIfTrue:
            offset = self.chunk.code.len() - begin + 4
        else:
            offset = self.chunk.code.len() - begin
    if offset > uint16.high().int:
        if offset > 16777215:
            self.error("cannot jump more than 16777215 bytecode instructions")
        self.emitByte(LongJumpBackwards)
        self.emitBytes(offset.toTriple())
    else:
        self.emitByte(JumpBackwards)
        self.emitBytes(offset.toDouble())
    

proc whileStmt(self: Compiler, node: WhileStmt) =
    ## Compiles C-style while loops
    let start = self.chunk.code.len()
    self.expression(node.condition)
    let jump = self.emitJump(JumpIfFalsePop)
    self.statement(node.body)
    self.patchJump(jump)
    self.emitLoop(start)


proc expression(self: Compiler, node: ASTNode) =
    ## Compiles all expressions
    case node.kind:
        of getItemExpr:
            discard
        # Note that for setItem and assign we don't convert
        # the node to its true type because that type information
        # would be lost in the call anyway. The differentiation
        # happens in self.assignment
        of setItemExpr, assignExpr:
            self.assignment(node)
        of identExpr:
            self.identifier(IdentExpr(node))
        of unaryExpr:
            # Unary expressions such as ~5 and -3
            self.unary(UnaryExpr(node))
        of groupingExpr:
            self.expression(GroupingExpr(node).expression)
        of binaryExpr:
            # Binary expressions such as 2 ^ 5 and 0.66 * 3.14
            self.binary(BinaryExpr(node))
        of intExpr, hexExpr, binExpr, octExpr, strExpr, falseExpr, trueExpr, infExpr, nanExpr, floatExpr, nilExpr:
            # Fortunately for us, all of these AST nodes types inherit from the base LiteralExpr
            # type
            self.literal(LiteralExpr(node))
        of tupleExpr, setExpr, listExpr:
            # Since all of these AST nodes share
            # the same structure, and the kind
            # discriminant is enough to tell one
            # from the other, why bother with
            # specialized cases when one is enough?
            self.literal(ListExpr(node))
        of dictExpr:
            self.literal(DictExpr(node))
        else:
            self.error(&"invalid AST node of kind {node.kind} at expression(): {node} (This is an internal error and most likely a bug)")  # TODO


proc statement(self: Compiler, node: ASTNode) =
    ## Compiles all statements
    case node.kind:
        of exprStmt:
            self.expression(ExprStmt(node).expression)
            self.emitByte(Pop)   # Expression statements discard their value. Their main use case is side effects in function calls
        # TODO
        of NodeKind.ifStmt:
            self.ifStmt(IfStmt(node))
        of delStmt:
            discard
        of assertStmt:
            discard
        of raiseStmt:
            discard
        of breakStmt:
            discard
        of continueStmt:
            discard
        of returnStmt:
            discard
        of importStmt:
            discard
        of fromImportStmt:
            discard
        of NodeKind.whileStmt, NodeKind.forStmt:
            ## Our parser already desugars for loops to
            ## while loops anyway
            self.whileStmt(WhileStmt(node))
        of forEachStmt:
            discard
        of NodeKind.blockStmt:
            self.blockStmt(BlockStmt(node))
        of NodeKind.yieldStmt:
            discard
        of NodeKind.awaitStmt:
            discard
        of NodeKind.deferStmt:
            discard
        of NodeKind.tryStmt:
            discard 
        else:
            self.error(&"invalid AST node of kind {node.kind} at statement(): {node} (This is an internal error and most likely a bug)")  # TODO


proc declaration(self: Compiler, node: ASTNode) =
    ## Compiles all declarations
    case node.kind:
        of NodeKind.varDecl:
            self.varDecl(VarDecl(node))
        of funDecl, classDecl:
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
        self.endScope()
        self.emitByte(OpCode.Return)   # Exits the VM's main loop when used at the global scope
    result = self.chunk
    if self.scopeDepth != -1:
        self.error(&"internal error: invalid scopeDepth state (expected -1, got {self.scopeDepth}), did you forget to call endScope/beginScope?")
