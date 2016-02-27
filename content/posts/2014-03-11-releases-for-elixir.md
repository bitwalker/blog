+++
date = "2014-03-20T01:00:00-05:00"
draft = false
title = "Releases For Elixir"
categories = ["elixir", "erlang", "programming", "tutorials"]

+++

Be forewarned, this post requires a fair amount of knowledge about Elixir or Erlang. Though the topic of hot code upgrades and downgrades is probably of interest to any dev who crosses the line in to ops on a regular basis, this particular post is going to be diving headlong into the madness that is Erlang releases, and how I've fixed them for Elixir.

I was hanging out in `#elixir-lang` last week, when someone (I believe it was `tylerflint`) brought up the issue of performing releases with Elixir. This had been a passively interesting topic to me, as it had been briefly mentioned a few times before, but I hadn't actually heard of anyone doing them.

In case you are reading this post to get an idea of how hot code upgrades/downgrades work in Elixir/Erlang - releases are how you do so. It's more than a little interesting, that something that is touted as a major feature of the Erlang VM is roughly equivalent to summoning deep magic, with incantations so arcane that only the most learned of magicians dare approach the subject.

Just to give you an idea, take a look [at this documentation](http://www.erlang.org/doc/design_principles/release_handling.html) describing the high level concepts around release handling. If that doesn't scare you away, [maybe this will](http://www.erlang.org/doc/design_principles/appup_cookbook.html). That last one describes the most critical aspect, how one release will upgrade (and downgrade) to another. It's so important, that if you do it wrong, you might as well have not even done it in the first place, because either your app will crash, the upgrade will fail in unpredicatable ways, or it will upgrade, but perhaps reload a module instead of upgrade it in place. The general sentiment I've encountered is that people either don't use releases, or they use releases, but just do rolling upgrades (taking a node offline, and restarting it using the new release). That seems fundamentally broken to me.

In the Erlang world, there is an excellent tool called Relx, which shields you from virtually all of the pain around most of the release tasks. The problem of course, is that Relx makes no attempt to help you with the appups, which again, is kind of the most critical aspect. In additon, it requires you to write your own build script over the top in order to call it with the appropriate configuration and parameters. Still, you get a lot of stuff for free out of Relx, and I think it's an excellent tool - I think it can be better.

So `tylerflint` asked about releases, and nobody had answers. So I told him I'd be interested in helping build a tool for it. He came back a few days later with an example project containing a handwritten `Makefile`, `relx.config`, and shell script to boot the release - and it worked great! Here in just a few days, he had put together a working tool that generated releases and allowed you to start it up with an Elixir shell. Unfortunately, it didn't handle upgrades/downgrades, it required you to download and compile Elixir during execution, it depended on a specific version of ERTS (the Erlang Runtime System), and it wasn't packaged in a way that could be easily brought in to any project. 

So `exrm`, the Elixir Release Manager, was born. The first iteration was essentially an Elixir wrapper (via a Mix task) around the `Makefile`, `relx.config`, and shell script he had written. It worked, but there were a lot of flaws. Over the past week or so, it has now evolved into a fully functional tool, which handles initial release, upgrades, and downgrades - all within a simple Mix task. Most importantly though, it does automatic appup generation. This is the secret sauce that I think will make releases in Elixir not only painless, but a recommended strategy for deploying to production. To give you an idea of what Elixir releases, via `exrm`, look like today, here is all the commands necessary to execute a release, deploy it, start it, upgrade it, then downgrade it:

1. `mix release`
2. `<make changes to project>`
3. `mix release`
4. `mkdir -p /tmp/example` (create deploy location)
5. `cp rel/example/**.tar.gz /tmp` (copy release packages to target)
6. `cd /tmp/example && tar -xf ../example-0.0.1.tar.gz` (extract initial release)
7. `bin/example start` (start your app)
8. `bin/example remote_console` (if you want an `iex` shell attached to the running node)
9. `mkdir -p releases/0.0.2`
10. `cp ../example-0.0.2.tar.gz releases/0.0.2/example.tar.gz` (deploy the upgrade package)
11. `bin/example upgrade "0.0.2"` (upgrade the node)
12. `bin/example downgrade "0.0.1"` (downgrade the node)
13. `bin/example stop` (stop the app)

I don't know about you, but that's about the simplest possible deployment process I've seen in any language. All of that could be automated even further using a CI server of some kind, and all without ever taking the running application offline, not even a dropped network connection. Now I feel like I understand the power of the Erlang VM, and what it means to have hot upgrades and downgrades - it's an incredibly powerful feature. Sadly though, `exrm` is only useful to an Elixir project, but a lot of the core logic could just as easily be built in Erlang as well.

In case you are curious about the automatic appup generation, it works as follows:

1. Reads in the `.app` of both the old and new release.
2. Finds all of the `.beam` files in both the old and new release.
3. Determines what type of module each `.beam` represents (application, supervisor, behavior, or standard module)
4. Determines what type of upgrade operation to apply for each type of module. For instance, supervisors will always be upgraded/downgraded via `code_change`.
5. Determines the set difference between the old and new versions, and applies the appropriate action (load, upgrade, unload, downgrade) for each module. Upgrades are applied in order of their dependencies, and downgrades are applied in reverse order.

And that's it! I'm currently working with `tylerflint` on making release configuration a breeze, likely using cuttlefish, with an Elixir DSL for defining schema files. There will be more developments in the near future, so if releases are important to you, and you have an Elixir project either in, or going to, production - stay tuned. For more info, check out the [GitHub repository](https://github.com/bitwalker/exrm).

If you have any ideas, suggestions, issues, constructive criticisms - please leave a comment, or open an issue on the tracker.

