use std::collections::VecDeque;
use std::net::{Ipv4Addr, UdpSocket};
use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use clap::Parser;
use hound::{SampleFormat, WavSpec, WavWriter};
use rodio::{source::Source, OutputStream};

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Path to write the recorded .wav stream to.
    output_file: PathBuf,

    /// The port to listen for incoming packets on.
    port: u16,

    /// If the live playback runs out of samples to play, it will wait for `jitter_backoff`
    /// milliseconds before resuming playback. Increasing this value may result in smoother
    /// playback, but will increase overall system latency.
    /// Additionally, the live playback may temporarily sound sped up if the audio
    /// stream suddenly catches up.
    /// The recorded .wav file is not affected by this value at all.
    #[arg(short, long, default_value_t = 50)]
    jitter_backoff: u64,

    /// The sample rate to assume for the incoming audio stream.
    #[arg(short, long, default_value_t = 44_100)]
    sample_rate: u32,

    /// Do not record the stream to a .wav file, only play back live.
    #[arg(short, long, default_value_t = false)]
    no_record: bool,
}

struct LivePlayback {
    jitter_backoff: usize,
    backoff: usize,
    sample_rate: u32,
    channels: u16,
    rx: Receiver<Vec<i16>>,
    buffer: VecDeque<f32>,
}

impl LivePlayback {
    fn new(sample_rate: u32, jitter_backoff: Duration) -> (Self, Sender<Vec<i16>>) {
        let (tx, rx) = mpsc::channel();

        let jitter_backoff = (jitter_backoff.as_millis() * sample_rate as u128 / 1000) as usize;

        (
            Self {
                jitter_backoff,
                backoff: 0,
                sample_rate,
                channels: 2,
                rx,
                buffer: VecDeque::new(),
            },
            tx,
        )
    }
}

impl Iterator for LivePlayback {
    type Item = f32;

    fn next(&mut self) -> Option<Self::Item> {
        if let Ok(sequence) = self.rx.try_recv() {
            self.buffer.extend(
                sequence
                    .into_iter()
                    .map(|sample| sample as f32 / i16::MAX as f32),
            )
        }

        if self.backoff > 0 {
            self.backoff -= 1;
            return Some(0.0);
        }

        match self.buffer.pop_front() {
            None => {
                self.backoff = self.jitter_backoff;
                Some(0.0)
            }

            sample => sample,
        }
    }
}

impl Source for LivePlayback {
    fn current_frame_len(&self) -> Option<usize> {
        None
    }

    fn channels(&self) -> u16 {
        self.channels
    }

    fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    fn total_duration(&self) -> Option<Duration> {
        None
    }
}

struct Recorder {
    output_file: PathBuf,
    rx: Receiver<RecorderMessage>,
    channels: u16,
    sample_rate: u32,
    recording: Vec<i16>,
}

impl Recorder {
    fn new(sample_rate: u32, output_file: PathBuf) -> (JoinHandle<()>, Sender<RecorderMessage>) {
        let (tx, rx) = mpsc::channel();

        let mut recorder = Self {
            output_file,
            rx,
            channels: 2,
            sample_rate,
            recording: Vec::new(),
        };

        let join_handle = thread::spawn(move || while recorder.listen() {});

        (join_handle, tx)
    }

    fn listen(&mut self) -> bool {
        match self.rx.recv() {
            Ok(RecorderMessage::Incoming(mut sequence)) => {
                self.recording.append(&mut sequence);
                true
            }

            Ok(RecorderMessage::JustExit) => false,

            Ok(RecorderMessage::SaveAndExit) => {
                self.save();
                false
            }

            _ => false,
        }
    }

    fn save(&self) {
        let spec = WavSpec {
            channels: self.channels,
            sample_rate: self.sample_rate,
            bits_per_sample: 16,
            sample_format: SampleFormat::Int,
        };

        let path = self.output_file.clone();
        let mut writer = WavWriter::create(path, spec).expect("cannot create .wav writer");

        for &sample in self.recording.iter() {
            writer
                .write_sample(sample)
                .expect("cannot write sample to .wav file");
        }

        if let Some(printable_path) = self.output_file.to_str() {
            println!("Output file `{}` written.", printable_path);
        } else {
            println!("Output stream written to file.");
        }
    }
}

enum RecorderMessage {
    JustExit,
    SaveAndExit,
    Incoming(Vec<i16>),
}

fn main() {
    let args = Cli::parse();

    let (live_playback, tx_live) =
        LivePlayback::new(args.sample_rate, Duration::from_millis(args.jitter_backoff));

    let (recorder_join_handle, tx_recorder) = Recorder::new(args.sample_rate, args.output_file);
    let tx_recorder_exit = tx_recorder.clone();

    let (_stream, stream_handle) = OutputStream::try_default().expect("cannot get playback device");

    stream_handle
        .play_raw(live_playback)
        .expect("cannot play back live stream");

    let socket = UdpSocket::bind((Ipv4Addr::new(127, 0, 0, 1), args.port))
        .expect("failed to create UDP socket");

    println!("Listening for UDP datagrams on 127.0.0.1:{}", args.port);

    ctrlc::set_handler(move || {
        if args.no_record {
            tx_recorder_exit.send(RecorderMessage::JustExit).ok();
        } else {
            tx_recorder_exit.send(RecorderMessage::SaveAndExit).ok();
        }

        while !recorder_join_handle.is_finished() {}
        std::process::exit(0);
    })
    .expect("failed to bind Ctrl+C handler");

    let mut buffer = Box::new(vec![0; 10485760]);

    while let Ok(size) = socket.recv(&mut buffer) {
        let samples: Vec<_> = (&buffer[..size])
            .chunks_exact(2)
            .map(|pair| i16::from_be_bytes(pair.try_into().unwrap()))
            .collect();

        tx_live
            .send(samples.clone())
            .expect("live playback thread closed");

        if !args.no_record {
            tx_recorder
                .send(RecorderMessage::Incoming(samples))
                .expect("recorder thread closed");
        }
    }
}
