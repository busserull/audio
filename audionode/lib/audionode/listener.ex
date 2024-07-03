defmodule An.Listener do
  use Task

  def start_link(opts) do
    port = Keyword.fetch!(opts, :port)
    Task.start_link(__MODULE__, :run, [port])
  end

  def run(port) do
    {:ok, socket} = :gen_udp.open(port, mode: :binary, active: false, reuseaddr: true)
    listen(socket)
  end

  def listen(socket) do
    {:ok, {address, port, packet}} = :gen_udp.recv(socket, 0)

    Task.start(__MODULE__, :parse_and_process, [address, port, packet])

    listen(socket)
  end

  def parse_and_process(address, port, packet) do
    <<seq::integer-big-unsigned-size(32), rest::binary>> = packet

    An.Logger.log_packet({address, port}, seq)

    stream = parse_stream([], rest)

    An.Mixer.add_stream({address, port}, stream)
  end

  def parse_stream(samples, <<>>), do: Enum.reverse(samples)

  def parse_stream(samples, <<head::integer-big-signed-size(16), rest::binary>>) do
    parse_stream([head | samples], rest)
  end
end
