import 'dart:io';
import 'dart:typed_data';

/// Wraps raw PCM audio data in a valid RIFF/WAV container header.
///
/// The `record` package's `pcm16bits` encoder produces raw PCM samples
/// without a WAV header, making the file unplayable by standard players
/// and unrecognized by ASR APIs. This class adds the minimal 44-byte
/// RIFF/WAV header required for playback and API compatibility.
class WavEncoder {
  static const _riff = 'RIFF';
  static const _wave = 'WAVE';
  static const _fmt = 'fmt ';
  static const _data = 'data';
  static const _headerSize = 44;
  static const _defaultSampleRate = 16000;
  static const _defaultNumChannels = 1;
  static const _defaultBitsPerSample = 16;

  static Future<String> convertToWav(String pcmPath) async {
    final pcmFile = File(pcmPath);
    final pcmBytes = await pcmFile.readAsBytes();

    if (_hasRiffHeader(pcmBytes)) return pcmPath;

    final header = _buildWavHeader(
      pcmDataSize: pcmBytes.length,
      sampleRate: _defaultSampleRate,
      numChannels: _defaultNumChannels,
      bitsPerSample: _defaultBitsPerSample,
    );

    final wavPath = pcmPath.replaceAll('.pcm', '.wav');
    await File(wavPath).writeAsBytes(Uint8List.fromList(header + pcmBytes));
    return wavPath;
  }

  static bool _hasRiffHeader(Uint8List bytes) =>
      bytes.length >= 4 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == _riff;

  static List<int> _buildWavHeader({
    required int pcmDataSize,
    required int sampleRate,
    required int numChannels,
    required int bitsPerSample,
  }) {
    final bytesPerSample = bitsPerSample ~/ 8;
    final blockAlign = numChannels * bytesPerSample;
    final byteRate = sampleRate * blockAlign;
    final fileSize = _headerSize + pcmDataSize;

    final buf = ByteData(_headerSize);
    int o = 0;

    void writeString(String s) {
      for (final c in s.codeUnits) {
        buf.setUint8(o++, c);
      }
    }

    void u16(int v) {
      buf.setUint16(o, v, Endian.little);
      o += 2;
    }

    void u32(int v) {
      buf.setUint32(o, v, Endian.little);
      o += 4;
    }

    writeString(_riff);
    u32(fileSize - 8);
    writeString(_wave);
    writeString(_fmt);
    u32(16); // PCM subchunk size
    u16(1); // audio format = PCM
    u16(numChannels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    writeString(_data);
    u32(pcmDataSize);

    return buf.buffer.asUint8List().toList();
  }
}
