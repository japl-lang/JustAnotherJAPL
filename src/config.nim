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

import strformat

const BYTECODE_MARKER* = "JAPL_BYTECODE"
const MAP_LOAD_FACTOR* = 0.75   # Load factor for builtin hashmaps
const HEAP_GROW_FACTOR* = 2     # How much extra memory to allocate for dynamic arrays and garbage collection when resizing
const MAX_STACK_FRAMES* = 800   # The maximum number of stack frames at any one time. Acts as a recursion limiter (1 frame = 1 call)
const JAPL_VERSION* = (major: 0, minor: 4, patch: 0)
const JAPL_RELEASE* = "alpha"
const JAPL_COMMIT_HASH* = "e234c8caaff25f6edf69329cf8a17531cb7914dd"
const JAPL_BRANCH* = "master"
const DEBUG_TRACE_VM* = false    # Traces VM execution
const SKIP_STDLIB_INIT* = false  # Skips stdlib initialization (can be imported manually)
const DEBUG_TRACE_GC* = false    # Traces the garbage collector (TODO)
const DEBUG_TRACE_ALLOCATION* = false   # Traces memory allocation/deallocation
const DEBUG_TRACE_COMPILER* = false     # Traces the compiler
const JAPL_VERSION_STRING* = &"JAPL {JAPL_VERSION.major}.{JAPL_VERSION.minor}.{JAPL_VERSION.patch} {JAPL_RELEASE} ({JAPL_BRANCH}, {CompileDate}, {CompileTime}, {JAPL_COMMIT_HASH[0..8]}) [Nim {NimVersion}] on {hostOS} ({hostCPU})"
const HELP_MESSAGE* = """The JAPL programming language, Copyright (C) 2021 Mattia Giambirtone & All Contributors

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
