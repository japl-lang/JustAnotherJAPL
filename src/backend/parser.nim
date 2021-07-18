# CONFIDENTIAL
# ______________
#
#  2021 Mattia Giambirtone
#  All Rights Reserved.
#
#
# NOTICE: All information contained herein is, and remains
# the property of Mattia Giambirtone. The intellectual and technical
# concepts contained herein are proprietary to Mattia Giambirtone
# and his suppliers and may be covered by Patents and are
# protected by trade secret or copyright law.
# Dissemination of this information or reproduction of this material
# is strictly forbidden unless prior written permission is obtained
# from Mattia Giambirtone


import meta/token
import meta/ast

export `$`
export ast


type Parser* = ref object
    ## A recursive-descent top-down
    ## parser implementation
    current: int
    file: string
    errored*: bool
    errorMessage*: string
    tokens: seq[Token]







