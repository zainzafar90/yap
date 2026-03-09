import Foundation
import AVFoundation
import Accelerate
import CoreMedia

enum AudioCaptureError: LocalizedError {
    case deviceUnavailable
    case inputCreationFailed
    case outputCreationFailed
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:      return "The selected microphone is unavailable."
        case .inputCreationFailed:    return "Could not create a capture input for the selected microphone."
        case .outputCreationFailed:   return "Could not create a capture output for the selected microphone."
        case .unsupportedAudioFormat: return "Received an unsupported audio format from the microphone."
        }
    }
}

final class AudioPipeline: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct AudioChunk {
        let sampleBuffer: CMSampleBuffer
        let monoSamples: [Float]
        let sampleRate: Double
    }

    var onChunk: ((AudioChunk) -> Void)?

    private let sessionQueue      = DispatchQueue(label: "net.zainzafar.yap.capture.session")
    private let sampleBufferQueue = DispatchQueue(label: "net.zainzafar.yap.capture.samples")

    private var captureSession = AVCaptureSession()
    private var audioOutput    = AVCaptureAudioDataOutput()
    private var deviceInput: AVCaptureDeviceInput?

    func start(deviceUID: String?) throws {
        var thrownError: Error?
        sessionQueue.sync {
            do {
                try configureSession(deviceUID: deviceUID)
                captureSession.startRunning()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
    }

    func stop() {
        sessionQueue.sync {
            audioOutput.setSampleBufferDelegate(nil, queue: nil)
            if captureSession.isRunning { captureSession.stopRunning() }

            captureSession.beginConfiguration()
            if let input = deviceInput {
                captureSession.removeInput(input)
                deviceInput = nil
            }
            captureSession.removeOutput(audioOutput)
            captureSession.commitConfiguration()

            audioOutput = AVCaptureAudioDataOutput()
        }
    }

    private func configureSession(deviceUID: String?) throws {
        let device: AVCaptureDevice?
        if let uid = deviceUID, !uid.isEmpty {
            device = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone], mediaType: .audio, position: .unspecified
            ).devices.first { $0.uniqueID == uid }
        } else {
            device = AVCaptureDevice.default(for: .audio)
        }
        guard let device else { throw AudioCaptureError.deviceUnavailable }

        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: device) }
        catch { throw AudioCaptureError.inputCreationFailed }

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)

        captureSession.beginConfiguration()
        if let existing = deviceInput {
            captureSession.removeInput(existing)
            deviceInput = nil
        }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw AudioCaptureError.inputCreationFailed
        }
        captureSession.addInput(input)

        guard captureSession.canAddOutput(output) else {
            captureSession.removeInput(input)
            captureSession.commitConfiguration()
            throw AudioCaptureError.outputCreationFailed
        }
        captureSession.addOutput(output)
        captureSession.commitConfiguration()

        deviceInput = input
        audioOutput = output
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        do {
            let (mono, rate) = try extractMonoSamples(from: sampleBuffer)
            onChunk?(AudioChunk(sampleBuffer: sampleBuffer, monoSamples: mono, sampleRate: rate))
        } catch { return }
    }

    private var scratchBuffer: [Float] = []

    private func extractMonoSamples(from sampleBuffer: CMSampleBuffer) throws -> ([Float], Double) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            throw AudioCaptureError.unsupportedAudioFormat
        }
        let asbd = asbdPtr.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM else {
            throw AudioCaptureError.unsupportedAudioFormat
        }

        var blockBuffer: CMBlockBuffer?
        let listSize = MemoryLayout<AudioBufferList>.size + (Int(asbd.mChannelsPerFrame) - 1) * MemoryLayout<AudioBuffer>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }

        let abl = raw.assumingMemoryBound(to: AudioBufferList.self)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: abl,
            bufferListSize: listSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { throw AudioCaptureError.unsupportedAudioFormat }

        let frameCount    = Int(CMSampleBufferGetNumSamples(sampleBuffer))
        let channelCount  = max(Int(asbd.mChannelsPerFrame), 1)
        let isFloat       = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSigned      = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        if scratchBuffer.count < frameCount {
            scratchBuffer = [Float](repeating: 0, count: frameCount)
        }
        let n = vDSP_Length(frameCount)
        var zero: Float = 0
        vDSP_vfill(&zero, &scratchBuffer, 1, n)

        let ptr = UnsafeMutableAudioBufferListPointer(abl)

        if isFloat && asbd.mBitsPerChannel == 32 {
            if isNonInterleaved {
                for ch in 0..<min(channelCount, ptr.count) {
                    guard let data = ptr[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    vDSP_vadd(scratchBuffer, 1, data, 1, &scratchBuffer, 1, n)
                }
            } else {
                guard let data = ptr.first?.mData?.assumingMemoryBound(to: Float.self) else {
                    throw AudioCaptureError.unsupportedAudioFormat
                }
                if channelCount == 1 {
                    memcpy(&scratchBuffer, data, frameCount * MemoryLayout<Float>.size)
                } else {
                    for ch in 0..<channelCount {
                        vDSP_vadd(scratchBuffer, 1, data.advanced(by: ch), vDSP_Stride(channelCount), &scratchBuffer, 1, n)
                    }
                }
            }
        } else if isSigned && asbd.mBitsPerChannel == 16 {
            var conv = [Float](repeating: 0, count: frameCount)
            if isNonInterleaved {
                for ch in 0..<min(channelCount, ptr.count) {
                    guard let data = ptr[ch].mData?.assumingMemoryBound(to: Int16.self) else { continue }
                    vDSP_vflt16(data, 1, &conv, 1, n)
                    vDSP_vadd(scratchBuffer, 1, conv, 1, &scratchBuffer, 1, n)
                }
            } else {
                guard let data = ptr.first?.mData?.assumingMemoryBound(to: Int16.self) else {
                    throw AudioCaptureError.unsupportedAudioFormat
                }
                for ch in 0..<channelCount {
                    vDSP_vflt16(data.advanced(by: ch), vDSP_Stride(channelCount), &conv, 1, n)
                    vDSP_vadd(scratchBuffer, 1, conv, 1, &scratchBuffer, 1, n)
                }
            }
            var scale = Float(1) / Float(Int16.max)
            vDSP_vsmul(scratchBuffer, 1, &scale, &scratchBuffer, 1, n)
        } else if isSigned && asbd.mBitsPerChannel == 32 {
            var conv = [Float](repeating: 0, count: frameCount)
            if isNonInterleaved {
                for ch in 0..<min(channelCount, ptr.count) {
                    guard let data = ptr[ch].mData?.assumingMemoryBound(to: Int32.self) else { continue }
                    vDSP_vflt32(data, 1, &conv, 1, n)
                    vDSP_vadd(scratchBuffer, 1, conv, 1, &scratchBuffer, 1, n)
                }
            } else {
                guard let data = ptr.first?.mData?.assumingMemoryBound(to: Int32.self) else {
                    throw AudioCaptureError.unsupportedAudioFormat
                }
                for ch in 0..<channelCount {
                    vDSP_vflt32(data.advanced(by: ch), vDSP_Stride(channelCount), &conv, 1, n)
                    vDSP_vadd(scratchBuffer, 1, conv, 1, &scratchBuffer, 1, n)
                }
            }
            var scale = Float(1) / Float(Int32.max)
            vDSP_vsmul(scratchBuffer, 1, &scale, &scratchBuffer, 1, n)
        } else {
            throw AudioCaptureError.unsupportedAudioFormat
        }

        if channelCount > 1 {
            var div = Float(channelCount)
            vDSP_vsdiv(scratchBuffer, 1, &div, &scratchBuffer, 1, n)
        }

        return (Array(scratchBuffer.prefix(frameCount)), asbd.mSampleRate)
    }
}
