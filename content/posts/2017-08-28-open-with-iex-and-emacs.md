+++
title = "Using Elixir 1.5's open command with Emacs.app"
draft = false
date = "2017-08-28T21:19:00-05:00"
categories = ["elixir", "programming", "emacs"]
+++

If you are a user of Emacs, you may have seen [Chris McCord's post](https://dockyard.com/blog/2017/08/24/elixir-open-command-with-terminal-emacs) 
on the Dockyard blog last week about using Elixir 1.5's new `open` command in IEx with terminal Emacs.

Being an Emacs user, but preferring Emacs.app generally to the terminal Emacs, I decided to investigate applying his
work to my own workflow. I promised to write it up if I succeeded, so here we are!

The first thing we need to do is place some scripts (or symlink them) in `/usr/local/bin`. These scripts will be
used by Elixir to open Emacs.app to the location of the module or module/function we want. Since Chris already wrote 
up the reasons for these scripts, I'm going to keep this short and focus on the contents, where to place them, and the changes I made.

First, we have to ensure `ELIXIR_EDITOR` is exported in our environment, since I use `fish`, this is how I did that in my
`~/.config/fish/config.local.fish` file:

```sh
set -x ELIXIR_EDITOR "~/bin/emacs +__LINE__ __FILE__"
```

This tells Elixir to execute `~/bin/emacs` with the line and file of the thing we're opening as arguments.

That script looks like so:

```sh
#!/usr/bin/env sh
EMACSPATH=/Applications/Emacs.app/Contents/MacOS
EMACSCLIENT="$(which emacsclient)"

# Check if an emacs server is available 
# (by checking to see if it will evaluate a lisp statement)
if ! ("${EMACSCLIENT}" --eval "t"  2> /dev/null > /dev/null ); then
    # There is no server available so,
    # Start Emacs.app detached from the terminal 
    # and change Emac's directory to PWD

    nohup "${EMACSPATH}/Emacs" --chdir "${PWD}" "${@}" 2>&1 > /dev/null &
else
    # The emacs server is available so use emacsclient

    ARGS="${@}"
    if [ -z "$ARGS" ]; then
        # There are no arguments, so
        # tell emacs to open a new window

        "${EMACSCLIENT}" --eval "(list-directory \"${PWD}\")"
    else    
        # There are arguments, so
        # tell emacs to open them

        "${EMACSCLIENT}" --no-wait "${@}"
    fi

    # Bring emacs to the foreground

    ${EMACSCLIENT} --eval "(x-focus-frame nil)"
fi
```

Make sure that script is set as executable with `chmod +x path/to/script`.

You're all set! Now you can test `open` in IEx:

```sh
> iex -S mix
Erlang/OTP 20 [erts-9.0] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:10] [hipe] [kernel-poll:false]

Interactive Elixir (1.5.1) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> open MyApp.Supervisor
```

This should either open a new instance of Emacs.app, or open the file containing `MyApp.Supervisor` in the currently open
instance. Have fun!
