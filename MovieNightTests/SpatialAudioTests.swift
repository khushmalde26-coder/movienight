import Foundation
import Testing
@testable import MovieNight

struct SpatialAudioTests {
    @Test func readsFFmpegProfiles() {
        #expect(SpatialAudio.fromProfile("Dolby Digital Plus + Dolby Atmos") == .atmos)
        #expect(SpatialAudio.fromProfile("Dolby TrueHD + Dolby Atmos") == .atmos)
        #expect(SpatialAudio.fromProfile("DTS-HD MA + DTS:X") == .dtsX)
        #expect(SpatialAudio.fromProfile("DTS-HD MA + DTS:X IMAX") == .dtsX)
        #expect(SpatialAudio.fromProfile("DTS-HD MA") == nil)
        #expect(SpatialAudio.fromProfile("LC") == nil)
        #expect(SpatialAudio.fromProfile(nil) == nil)
    }

    @Test func fallsBackToReleaseNames() {
        #expect(SpatialAudio.fromFileName("Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.mkv") == .atmos)
        #expect(SpatialAudio.fromFileName("Top Gun Maverick (2022) TrueHD 7.1 Atmos.mkv") == .atmos)
        #expect(SpatialAudio.fromFileName("Oppenheimer.2023.DTS-X.mkv") == .dtsX)
        #expect(SpatialAudio.fromFileName("Atmosphere.mkv") == nil)
        #expect(SpatialAudio.fromFileName("Heat (1995).mkv") == nil)
    }

    /// dec3 for one 5.1 independent substream: data_rate, num_ind_sub, the substream, then the
    /// optional JOC extension (reserved 7 bits, flag_ec3_extension_type_a, complexity_index_type_a).
    private func dec3(joc: Bool) -> Data {
        var bits = ""
        func put(_ value: Int, _ count: Int) { bits += String(value, radix: 2).leftPad(count) }
        put(768, 13); put(0, 3)                                  // 768 kbit/s, one independent substream
        put(0, 2); put(16, 5); put(0, 1); put(0, 1); put(0, 3)   // fscod, bsid 16, reserved, asvc, bsmod
        put(7, 3); put(1, 1); put(0, 3); put(0, 4); put(0, 1)    // acmod 3/2, LFE, reserved, no dependents
        if joc { put(0, 7); put(1, 1); put(16, 8) }
        while bits.count % 8 != 0 { bits += "0" }
        return Data(stride(from: 0, to: bits.count, by: 8).map { UInt8(bits.dropFirst($0).prefix(8), radix: 2)! })
    }

    @Test func spotsAtmosInDolbyDigitalPlus() {
        #expect(SpatialAudio.isJointObjectCoding(dec3: dec3(joc: true)))
        #expect(!SpatialAudio.isJointObjectCoding(dec3: dec3(joc: false)))
        #expect(!SpatialAudio.isJointObjectCoding(dec3: Data([0x01])))
    }
}

private extension String {
    func leftPad(_ count: Int) -> String { String(repeating: "0", count: max(0, count - self.count)) + self }
}
