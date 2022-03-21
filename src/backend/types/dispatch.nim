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

## Type dispatching module
import baseObject
import intObject
import floatObject


proc dispatch*(obj: ptr Obj, p: proc (self: ptr Obj): ptr Obj): ptr Obj =
    ## Dispatches a given one-argument procedure according to 
    ## the provided object's runtime type and returns its result
    case obj.kind:
        of BaseObject:
            result = p(obj)
        of ObjectType.Float:
            result = p(cast[ptr Float](obj))
        of ObjectType.Integer:
            result = p(cast[ptr Integer](obj))
        else:
            discard


proc dispatch*(a, b: ptr Obj, p: proc (self: ptr Obj, other: ptr Obj): ptr Obj): ptr Obj =
    ## Dispatches a given two-argument procedure according to 
    ## the provided object's runtime type and returns its result
    case a.kind:
        of BaseObject:
            result = p(a, b)
        of ObjectType.Float:
            # Further type casting for b is expected to occur later
            # in the given procedure
            result = p(cast[ptr Float](a), b)
        of ObjectType.Integer:
            result = p(cast[ptr Integer](a), b)
        else:
            discard