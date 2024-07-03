use std::collections::VecDeque;
use std::fs::File;
use std::io::BufReader;
use std::net::{SocketAddr, UdpSocket};
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::time::{Duration, Instant};

use clap::Parser;
use rodio::{source::Source, Decoder};

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Path to .wav file to transmit.
    wave_file: PathBuf,

    /// IP address to stream to, on the format ip:port, as in 127.0.0.1:4040.
    address: String,

    /// Group bits of the input .wav file into chunks of this many milliseconds
    /// before transmitting. A lower value means lower latency, but also that
    /// packets will be transmitted more frequently.
    #[arg(short, long, default_value_t = 25)]
    chunk_size_ms: usize,

    /// Whether we are streaming directly to an AudioRecorder or not.
    /// When streaming to an AudioRecorded, the AudioStreamer will convert
    /// the stream to stereo, since this is assumed by the AudioRecorder.
    /// When streaming to an AudioNode, the stream is left in mono to save
    /// on bandwidth and drive latency down.
    #[arg(short, long, default_value_t = false)]
    stream_to_recorder: bool,
}

struct Wave {
    channels: u16,
    sample_rate: u32,
    data: VecDeque<i16>,
}

impl Wave {
    fn from<P: AsRef<Path>>(path: P) -> Self {
        let file = BufReader::new(File::open(path).expect("cannot open audio file"));
        let source = Decoder::new(file).expect("failed to decode audio file");

        let sample_rate = source.sample_rate();

        let data: VecDeque<i16> = source.into_iter().collect();

        Self {
            // Assume that the read .wav file only has one channel by default,
            // to make development marginally easier
            channels: 1,
            sample_rate,
            data,
        }
    }

    fn make_stereo(&mut self) {
        if self.channels == 2 {
            return;
        }

        self.channels = 2;

        let mut data = VecDeque::with_capacity(2 * self.data.len());

        for &sample in self.data.iter() {
            data.push_back(sample);
            data.push_back(sample);
        }

        self.data = data;
    }

    fn chunk_ms(self, ms: usize, include_sequence_number: bool) -> (Vec<u8>, WaveChunks) {
        let chunk_size = (self.channels as usize * ms) * (self.sample_rate as usize) / 1000;
        let stream = Vec::from(self.data);

        (
            Vec::with_capacity(4 + 2 * chunk_size),
            WaveChunks::new(stream, chunk_size, include_sequence_number),
        )
    }
}

struct WaveChunks {
    include_sequence_number: bool,
    exhausted: bool,
    stream: Vec<i16>,
    chunk_size: usize,
    count: u32,
}

impl WaveChunks {
    fn new(stream: Vec<i16>, chunk_size: usize, include_sequence_number: bool) -> Self {
        Self {
            exhausted: false,
            stream,
            chunk_size,
            count: 0,
            include_sequence_number,
        }
    }

    fn next(&mut self, buffer: &mut Vec<u8>) -> Option<usize> {
        if self.exhausted {
            return None;
        }

        let start = self.count as usize * self.chunk_size;
        let mut end = start + self.chunk_size;

        if end >= self.stream.len() {
            end = self.stream.len();
            self.exhausted = true;
        }

        buffer.clear();

        if self.include_sequence_number {
            buffer.extend_from_slice(&self.count.to_be_bytes());
        }

        for sample in &self.stream[start..end] {
            buffer.extend_from_slice(&sample.to_be_bytes());
        }

        self.count += 1;

        Some(
            self.include_sequence_number
                .then_some(4)
                .unwrap_or_default()
                + 2 * (end - start),
        )
    }
}

fn main() {
    let args = Cli::parse();

    let mut wave = Wave::from(args.wave_file);

    if args.stream_to_recorder {
        wave.make_stereo();
    }

    let socket = UdpSocket::bind("127.0.0.1:0").expect("failed to create UDP socket");

    let destination = SocketAddr::from_str(&args.address).expect("malformed destination address");
    let send_interval = Duration::from_millis(args.chunk_size_ms as u64);

    let (mut buffer, mut payload_stream) =
        wave.chunk_ms(args.chunk_size_ms, !args.stream_to_recorder);

    while let Some(byte_count) = payload_stream.next(&mut buffer) {
        let sent = Instant::now();

        socket.send_to(&buffer[..byte_count], destination).ok();

        while Instant::now() - sent < send_interval {}
    }
}
