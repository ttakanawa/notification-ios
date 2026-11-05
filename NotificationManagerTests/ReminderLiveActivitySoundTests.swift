import AVFAudio
import Foundation
import Testing

@testable import NotificationManager

@Suite("Live Activity start sound")
struct ReminderLiveActivitySoundTests {
    @Test func scheduledStartSoundIsBundledValidSilentAudio() throws {
        let name = SystemReminderLiveActivityClient.scheduledStartSoundName as NSString
        let url = try #require(
            Bundle.main.url(
                forResource: name.deletingPathExtension, withExtension: name.pathExtension))
        let audio = try AVAudioFile(forReading: url)
        #expect(audio.length > 0)
        #expect(Double(audio.length) / audio.processingFormat.sampleRate < 1)
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
        try audio.read(into: buffer)
        let samples = try #require(buffer.floatChannelData)
        for channel in 0..<Int(buffer.format.channelCount) {
            #expect((0..<Int(buffer.frameLength)).allSatisfy { samples[channel][$0] == 0 })
        }
    }
}
