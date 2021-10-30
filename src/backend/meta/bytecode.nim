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


export ast


type
    Chunk* = ref object
        ## A piece of bytecode.
        ## Consts represents the constants table the code is referring to
        ## and is a compile-time a mirror of the VM's stack at runtime.
        ## Code is the linear sequence of compiled bytecode instructions.
        ## Lines maps bytecode instructions to line numbers using Run
        ## Length Encoding. Instructions are encoded in groups whose structure
        ## follows the following schema:
        ## - The first integer represents the line number
        ## - The second integer represents the count of whatever comes after it
        ##  (let's call it c)
        ## - After c, a sequence of c integer follows
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
        ## Note: x represents the
        ## argument to unary opcodes, while
        ## a and b represent arguments to binary
        ## opcodes. Other variable names may be
        ## used for more complex opcodes
        
        LoadConstant = 0u8,  # Pushes constant from Chunk.consts[x] onto the stack
        # Binary operators
        UnaryNegate,  # Pushes the result of -x onto the stack
        BinaryAdd,    # Pushes the result of a + b onto the stack
        BinarySubtract,  # Pushes the result of a - b onto the stack
        BinaryDivide,    # Pushes the result of a / b onto the stack (true division)
        BinaryFloorDiv,  # Pushes the result of a // b onto the stack (integer division)
        BinaryMultiply,  # Pushes the result of a * b onto the stack
        BinaryPow,    # Pushes the result of a ** b (reads as 'a to the power of') onto the stack
        BinaryMod,  # Pushes the result of a % b onto the stack (modulo division)
        BinaryShiftRight,  # 
        BinaryShiftLeft,
        BinaryXor,
        BinaryOr,
        BinaryAnd,
        BinaryNot,
        BinaryAs,   # Type conversion
        BinaryIs,   # Identity checking
        BinaryOf,   # Instance checking
        BinarySlice,  # Subscript operator, like "hello"[0]
        # Binary comparison operators
        GreaterThan,   # 
        LessThan,
        EqualTo,
        GreaterOrEqual,
        LessOrEqual,
        # Logical operators
        LogicalNot,
        LogicalAnd,
        LogicalOr,
        # Binary in-place operators
        InPlaceAdd,
        InPlaceSubtract,
        InPlaceDivide,
        InPlaceFloorDiv,
        InPlaceMultiply,
        InPlacePow,
        InPlaceMod,
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
        JumpIfFalse,
        Jump,
        Loop,
        Call,
        Return
        # Misc
        Raise,
        ReRaise,   # Re-raises active exception
        BeginTry,
        FinishTry



const simpleInstructions* = {OpCode.Return, OpCode.BinaryAdd, OpCode.BinaryMultiply,
                             OpCode.BinaryDivide, OpCode.BinarySubtract,
                             OpCode.BinaryMod, OpCode.BinaryPow, OpCode.Nil,
                             OpCode.True, OpCode.False, OpCode.Nan, OpCode.Inf,
                             OpCode.BinaryShiftLeft, OpCode.BinaryShiftRight,
                             OpCode.BinaryXor, OpCode.LogicalNot, OpCode.EqualTo,
                             OpCode.GreaterThan, OpCode.LessThan, OpCode.LoadAttribute,
                             OpCode.BinarySlice, OpCode.Pop, OpCode.UnaryNegate,
                             OpCode.BinaryIs, OpCode.BinaryAs, OpCode.GreaterOrEqual,
                             OpCode.LessOrEqual, OpCode.BinaryOr, OpCode.BinaryAnd,
                             OpCode.BinaryNot, OpCode.InPlaceAdd, OpCode.InPlaceDivide,
                             OpCode.InPlaceFloorDiv, OpCode.InPlaceMod, OpCode.InPlaceMultiply,
                             OpCode.InPlaceSubtract, OpCode.BinaryFloorDiv, OpCode.BinaryOf}
const constantInstructions* = {OpCode.LoadConstant, OpCode.DeclareName,
                               OpCode.LoadName, OpCode.UpdateName,
                               OpCode.DeleteName}
const byteInstructions* = {OpCode.UpdateNameFast, OpCode.LoadNameFast, 
                           OpCode.DeleteNameFast, OpCode.Call}
const jumpInstructions* = {OpCode.JumpIfFalse, OpCode.Jump, OpCode.Loop}


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


proc write*(self: Chunk, bytes: openarray[uint8], line: int) =
    ## Calls writeChunk in a loop with all members of the given
    ## array
    for cByte in bytes:
        self.write(cByte, line)


proc addConstant*(self: Chunk, constant: ASTNode): array[3, uint8] =
    ## Writes a constant to a chunk. Returns its index casted to a 3-byte
    ## sequence (array)
    self.consts.add(constant)
    result = cast[array[3, uint8]](self.consts.high())