defmodule An.Synth do
  def merge_and_send(_master_volume, []) do
    nil
  end

  def merge_and_send(master_volume, streams) do
    Task.start(__MODULE__, :synthesize, [master_volume, streams])
  end

  def synthesize(master_volume, mono_streams) do
    stereo = Enum.map(mono_streams, &make_stereo(master_volume, &1))

    single_stream = merge(stereo)

    bytes = encode_stream(single_stream)

    An.Streamer.send(bytes)
  end

  def make_stereo(master_volume, {{volume, right, left}, _drop_count, stream}) do
    r = master_volume * volume * right
    l = master_volume * volume * left

    Enum.map(stream, &{trunc(&1 * r), trunc(&1 * l)})
  end

  def merge([stream | []]), do: stream

  def merge([head | tail]), do: merge(head, tail)

  def merge(head, []), do: Enum.to_list(head)

  def merge(first, [second | rest]) do
    padded = Stream.concat(second, Stream.cycle([{0, 0}]))

    partly_merged =
      Stream.zip_with(first, padded, fn {fr, fl}, {sr, sl} -> {fr + sr, fl + sl} end)

    merge(partly_merged, rest)
  end

  @doc """
  Encode a stream of signed 16 bit values into a stream of encoded bytes.
  """
  def encode_stream(buffer), do: encode_stream(<<>>, buffer)

  def encode_stream(bitstring, []), do: bitstring

  def encode_stream(bitstring, [{r, l} | tl]) do
    encode_stream(
      <<bitstring::binary, r::integer-signed-size(16), l::integer-signed-size(16)>>,
      tl
    )
  end
end
