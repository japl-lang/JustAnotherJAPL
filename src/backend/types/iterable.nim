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

# Implementation of iterable types and iterators in JAPL

import baseObject


type
    Iterable* = object of Obj
        ## Defines the standard interface
        ## for iterable types in JAPL
        length*: int
        capacity*: int
    Iterator* = object of Iterable
        ## This object drives iteration
        ## for every iterable type in JAPL except
        ## generators
        iterable*: ptr Obj
        iterCount*: int


proc getIter*(self: Iterable): ptr Iterator =
    ## Returns the iterator object of an
    ## iterable, which drives foreach
    ## loops
    return nil


proc next*(self: Iterator): ptr Obj = 
    ## Returns the next element from
    ## the iterator or nil if the
    ## iterator has been consumed
    return nil