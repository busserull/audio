defmodule An.Streamer do
  use Agent

  def start_link(opts) do
    address = Keyword.fetch!(opts, :address)
    port = Keyword.fetch!(opts, :port)

    dest = {address, port}

    Agent.start_link(
      fn ->
        {:ok, socket} = :gen_udp.open(0, mode: :binary, active: false)
        {socket, dest}
      end,
      name: __MODULE__
    )
  end

  def send(stream) do
    Agent.cast(__MODULE__, fn {socket, dest} ->
      :gen_udp.send(socket, dest, stream)
      {socket, dest}
    end)
  end
end
