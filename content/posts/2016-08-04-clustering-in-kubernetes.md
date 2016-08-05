+++
title = "Elixir/Erlang Clustering in Kubernetes"
draft = false
date = "2016-08-04T18:00:00-05:00"
categories = ["elixir", "erlang", "programming", "kubernetes", "clustering"]
+++

At work, our infrastructure is run on OpenShift Origin, a RedHat OSS project which
is a bunch of nice tooling on top of Kubernetes. It's been really pleasant to work with
for the most part, though there have been some growing pains and lessons learned along
the way. Since I was responsible for pushing to adopt it, and setting up the cluster, I've been
sort of the go-to for edge cases and advice designing our applications around it. One of
the first things that came up, and which I've spent a lot of time working with, is how to
handle some of our Elixir/Erlang applications which need to form a cluster of nodes.

For those not entirely familiar, here's a brief recap of how Erlang does distribution. Nodes
must be configured to start in distributed mode, with a registered long or short name, and
a magic cookie which will be used for authentication when connecting nodes. Typically you configure
your node for distribution in `vm.args` like so:

```elixir
-name myapp@192.168.1.2
-setcookie myapp
```

The above will tell the VM on start up to enable distribution, register the node with the long name
`myapp@192.168.1.2` with the magic cookie `myapp`. Other nodes which wish to connect to this node, must
explicitly connect with `:net_adm.connect_node(:'myapp@192.168.1.2')`, be present in the `.hosts.erlang`
file read by those nodes, or one can rely on implicitly connecting when the node is referenced in a call
to `:rpc.call/4` or whatever. It's important to note that the domain, i.e. `192.168.1.2` in this case, must be
routable. So just putting any old domain name in there is not a good idea. Anyway, once we've connected to
the node, we can now talk to processes on the other node, etc.

All of this is pretty manual, other than the `.hosts.erlang` file, which if you're wondering what that is,
here's the excerpt from the Erlang manual:

```
File .hosts.erlang consists of a number of host names written as Erlang terms. It is looked for in the current work directory, the user's home directory, and $OTP_ROOT (the root directory of Erlang/OTP), in that order.

The format of file .hosts.erlang must be one host name per line. The host names must be within quotes.

Example:

    'super.eua.ericsson.se'.
    'renat.eua.ericsson.se'.
    'grouse.eua.ericsson.se'.
    'gauffin1.eua.ericsson.se'.
```

Even that file though requires knowing in advance what hosts to connect to. If you're familiar with Kubernetes,
you've probably already realized by now that this is not really possible. Container IP addresses are dynamic, and even if
they were static, dynamically scaling the number of replicas based on load means that you will have nodes joining/leaving
the cluster.

So how does one handle clustering in such a dynamic environment? My first shot at solving this was to use Redis as
a cluster registry. It worked fine, mostly, but I hated the dependency, and wanted something easily reusable across
our other apps. My next shot at addressing those issues, was to build a library I recently released, called
[Swarm](https://github.com/bitwalker/swarm), which as part of it's functionality, includes autoclustering via a UDP gossip
protocol. This worked nicely in my test environment, which was not run under Kubernetes, but when I pushed it to our developlment
environment in OpenShift, I found out that OpenShift does not currently route UDP packets over the pod network. Damn it.

It was at this point that I was doing some maintainence on one of our applications, and discovered that Kubernetes mounts
an API token, and the current namespace, for the pod's service account, into every container. This API token can be used to
then query the Kubernetes API for the set of pods in a given service. Swarm is built with pluggable "cluster strategies", so
I wrote one to pull all pod IPs associated with services which match a given label selector, i.e. `app=myapp`. It then polls
the Kubernetes API every 5s and connects to new nodes when they appear. To be clear, since all you get from Kubernetes is the
pod IP, you only have half of the node name you need for the `-name` flag in `vm.args`, but for my use case, I could simply
share the same hostname, i.e. `myapp`, and then use the pod IP to get the full node name. Success!

If you are running on Kubernetes, and want to cluster some Elixir/Erlang nodes, give [Swarm](https://github.com/bitwalker/swarm)
a look. In the `priv` directory, it has a `.yaml` file containing the definition of a Role which will grant any user associated
with that role, the ability to list endpoints (the set of pods in a service). To give you a quick run down of the steps required:

- Create the `endpoints-viewer` role using the Swarm-provided definition.
- Grant the default serviceaccount in the namespace you plan to cluster in, the `endpoints-viewer` role.
- Configure Swarm with the node basename and label selector to use for locating nodes.
- Start your app!



I should probably talk about Swarm in another blog post at some point, but it also provides a distributed global process
registry, similar to `gproc`, but is leaderless, and can handle a much larger number of registered processes. In addition
to the process registry, it also does process grouping, so you can publish messages to all members of a group, or call
all members and collect the results. Names can be any Erlang term, which gives you a great deal more flexibility with naming.
It has it's own tradeoffs vs `gproc` though, so it isn't necessarily the go-to solution for every problem, but was necessary
for my own use cases at work because we're an IoT platform, and have processes per-device which need to have messages routed
to them wherever they are in the cluster.

Reach out on Twitter or GitHub if you have questions about my experiences, I'd love to know how other people are tackling
these kinds of things!
