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
import ast
import ../../util/multibyte


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

    OpCode* {.pure.} = enum
        ## Enum of possible opcodes.

        # Note: x represents the
        # argument to unary opcodes, while
        # a and b represent arguments to binary
        # opcodes. Other variable names may be
        # used for more complex opcodes        
        LoadConstant = 0u8,  # Pushes constant at position x in the constant table onto the stack
        # Binary operators
        UnaryNegate,  # Pushes the result of -x onto the stack
        BinaryAdd,    # Pushes the result of a + b onto the stack
        BinarySubtract,  # Pushes the result of a - b onto the stack
        BinaryDivide,    # Pushes the result of a / b onto the stack (true division). The result is a float
        BinaryFloorDiv,  # Pushes the result of a // b onto the stack (integer division). The result is always an integer
        BinaryMultiply,  # Pushes the result of a * b onto the stack
        BinaryPow,    # Pushes the result of a ** b (a to the power of b) onto the stack
        BinaryMod,  # Pushes the result of a % b onto the stack (modulo division)
        BinaryShiftRight,  # Pushes the result of a >> b (a with bits shifted b times to the right) onto the stack
        BinaryShiftLeft,   # Pushes the result of a << b (a with bits shifted b times to the left) onto the stack
        BinaryXor,  # Pushes the result of a ^ b (bitwise exclusive or) onto the stack
        BinaryOr,   # Pushes the result of a | b (bitwise or) onto the stack
        BinaryAnd,  # Pushes the result of a & b (bitwise and) onto the stack
        UnaryNot,  # Pushes the result of ~x (bitwise not) onto the stack
        BinaryAs,   # Pushes the result of a as b onto the stack (converts a to the type of b. Explicit support from a is required)
        BinaryIs,   # Pushes the result of a is b onto the stack (true if a and b point to the same object, false otherwise)
        BinaryIsNot,  # Pushes the result of not (a is b). This could be implemented in terms of BinaryIs, but it's more efficient this way
        BinaryOf,   # Pushes the result of a of b onto the stack (true if a is a subclass of b, false otherwise)
        BinarySlice, # Perform slicing on supported objects (like "hello"[0:2], which yields "he"). The result is pushed onto the stack
        BinarySubscript,  # Subscript operator, like "hello"[0] (which pushes 'h' onto the stack)
        # Binary comparison operators
        GreaterThan,
        LessThan,
        EqualTo,
        GreaterOrEqual,
        LessOrEqual,
        # Logical operators
        LogicalNot,
        LogicalAnd,
        LogicalOr,
        # Binary in-place operators. Same as their non in-place counterparts
        # except they operate on already existing names.
        InPlaceAdd,
        InPlaceSubtract,
        InPlaceDivide,
        InPlaceFloorDiv,
        InPlaceMultiply,
        InPlacePow,
        InPlaceMod,
        InPlaceRightShift,
        InPlaceLeftShift,
        InPlaceXor,
        InPlaceOr,
        InPlaceAnd,
        InPlaceNot,
        # Constants/singletons
        Nil,
        True,
        False,
        Nan,
        Inf,
        # Basic stack operations
        Pop, 
        Push,
        # Name resolution/handling
        LoadAttribute,
        DeclareName,
        DeclareNameFast,
        LoadName,
        LoadNameFast,  # Compile-time optimization for statically resolved global variables
        UpdateName,
        UpdateNameFast,
        DeleteName,
        DeleteNameFast,
        # Looping and jumping
        JumpIfFalse,   # Jumps to an absolute index in the bytecode if the value at the top of the stack is falsey
        Jump,    # Relative unconditional jump in the bytecode. This is how instructions like break and continue are implemented
        Call,
        Return
        # Misc
        Raise,
        ReRaise,   # Re-raises active exception
        BeginTry,
        FinishTry, 
        Yield,
        Await,
        BuildList,
        BuildDict,
        BuildSet,
        BuildTuple




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
                             UnaryNot, InPlaceAdd, InPlaceDivide,
                             InPlaceFloorDiv, InPlaceMod, InPlaceMultiply,
                             InPlaceSubtract, BinaryFloorDiv, BinaryOf, Raise,
                             ReRaise, BeginTry, FinishTry,
                             Yield, Await}
const constantInstructions* = {LoadConstant, DeclareName,
                               LoadName, UpdateName,
                               DeleteName}
const byteInstructions* = {UpdateNameFast, LoadNameFast, 
                           DeleteNameFast, Call}
const jumpInstructions* = {JumpIfFalse, Jump}


proc newChunk*(): Chunk =
    ## Initializes a new, empty chunk
    result = Chunk(consts: @[], code: @[], lines: @[])


proc write*(self: Chunk, newByte: uint8, line: int) =
    ## Adds the given instruction at the provided line number
    ## to the given chunk object
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


proc addConstant*(self: Chunk, constant: ASTNode): array[3, uint8] =
    ## Writes a constant to a chunk. Returns its index casted to a 3-byte
    ## sequence (array)
    self.consts.add(constant)
    result = self.consts.high().toTriple()