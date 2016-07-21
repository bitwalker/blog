+++
title = "Distillery vs. Exrm vs. Relx"
draft = false
date = "2016-07-21T17:48:07-05:00"
categories = ["elixir", "erlang", "programming", "releases"]
+++

I received an excellent question on Twitter today:

{{< tweet 756255858636521472 >}}

I've been focusing more on implementing [Distillery](https://github.com/bitwalker/distillery),
sharing it with people willing to help test, etc., that I forgot to sit down and write down why it
exists in the first place. So in this post, I'll attempt to explain as best I can.

## Do I care?

Do you use Exrm? Then yes.

Do you use Relx? With Elixir? Then yes.

With Erlang? Not yet, but eventually.

## What is Distillery?

Distillery is effectively a rewrite of release handling for Elixir. It is intended to be a replacement of
Exrm, my library for building releases in Elixir projects. It is also a goal of the project to potentially
be a part of Mix itself as the standard tooling for releases in Elixir. It may or may not make sense to do so,
and for prototyping it needed to live as it's own project anyway, so here we are.

Distillery is written in Elixir, with no dependencies. It takes full advantage of the knowledge about the current
project and it's dependencies provided by Mix, this allows Distillery to do things like automatically determine
what applications are required in the release, even if you have dependencies which are missing an application
in their `mix.exs`, Distillery will still make sure it's added.

This rewrite also let me address some of the issues I, and others, had with how Exrm did certain things. One of
the big differences is in the handling of umbrella projects. When I first started with Elixir, umbrella projects
were very uncommon - so much so that I did not even support them initially. Over time of course, the complexity
of applications being built grew, and so did the usage and support for umbrellas in Elixir. Exrm still is very
simple in it's handling of umbrellas - you can build a release of one or more apps in the umbrella individually,
but it is not possible to build a release containing multiple apps. Distillery allows you to build releases containing
any combination of apps in the umbrella. Take a look at the [Umbrella Projects](https://hexdocs.pm/distillery/umbrella-projects.html)
page in Distillery's docs for an overview.

Likewise, Exrm did not have the a way to define multiple configurations of a release. For example, you may want
to configure releases differently for dev/staging/prod beyond just what's in your `config.exs`. Distillery has
support for this via [Environments](https://hexdocs.pm/distillery/configuration.html).
It also has support for defining more than one release, which Exrm did not support.

The new configuration file is the source of much of this flexibility, and is also much nicer, resembling the style
of configuration you are already used to in `config.exs`. It is different of course, but just as easy to pick up.

I also took this time to revamp error handling, warnings, etc., so that as a developer, you have much more useful
errors and warnings to work from when encountering issues. This is an area of constant improvement, but the
state of affairs is much better than it was in Exrm.

Distillery also introduces [event hooks](https://hexdocs.pm/distillery/boot-hooks.html),
[custom commands](https://hexdocs.pm/distillery/custom-commands.html), and EEx template overlays.
None of which were present in Exrm.

## What's wrong with Exrm?

Other than some of the deficiencies outlined above, Exrm continues to work well, and there are a large
number of people using it today. However it is ultimately architected
around Relx being at it's core. Relx was responsible for most of the heavy lifting of building the release.
Because this responsibility lay within Relx, Exrm could do nothing to make Relx smarter about Elixir applications.

There were also times where necessary fixes to Relx dependencies were made, but Relx was not updated in sync,
leaving users unable to upgrade easily to address issues.

Additionally, there is a lot of technical debt that has accrued over time. It's important to realize the Exrm has been
around since roughly 0.11 or so of Elixir, and been through a great many of the major changes to the language and
standard library. Likewise, people have come to rely on certain features which are better implemented in other ways,
and this has made it difficult to make significant changes like the one represented by the difference between
Distillery and Exrm.

## What's wrong with Relx?

Nothing! I mean, in the sense that it's been at the core of Exrm since day one, and is still an excellent tool.
I am still a maintainer on the project, and will continue to help out where I can. That said, for Elixir projects,
it's not an ideal fit. It works just fine, but Distillery can be much smarter about how it does things. Additionally,
Relx is still ultimately tailored around Erlang applications, thus booting a console of a Relx release means booting an Erlang shell,
not IEx. Exrm fixed this by forking Relx's boot script, but it was never ideal. Distillery is oriented around Elixir by
default, but provides a path to booting with an Erlang shell if so desired. This means that eventually when I add support
for using Distillery with rebar3, the correct shell can be chosen based on the build tool.

## What about edeliver?

I can't speak too much about it, since I don't use it myself, but I do know that it currently uses Exrm to build
releases (and I believe it can use Relx as well). Ultimately, I would see Distillery replacing Exrm in edeliver,
but currently that is not the case. As far as I'm aware, the comparison of these three tools does not impact edeliver
to any significant degree, as it just needs a tool to package a release, and takes it from there. If anyone from
the edeliver team reads this, and would like to connect on how to make the most use of Distillery, I'd be glad to do
so!
