# Detection
# ‾‾‾‾‾‾‾‾‾

hook global BufCreate .*[.](fbdl?) %{
    set-option buffer filetype fbdl
}

# Initialization
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾

hook global WinSetOption filetype=fbdl %{
    require-module fbdl

    set-option window static_words %opt{fbdl_static_words}

    hook window InsertChar \n -group fbdl-insert fbdl-insert-on-new-line
    hook window InsertChar \n -group fbdl-indent fbdl-indent-on-new-line
    # cleanup trailing whitespaces on current line insert end
    hook window ModeChange pop:insert:.* -group fbdl-trim-indent %{ try %{ execute-keys -draft <semicolon> <a-x> s ^\h+$ <ret> d } }
    hook -once -always window WinSetOption filetype=.* %{ remove-hooks window fbdl-.+ }
}

hook -group fbdl-highlight global WinSetOption filetype=fbdl %{
    add-highlighter window/fbdl ref fbdl
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/fbdl }
}

provide-module fbdl %§

# Highlighters & Completion
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

add-highlighter shared/fbdl regions
add-highlighter shared/fbdl/code default-region group
#add-highlighter shared/fbdl/docstring     region -match-capture ^\h*("""|''') (?<!\\)(?:\\\\)*("""|''') regions
#add-highlighter shared/fbdl/triple_string region -match-capture ("""|''') (?<!\\)(?:\\\\)*("""|''') fill string
add-highlighter shared/fbdl/double_string region '"'   (?<!\\)(\\\\)*"  fill string
#add-highlighter shared/fbdl/single_string region "'"   (?<!\\)(\\\\)*'  fill string
#add-highlighter shared/fbdl/documentation region '##'  '$'              fill documentation
add-highlighter shared/fbdl/comment       region '#'   '$'              fill comment

# Integer formats
add-highlighter shared/fbdl/code/ regex '(?i)\b0b[01]+l?\b' 0:value
add-highlighter shared/fbdl/code/ regex '(?i)\b0x[\da-f]+l?\b' 0:value
add-highlighter shared/fbdl/code/ regex '(?i)\b0o?[0-7]+l?\b' 0:value
add-highlighter shared/fbdl/code/ regex '(?i)\b([1-9]\d*|0)l?\b' 0:value

# Bit string literals. TODO: Do not work, why?.
add-highlighter shared/fbdl/code/ regex '[bB]"[01_]*"' 0:value
add-highlighter shared/fbdl/code/ regex '[oO]"[01234567_]*"' 0:value
add-highlighter shared/fbdl/code/ regex '(?i)x"[0123456789abcdef_]*"' 0:value

# Float formats
add-highlighter shared/fbdl/code/ regex '\b\d+[eE][+-]?\d+\b' 0:value
add-highlighter shared/fbdl/code/ regex '(\b\d+)?\.\d+\b' 0:value
add-highlighter shared/fbdl/code/ regex '\b\d+\.' 0:value

#add-highlighter shared/fbdl/docstring/ default-region fill documentation
#add-highlighter shared/fbdl/docstring/ region '(>>>|\.\.\.) \K'    (?=''')|(?=""") ref fbdl

add-highlighter shared/fbdl/code/ regex (?<=[\w\s\d\)\]'"_])(<=|<<|>>|>=|<>?|>|!=|==|\||\^|&|\+|-|\*\*?|//?|%|~) 0:operator

evaluate-commands %sh{
    values="true false"

    time_units="ns us ms s"

    keywords="const if import type"

    properties="
        access add-enable atomic
        byte-write-enable
        clear
        delay
        enable-init-value enable-reset-value
        init-value in-trigger
        masters
        out-trigger
        range read-latency read-value reset reset-value
        size
        width
    "

    functions="abs bool ceil floor log log2 log10"

    types="blackbox block bus config group irq mask memory param proc return status stream static"

    join() { sep=$2; eval set -- $1; IFS="$sep"; echo "$*"; }

    # Add the language's grammar to the static completion list
    printf %s\\n "declare-option str-list fbdl_static_words $(join "${values} ${time_units} ${attributes} ${methods} ${keywords} ${types} ${functions}" ' ')"

#        add-highlighter shared/fbdl/code/ regex '\b($(join "${attributes}" '|'))\b' 0:attribute
#        add-highlighter shared/fbdl/code/ regex '\b($(join "${types}" '|'))\b' 0:type
    # Highlight keywords
    printf %s "
        add-highlighter shared/fbdl/code/ regex '\b($(join "${values}" '|'))\b' 0:value
        add-highlighter shared/fbdl/code/ regex '\d+\s+\b($(join "${time_units}" '|'))\b' 1:meta
        add-highlighter shared/fbdl/code/ regex '\b($(join "${keywords}" '|'))\b' 0:keyword
        add-highlighter shared/fbdl/code/ regex '[^\t]\b($(join "${types}" '|'))\b' 1:type
        add-highlighter shared/fbdl/code/ regex '((^|;)\s*\b($(join "${properties}" '|'))\b\s*=)' 3:attribute
        add-highlighter shared/fbdl/code/ regex '\b($(join "${functions}" '|'))\b\(' 1:builtin
    "
}

#add-highlighter shared/fbdl/code/ regex (?<=[\w\s\d'"_])((?<![=<>!]):?=(?![=])|[+*-]=) 0:builtin
#add-highlighter shared/fbdl/code/ regex ^\h*(?:from|import)\h+(\S+) 1:module

# Commands
# ‾‾‾‾‾‾‾‾

define-command -hidden fbdl-insert-on-new-line %{
    evaluate-commands -draft -itersel %{
        # copy '#' comment prefix and following white spaces
        try %{ execute-keys -draft k <a-x> s ^\h*#\h* <ret> y jgh P }
    }
}

define-command -hidden fbdl-indent-on-new-line %<
    evaluate-commands -draft -itersel %<
        # preserve previous line indent
        try %{ execute-keys -draft <semicolon> K <a-&> }
        # cleanup trailing whitespaces from previous line
        try %{ execute-keys -draft k x s \h+$ <ret> d }
        # indent after line ending with :
        try %{ execute-keys -draft <space> k <a-x> <a-k> :$ <ret> <a-K> ^\h*# <ret> j <a-gt> }
        # deindent closing brace/bracket when after cursor (for arrays and dictionaries)
        try %< execute-keys -draft <a-x> <a-k> ^\h*[}\]] <ret> gh / [}\]] <ret> m <a-S> 1<a-&> >
    >
>

§
