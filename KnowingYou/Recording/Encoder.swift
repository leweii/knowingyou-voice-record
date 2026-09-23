import AVFoundation

/// Transcodes the crash-safe `.caf` recording to the final AAC `.m4a`.
/// Pulled forward from S09 into S10 because crash recovery
/// (`RecordingStore.recover`) needs it before S09's session/mixer exist;
/// S09 reuses this unchanged rather than redoing it.
enum Encoder {
    static func encode(caf: URL, to m4a: URL, format: AudioFormat) async throws {
        let inputFile = try AVAudioFile(forReading: caf)

        let channelCount: AVAudioChannelCount = format == .dualTrack ? 2 : 1
        let bitRate = format == .dualTrack ? 160_000 : 96_000
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFile.processingFormat.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: bitRate,
        ]

        let outputFile = try AVAudioFile(
            forWriting: m4a,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let bufferSize: AVAudioFrameCount = 8192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: bufferSize) else {
            throw KYError.encodingFailed("could not allocate PCM buffer")
        }

        while inputFile.framePosition < inputFile.length {
            buffer.frameLength = 0
            try inputFile.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try outputFile.write(from: buffer)
        }
    }
}
