# Copyright 2022 Mattia Giambirtone & All Contributors
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


## The base JAPL object

import ../../memory/allocator


type
    ObjectType* {.pure.} = enum
        ## All the possible object types
        String, Exception, Function,
        Class, Module, BaseObject,
        Native, Integer, Float, 
        Bool, NotANumber, Infinity, 
        Nil, List, Dict, Set, Tuple
    Obj* = object of RootObj
        ## The base object for all
        ## JAPL types. Every object
        ## in JAPL implicitly inherits
        ## from this base type and extends
        ## its functionality
        kind*: ObjectType
        hashValue*: uint64


## Object constructors and allocators

proc allocateObject*(size: int, kind: ObjectType): ptr Obj =
    ## Wrapper around reallocate() to create a new generic JAPL object
    result = cast[ptr Obj](reallocate(nil, 0, size))
    result.kind = kind


template allocateObj*(kind: untyped, objType: ObjectType): untyped =
    ## Wrapper around allocateObject to cast a generic object
    ## to a more specific type
    cast[ptr kind](allocateObject(sizeof kind, objType))


proc newObj*: ptr Obj =
    ## Allocates a generic JAPL object
    result = allocateObj(Obj, ObjectType.BaseObject)
    result.hashValue = 0x123FFFF


## Default object methods implementations

# In JAPL code, this method will be called
# stringify()
proc `$`*(self: ptr Obj): string = "<object>"
proc stringify*(self: ptr Obj): string = $self

proc hash*(self: ptr Obj): int64 = 0x123FFAA  # Constant hash value
# I could've used mul, sub and div, but "div" is a reserved
# keyword and using `div` looks ugly. So to keep everything
# consistent I just made all names long
proc multiply*(self, other: ptr Obj): ptr Obj = nil
proc sum*(self, other: ptr Obj): ptr Obj = nil
proc divide*(self, other: ptr Obj): ptr Obj = nil
proc subtract*(self, other: ptr Obj): ptr Obj = nil
# Returns 0 if self == other, a negative number if self < other
# and a positive number if self > other. This is a convenience
# method to implement all basic comparison operators in one
# method 
proc compare*(self, other: ptr Obj): ptr Obj = nil
# Specific methods for each comparison
proc equalTo*(self, other: ptr Obj): ptr Obj = nil
proc greaterThan*(self, other: ptr Obj): ptr Obj = nil
proc lessThan*(self, other: ptr Obj): ptr Obj = nil
proc greaterOrEqual*(self, other: ptr Obj): ptr Obj = nil
proc lessOrEqual*(self, other: ptr Obj): ptr Obj = nil