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

## Low level bytecode implementation details
import ast
import ../../util/multibyte
import errors

import strutils
import strformat


export ast


type
    Chunk* = ref object
        ## A piece of bytecode.
        ## Consts represents the constants table the code is referring to.
        ## Code is the linear sequence of compiled bytecode instructions.
        ## Lines maps bytecode instructions to line numbers using Run
        ## Length Encoding. Instructions are encoded in groups whose structure
        ## follows the following schema:
        ## - The first integer represents the line number
        ## - The second integer represents the count of whatever comes after it
        ##  (let's call it c)
        ## - After c, a sequence of c integers follows
        ##
        ## A visual representation may be easier to understand: [1, 2, 3, 4]
        ## This is to be interpreted as "there are 2 instructions at line 1 whose values
        ## are 3 and 4"
        ## This is more efficient than using the naive approach, which would encode
        ## the same line number multiple times and waste considerable amounts of space.
        consts*: seq[ASTNode]
        code*: seq[uint8]
        lines*: seq[int]
        reuseConsts*: bool

    OpCode* {.pure.} = enum
        ## Enum of possible opcodes.

        # Note: x represents the
        # argument to unary opcodes, while
        # a and b represent arguments to binary
        # opcodes. Other variable names may be
        # used for more complex opcodes. All
        # arguments to opcodes (if they take
        # arguments) come from popping off the
        # stack. Unsupported operations will
        # raise TypeError or ValueError exceptions
        # and never fail silently
        LoadConstant = 0u8, # Pushes constant at position x in the constant table onto the stack
        ## Binary operators
        UnaryNegate,        # Pushes the result of -x onto the stack
        BinaryAdd,          # Pushes the result of a + b onto the stack
        BinarySubtract,     # Pushes the result of a - b onto the stack
        BinaryDivide,       # Pushes the result of a / b onto the stack (true division). The result is a float
        BinaryFloorDiv,     # Pushes the result of a // b onto the stack (integer division). The result is always an integer
        BinaryMultiply,     # Pushes the result of a * b onto the stack
        BinaryPow,          # Pushes the result of a ** b (a to the power of b) onto the stack
        BinaryMod,          # Pushes the result of a % b onto the stack (modulo division)
        BinaryShiftRight,   # Pushes the result of a >> b (a with bits shifted b times to the right) onto the stack
        BinaryShiftLeft,    # Pushes the result of a << b (a with bits shifted b times to the left) onto the stack
        BinaryXor,          # Pushes the result of a ^ b (bitwise exclusive or) onto the stack
        BinaryOr,           # Pushes the result of a | b (bitwise or) onto the stack
        BinaryAnd,          # Pushes the result of a & b (bitwise and) onto the stack
        UnaryNot,           # Pushes the result of ~x (bitwise not) onto the stack
        BinaryAs,           # Pushes the result of a as b onto the stack (converts a to the type of b. Explicit support from a is required)
        BinaryIs,           # Pushes the result of a is b onto the stack (true if a and b point to the same object, false otherwise)
        BinaryIsNot,        # Pushes the result of not (a is b). This could be implemented in terms of BinaryIs, but it's more efficient this way
        BinaryOf,           # Pushes the result of a of b onto the stack (true if a is a subclass of b, false otherwise)
        BinarySlice,        # Perform slicing on supported objects (like "hello"[0:2], which yields "he"). The result is pushed onto the stack
        BinarySubscript,    # Subscript operator, like "hello"[0] (which pushes 'h' onto the stack)
        ## Binary comparison operators
        GreaterThan,        # Pushes the result of a > b onto the stack
        LessThan,           # Pushes the result of a < b onto the stack
        EqualTo,            # Pushes the result of a == b onto the stack
        NotEqualTo,         # Pushes the result of a != b onto the stack (optimization for not (a == b))
        GreaterOrEqual,     # Pushes the result of a >= b onto the stack
        LessOrEqual,        # Pushes the result of a <= b onto the stack
        ## Logical operators
        LogicalNot,  # Pushes true if 
        LogicalAnd,
        LogicalOr,
        ## Constant opcodes (each of them pushes a singleton on the stack)
        Nil,
        True,
        False,
        Nan,
        Inf,
        ## Basic stack operations
        Pop,                # Pops an element off the stack and discards it
        Push,               # Pushes x onto the stack
        PopN,               # Pops x elements off the stack (optimization for exiting scopes and returning from functions)
        ## Name resolution/handling
        LoadAttribute,
        DeclareName,        # Declares a global dynamically bound name in the current scope
        LoadName,           # Loads a dynamically bound variable
        LoadFast,           # Loads a statically bound variable
        StoreName,          # Sets/updates a dynamically bound variable's value
        StoreFast,          # Sets/updates a statically bound variable's value
        DeleteName,         # Unbinds a dynamically bound variable's name from the current scope
        DeleteFast,         # Unbinds a statically bound variable's name from the current scope
        LoadHeap,           # Loads a closed-over variable
        StoreHeap,          # Stores a closed-over variable
        ## Looping and jumping
        Jump,               # Absolute, unconditional jump into the bytecode
        JumpIfFalse,        # Jumps to an absolute index in the bytecode if the value at the top of the stack is falsey
        JumpIfTrue,         # Jumps to an absolute index in the bytecode if the value at the top of the stack is truthy
        JumpIfFalsePop,     # Like JumpIfFalse, but it also pops off the stack (regardless of truthyness). Optimization for if statements
        JumpIfFalseOrPop,   # Jumps to an absolute index in the bytecode if the value at the top of the stack is falsey and pops it otherwise
        JumpForwards,       # Relative, unconditional, positive jump in the bytecode
        JumpBackwards,      # Relative, unconditional, negative jump into the bytecode
        Break,              # Temporary opcode used to signal exiting out of loops
        ## Long variants of jumps (they use a 24-bit operand instead of a 16-bit one)
        LongJump,
        LongJumpIfFalse,
        LongJumpIfTrue,
        LongJumpIfFalsePop,
        LongJumpIfFalseOrPop,
        LongJumpForwards,
        LongJumpBackwards,
        ## Functions
        Call,               # Calls a callable object
        Return              # Returns from the current function
        ## Exception handling
        Raise,              # Raises exception x
        ReRaise,            # Re-raises active exception
        BeginTry,           # Initiates an exception handling context
        FinishTry,          # Closes the current exception handling context
        ## Generators
        Yield,
        ## Coroutines
        Await,
        ## Collection literals
        BuildList,
        BuildDict,
        BuildSet,
        BuildTuple,
        ## Misc
        Assert,
        MakeClass,
        Slice,              # Slices an object (takes 3 arguments: start, stop, step) and pushes the result of a.subscript(b, c, d) onto the stack
        GetItem,            # Pushes the result of a.getItem(b)


# We group instructions by their operation/operand types for easier handling when debugging

# Simple instructions encompass:
# - Instructions that push onto/pop off the stack unconditionally (True, False, Pop, etc.)
# - Unary and binary operators
const simpleInstructions* = {Return, BinaryAdd, BinaryMultiply,
                             BinaryDivide, BinarySubtract,
                             BinaryMod, BinaryPow, Nil,
                             True, False, OpCode.Nan, OpCode.Inf,
                             BinaryShiftLeft, BinaryShiftRight,
                             BinaryXor, LogicalNot, EqualTo,
                             GreaterThan, LessThan, LoadAttribute,
                             BinarySlice, Pop, UnaryNegate,
                             BinaryIs, BinaryAs, GreaterOrEqual,
                             LessOrEqual, BinaryOr, BinaryAnd,
                             UnaryNot, BinaryFloorDiv, BinaryOf, Raise,
                             ReRaise, BeginTry, FinishTry, Yield, Await,
                             MakeClass}

# Constant instructions are instructions that operate on the bytecode constant table
const constantInstructions* = {LoadConstant, DeclareName, LoadName, StoreName, DeleteName}

# Stack triple instructions operate on the stack at arbitrary offsets and pop arguments off of it in the form
# of 24 bit integers
const stackTripleInstructions* = {Call, StoreFast, DeleteFast, LoadFast}

# Stack double instructions operate on the stack at arbitrary offsets and pop arguments off of it in the form
# of 16 bit integers
const stackDoubleInstructions* = {}

# Argument double argument instructions take hardcoded arguments on the stack as 16 bit integers
const argumentDoubleInstructions* = {PopN, }

# Jump instructions jump at relative or absolute bytecode offsets
const jumpInstructions* = {JumpIfFalse, JumpIfFalsePop, JumpForwards, JumpBackwards,
                           LongJumpIfFalse, LongJumpIfFalsePop, LongJumpForwards,
                           LongJumpBackwards, JumpIfTrue, LongJumpIfTrue}

# Collection instructions push a built-in collection type onto the stack
const collectionInstructions* = {BuildList, BuildDict, BuildSet, BuildTuple}


proc newChunk*(reuseConsts: bool = true): Chunk =
    ## Initializes a new, empty chunk
    result = Chunk(consts: @[], code: @[], lines: @[], reuseConsts: reuseConsts)


proc `$`*(self: Chunk): string = &"""Chunk(consts=[{self.consts.join(", ")}], code=[{self.code.join(", ")}], lines=[{self.lines.join(", ")}])"""


proc write*(self: Chunk, newByte: uint8, line: int) =
    ## Adds the given instruction at the provided line number
    ## to the given chunk object
    assert line > 0, "line must be greater than zero"
    if self.lines.high() >= 1 and self.lines[^2] == line:
        self.lines[^1] += 1
    else:
        self.lines.add(line)
        self.lines.add(1)
    self.code.add(newByte)


proc write*(self: Chunk, bytes: openarray[uint8], line: int) =
    ## Calls write in a loop with all members of the given
    ## array
    for cByte in bytes:
        self.write(cByte, line)


proc write*(self: Chunk, newByte: OpCode, line: int) =
    ## Adds the given instruction at the provided line number
    ## to the given chunk object
    self.write(uint8(newByte), line)


proc write*(self: Chunk, bytes: openarray[OpCode], line: int) =
    ## Calls write in a loop with all members of the given
    ## array
    for cByte in bytes:
        self.write(uint8(cByte), line)


proc getLine*(self: Chunk, idx: int): int =
    ## Returns the associated line of a given
    ## instruction index
    if self.lines.len < 2:
        raise newException(IndexDefect, "the chunk object is empty")
    var
        count: int
        current: int = 0
    for n in countup(0, self.lines.high(), 2):
        count = self.lines[n + 1]
        if idx in current - count..<current + count:
            return self.lines[n]
        current += count
    raise newException(IndexDefect, "index out of range")


proc findOrAddConstant(self: Chunk, constant: ASTNode): int =
    ## Small optimization function that reuses the same constant
    ## if it's already been written before (only if self.reuseConsts
    ## equals true)
    if self.reuseConsts:
        for i, c in self.consts:
            # We cannot use simple equality because the nodes likely have
            # different token objects with different values
            if c.kind != constant.kind:
                continue
            if constant.isConst():
                var c = LiteralExpr(c)
                var constant = LiteralExpr(constant)
                if c.literal.lexeme == constant.literal.lexeme:
                    # This wouldn't work for stuff like 2e3 and 2000.0, but those
                    # forms are collapsed in the compiler before being written
                    # to the constants table
                    return i
            elif constant.kind == identExpr:
                var c = IdentExpr(c)
                var constant = IdentExpr(constant)
                if c.name.lexeme == constant.name.lexeme:
                    return i
            else:
                continue
    self.consts.add(constant)
    result = self.consts.high()


proc addConstant*(self: Chunk, constant: ASTNode): array[3, uint8] =
    ## Writes a constant to a chunk. Returns its index casted to a 3-byte
    ## sequence (array). Constant indexes are reused if a constant is used
    ## more than once and self.reuseConsts equals true
    if self.consts.len() == 16777215:
        # The constant index is a 24 bit unsigned integer, so that's as far
        # as we can index into the constant table (the same applies
        # to our stack by the way). Not that anyone's ever gonna hit this
        # limit in the real world, but you know, just in case
        raise newException(CompileError, "cannot encode more than 16777215 constants")
    result = self.findOrAddConstant(constant).toTriple()
