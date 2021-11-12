# Copyright 2020 Mattia Giambirtone
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

import strformat


const MAP_LOAD_FACTOR* = 0.75  # Load factor for builtin hashmaps
const HEAP_GROW_FACTOR* = 2   # How much extra memory to allocate for dynamic arrays and garbage collection when resizing
const MAX_STACK_FRAMES* = 800   # The maximum number of stack frames at any one time. Acts as a recursion limiter (1 frame = 1 call)
const JAPL_VERSION* = "0.4.0"
const JAPL_RELEASE* = "alpha"
const JAPL_COMMIT_HASH* = "b252749d0e5448b8fef64150299d8318362bc08c"
const JAPL_BRANCH* = "master"
const DEBUG_TRACE_VM* = false # Traces VM execution
const SKIP_STDLIB_INIT* = false # Skips stdlib initialization (can be imported manually)
const DEBUG_TRACE_GC* = false    # Traces the garbage collector (TODO)
const DEBUG_TRACE_ALLOCATION* = false   # Traces memory allocation/deallocation
const DEBUG_TRACE_COMPILER* = false  # Traces the compiler
const JAPL_VERSION_STRING* = &"JAPL {JAPL_VERSION} ({JAPL_RELEASE}, {CompileDate}, {CompileTime}) on branch {JAPL_BRANCH} ({JAPL_COMMIT_HASH[0..8]})"
const HELP_MESSAGE* = """The JAPL language, Copyright (C) 2021 Mattia Giambirtone & All contributors

This program is free software, see the license distributed with this program or check
http://www.apache.org/licenses/LICENSE-2.0 for more info.

Basic usage
-----------

$ jpl  -> Starts the REPL

$ jpl filename.jpl -> Runs filename.jpl


Command-line options
--------------------

-h, --help  -> Shows this help text and exits
-v, --version -> Prints the JAPL version number and exits
-s, --string -> Executes the passed string as if it was a file
-i, --interactive -> Enables interactive mode, which opens a REPL session after execution of a file or source string
-nc, --nocache -> Disables dumping the result of bytecode compilation to files
-cd, --cache-delay -> Configures the bytecode cache invalidation threshold, in minutes (defaults to 60)
"""