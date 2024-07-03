# Real time audio streaming challenge

This is a submission to a programming challenge offered to me in as part of a screening process.

## Part 1: Proposed system architecture
![System architecture](arch.svg)

The proposed architecture of the system can be seen in the image above.
Short descriptions of each system component with estimated development time, along with packet formats follow.

## Packet format

There are two packet formats in use; "UDP mono with sequence numbers", and "UDP stereo without sequence numbers".
Firstly, the rationale for choosing UDP:

### Why UDP?

For an IP based protocol, we essentially have a choice only between UDP and TCP (disregarding SCTP).

TCP offers a robust connection-oriented way of transferring data. Packets are guaranteed to arrive in order, and most of the "Quality of Service" aspects are automatically handled on the transport layer. Importantly, it also offers congestion control. That said, TCP has a significant overhead due to acknowledgements, which in general limits its use in real-time systems somewhat.

UDP is "barebones" in the sense that it does not come with the fancy bells and whistles of TCP. It spews datagrams onto a line, and that's about it. The protocol has no knowledge about what happens to the packets, and it has no knowledge about whether someone is listening or not.

Ultimately, the low-latency requirement of the system speaks strongly for choosing UDP, even though it incurs more development effort, for example when tracking connected streams.

### UDP mono with sequence numbers

```text
  [ Sequence number (4 bytes big endian) ][ Single channel raw audio (configurable number of bytes) ]
```

This format is used when an `audiostreamer` sends packets to an `audionode`.

The reason for the sequence number is to allow the `audionode` to track dropped packets, and packets that arrive out of order. It is only used for logging, and no corrective action is taken.

The stream is a single channel only, as this is what's read from the `.wav` input file.

### UDP stereo without sequence numbers

```text
[ Dual channel raw audio (configurable number of bytes) ]
```

This format is used when an `audionode` streams to an `audiorecorder`. Optionally, this format may be used when an `audiostreamer` sends directly to an `audiorecorder` for testing.

This format has two channels, as it comes fully mixed from the `audionode`. When this format is used in the `audiostreamer`, the same track is simply copied on both channels.

## Proposed development strategy

The overarching strategy is as follows:

1. Develop `audiostreamer` to the point where it can send packets using the "UDP stereo" format.
2. Develop `audiorecorder` to the point where it can receive packets and play audio back.
3. Go back and implement the "UDP mono" format for `audiostreamer`.
4. Develop `audionode` so that it can relay packets from a single `audiostreamer` to an `audiorecorder`, converting the format from "UDP mono" to "UDP stereo" along the way.
5. Support more than one stream on the `audionode`, merging them together.
6. Implement master volume control for the `audionode` mixer.
7. Create a publish-subscribe service on the `audionode` that lets us influence the master volume, and advertise changes to clients.
8. Create a rudimentary web UI for changing the master volume, using websockets to communicate between the browser and the server, building upon the publish-subscribe system from before, to update all connected websockets.
9. Rinse and repeat this for individual track volumes.
10. Implement left-right balance for tracks, and add this to the publish-subscribe system, as well as the web UI.
11. Support left-right balance in the `audionode` mixer.
12. Extend the publish-subscribe system to allow updating clients on new streams and dropped streams.
13. Support dropping streams by assuming that a stream that hasn't sent data for some amount of time has quit.
14. Write stream events to a log file.
15. Go back and flesh out `audiorecorder` to actually record and save audio.
16. Sprinkle Tailwind CSS on the web UI to make it look swag.
17. Write this outline and documentation.

## Estimated time

A quick overview of estimated times before the project started follows, along with a description of why I gave the time estimate.

Afterwards, a similar overview of actual spent time is given.

* Research: 2 hours. As with most projects, there are things that need to be better understood before programming can happen. Upon starting this project, the design of the `.wav` file format was not known to me, for example.
* `audiostreamer` 2 hours. This seems simple enough:
  1. Read a `.wav` file.
  2. Chunk into packets.
  3. Blast away on UDP.
* `audionode` 8 hours or more. This will require some additional development time, as it involves several domains:
  - Rudimentary signal processing to merge streams (of potentially varying lengths) together.
  - Real-time server to web UI bi-directionaly communication, requires both the usual HTML, CSS, Javascript, plus server side code. Domain specific languages also tend to enter the mix here, not to mention a plethora of different frameworks and paradigms.
  - Simultaneous logging, communication, and signal processing calls for a decent amount of parallel work.
* `audiorecorder` 4 hours. This also seems simple:
  - It is essentially a "reverse `audiostreamer`", but it has to write a `.wav` and not just read one. This requires correctly setting the WAVE header after transmission has stopped.
  - Simultaneous live playback while also receiving and recording calls for some concurrency.

Total estimated time: ~16 hours.

# System implementation

A brief overview of choices made during development follows.

## Choice of technologies

Both `audiostreamer` and `audiorecorder` are simple CLI programs that perform well-defined and limited tasks. They should, however, perform their tasks quickly. Additionally, `audiorecorder` is doing a couple of things concurrently, so parallelizing should preferably be easy.

A language such as C, C++, Go, or Rust is a natural choice for this, as they all offer native performance.

Given free choice, there is little reason to choose C, as this by far incurs the heaviest development burden, as most things will have to be done from scratch.

Between C++, Go, and Rust, both Go and Rust have _arguably_ saner and more modern toolchains and language constructs, which is a huge plus.

The way I see it, Go and Rust can largely be picked based on preference in this scenario, so my choice falls to Rust, since I am more familiar with that, and would have to repeat a few things before I am proficient in Go.

For `audionode`, we not only require support for many simultaneous streams, but also preferably a seamless way to integrate a web based user interface. Although Rust may yet again be used here, I find Elixir + Phoenix a natural choice for the following reasons:

Firstly, Elixir is based on Erlang/OTP. Erlang itself was developed for massively scalable soft real-time systems for use in the telecom industry. It therefore seems rather fitting for this application.

Secondly, Phoenix is a highly robust, ergonomic, and efficient web development framework that integrates seamlessly into an Elixir supervisor tree, and allows for direct interop with other server code.

Choosing Elixir + Phoenix thus removes the need for interprocess communication between a dedicated "mixer server" and a "web UI client", and allows us keep all `audionode` code in the same project.

As a final cherry on top, Phoenix comes with the "LiveView" library (essentially the same as "Hotwire" for Ruby on Rails). Using this drastically limits the need for custom Javascript to glue bits and pieces of the interface and server together, thereby dramatically improving development times and developer happiness.


## Actual spent time

I do have to admit that I frequently underestimate the time that work will take. Here is a rundown:

* Research: a bit less than 2 hours. It turns out that `.wav` files are dirt simple, and part of this time was spent writing a combinator parser using the `nom` Rust library, to make sure I got all the details nailed down. Ultimately, this parser was scrapped in favor of using off-the-shelf and open source solutions. More on this later.
* `audiostreamer`: 4 hours. Part of this time was also spent on simultaneously developing a rudimentary `audiorecorder` for testing. The primary reason this ended taking up more time than estimated comes down to tuning of default packet sizes, refactoring, and the CLI.
* `audionode`: about 9 hours. Most of this was known, but optimizing audio stream merging to be fast enough took a chunk of time.
* `audiorecorder`: 4 hours. This took some fiddling, but by the time the full version of this was to be written, the strategy was pretty obvious from `audiostreamer`. Some time was spent for the CLI. Some more refactoring could have been done, so another hour could easily go into this.

Total time: ~19 hours.

## Libraries used

A handful of libraries have been used in the development process.
For a full overview, see `[dependencies]` in `audiostreamer/Cargo.toml` and `audiorecorder/Cargo.toml`.

For `audionode`, I have only directly used the Phoenix framework, which itself pulls in a number of dependencies. These are listed under `defp deps do` in `audionode/mix.exs`.

All of the libraries used have free and open source licenses. In particular, all of the used Rust libraries are licensed under Apache 2.0.

## Use of AI generated code

None :)

# Use of system

## `audiostreamer`

The `audiostreamer` is a Rust program, and can be run with `cargo run -- <wav file> <destination>`.

Optionally, the following flags may be supplied:
* `--chunk-size-ms`: Specifies how large each transmitted chunk should be, in milliseconds. Increasing this may make the transmission smoother, but will also increase latency. At some point, the transmitted UDP datagrams will also be prohibitively large, and will be silently dropped.
* `--stream-to-recorder`: Specify this flag to stream to an `audiorecorder` directly. The `audiorecorder` expects a stereo stream without sequence numbers, whereas an `audionode` expects a mono stream with sequence numbers. If streaming to an `audiorecorder` directly without this flag, the output stream will be played back twice as fast, and have auditory artifacts.

### Example

`cargo run -- BolzAndKnecht_HungarianDanceNo5_Full/03_Saxophone.wav 127.0.0.1:4030`

## `audionode`

The `audionode` is an Elixir/OTP + Phoenix application, and can be run with either `iex -S mix phx.server` or with just `mix phx.server`.o

For configuration, environment variables are used, and the following ones are supported:
* `LOGFILE`: Default `"audionode.log"`. The path and file name of the log file to write.
* `BUFFER_SIZE`: Default `200`. The internal mixer buffer size, in milliseconds. Increasing this may make streaming smoother, but will also increase overall system latency. At some point, the transmitted UDP datagrams will also be prohibitively large, and will be silently dropped.
* `LISTEN_PORT`: Default `4030`. The port to listen on incoming UDP datagrams on.
* `DEST`: Default `"127.0.0.1:4040"`. The destination address and port of an `audiorecorder`.

### Example

`LOGFILE=out.log iex -S mix phx.server`

### Logfile

The logfile tracks the following:
* New streams.
* Repeated packets (same sequence number received twice).
* Out of order packets.
* Missing packets.
* Dropped streams.

Each event is listed on a separate line, and has the format `[Timestamp (ms)] [IP address of event] Event description`. The timestamp denotes milliseconds since the server was started.

## `audiorecorder`

The `audiorecorder` is a Rust program, and can be run with `cargo run -- <wav file to save> <incoming port>`.

Optionally, the following flags may be supplied:
* `--jitter-backoff`: Default `50`. If the `audiorecorder` has consumed all available incoming data, the playback will allow this many milliseconds to buffer before resuming playback. Increasing this value may result in smoother playback, but also increase system latency. This value has no effect on the saved `.wav` file, only on the live stream.
* `--sample-rate`: Default `44100`. The incoming audio stream has no information about the stream sample rate, so it must be set explicitly.
* `--no-record`: When this flag is given, the `audiorecorder` will in fact not record audio to a `.wav` file, instead only playing it back live as it arrives. A dummy output filename must still be given.

### Example

`cargo run -- recording.wav 4040`

# Limitations and areas of potential improvement

During development, a handful of shortcuts have been taken. These will be briefly outlined, along with suggested changes.

## Common

Throughout the system, audio buffers are kept small. This decreases the experienced latency, but also quickly deteriorates audio quality when packets start dropping.

## `audiostreamer`

* [Congestion control] As the overall system relies on UDP, the `audiostreamer`s have no way of knowing when the network is at full capacity. Basic congestion control might be useful, but requires feedback from the `audionode`, complicating the communications protocol.

## `audionode`

* [Supervisors] The `audionode` maintains a supervisor tree that will restart processes if they fail. In this implementation, everything is kept under the same supervisor, which means that unrelated failures in e.g. the `Logger` module will incur a restart of the `Mixer` module. These may easily be put in separate supervisor trees.
* [Worker pools] This implementation strikes a balance between _enough parallelism_ and _total system overload_ only by heuristics based on trial and error. Defining a set worker pool for processes could allow for more predictable system utilization.
* [NIFs] All of the audio stream mixing is done in Elixir. **N**atively **I**mplemented **F**unctions would very likely result in a more scalable system, as mixing can be done a lot faster. This was also identified as the main bottleneck of the overall system.
* [Distribution] Elixir/OTP applications can scale to several machines with relative ease. Distributing the load among more machines, and mixing only parts of the tracks on each machine, before gluing them together on one "master machine" would allow for supporting a very high number of simultaneous connections indeed.
* [Decouple buffer size and transmission] The `audionode` internal buffer size is indirectly tied to the outgoing datagram size. This means that selecting a larger buffer will automatically make outgoing UDP packets larger. This is a very loose coupling, and I estimate only about an hour's work to more seamlessly split the internal buffer into several packets with appropriate sizes.
* [QoS] This implementation has a very simple packet scheme, consisting only of a sequence number and raw data. Packets are mixed and sent to the `audiorecorder`, even if they come out of order. Similarly, packets that are lost are simply gone; there is no effort taken to make a retransmission. Retransmission would increase latency, but might be acceptable in scenarios where a certain audio quality is required.
* [Production environment] The `audionode` currently only runs in debug build. This is only due to time saving on configuring the production toolchain, but is exceedingly straight forward setting up. Switching to a production build has the potential to dramatically increase performance in some areas.

## `audiorecorder`

* [Sample rate] The incoming data stream has no information about sample rate, so this must be explicitly given. The packet format may be extended to include basic metainformation before playback is started, although this would complicate the overall system architecture somewhat.
* [File appending] In this implementation, `audiorecorder` keeps the entire "recorded" playback in RAM, and only saves it to a `.wav` when the program is stopped. The sole reason for this is ease-of-development. Appending to a `.wav` while the stream is incoming is very straight forward, and upon exit only the file header has to be updated to reflect the correct stream size. Seeing as some naïve WAVE file parser implementations even disregard parts of the RIFF header, updating the file header upon exit might not even be necessary, as long as the end consuming application is "lenient" in this regard.
