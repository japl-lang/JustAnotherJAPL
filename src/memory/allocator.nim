# Copyright 2022 Mattia Giambirtone
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

## Memory allocator from JAPL


import segfaults
import ../config

when DEBUG_TRACE_ALLOCATION:
    import strformat


proc reallocate*(p: pointer, oldSize: int, newSize: int): pointer =
    ## Wrapper around realloc/dealloc
    try:
        if newSize == 0 and p != nil:
            when DEBUG_TRACE_ALLOCATION:
                if oldSize > 1:
                    echo &"DEBUG - Memory manager: Deallocating {oldSize} bytes"
                else:
                    echo "DEBUG - Memory manager: Deallocating 1 byte"
            dealloc(p)
            return nil
        when DEBUG_TRACE_ALLOCATION:
            if pointr == nil and newSize == 0:
                echo &"DEBUG - Memory manager: Warning, asked to dealloc() nil pointer from {oldSize} to {newSize} bytes, ignoring request"
        if oldSize > 0 and p != nil or oldSize == 0:
            when DEBUG_TRACE_ALLOCATION:
                if oldSize == 0:
                    if newSize > 1:
                        echo &"DEBUG - Memory manager: Allocating {newSize} bytes of memory"
                    else:
                        echo "DEBUG - Memory manager: Allocating 1 byte of memory"
                else:
                    echo &"DEBUG - Memory manager: Resizing {oldSize} bytes of memory to {newSize} bytes"
            result = realloc(p, newSize)
        when DEBUG_TRACE_ALLOCATION:
            if oldSize > 0 and pointr == nil:
                echo &"DEBUG - Memory manager: Warning, asked to realloc() nil pointer from {oldSize} to {newSize} bytes, ignoring request"
    except NilAccessDefect:
        stderr.write("JAPL: could not manage memory, segmentation fault\n")
        quit(139)   # For now, there's not much we can do if we can't get the memory we need, so we exit


template resizeArray*(kind: untyped, pointr: pointer, oldCount, newCount: int): untyped =
    ## Handy macro (in the C sense of macro, not nim's) to resize a dynamic array
    cast[ptr UncheckedArray[kind]](reallocate(pointr, sizeof(kind) * oldCount, sizeof(kind) * newCount))


template freeArray*(kind: untyped, pointr: pointer, oldCount: int): untyped =
    ## Frees a dynamic array
    reallocate(pointr, sizeof(kind) * oldCount, 0)


template free*(kind: untyped, pointr: pointer): untyped =
    ## Frees a pointer by reallocating its
    ## size to 0
    reallocate(pointr, sizeof(kind), 0)


template growCapacity*(capacity: int): untyped =
    ## Handy macro used to calculate how much
    ## more memory is needed when reallocating
    ## dynamic arrays
    if capacity < 8:
        8
    else:
        capacity * ARRAY_GROW_FACTOR


template allocate*(castTo: untyped, sizeTo: untyped, count: int): untyped =
    ## Allocates an object and casts its pointer to the specified type
    cast[ptr castTo](reallocate(nil, 0, sizeof(sizeTo) * count))
