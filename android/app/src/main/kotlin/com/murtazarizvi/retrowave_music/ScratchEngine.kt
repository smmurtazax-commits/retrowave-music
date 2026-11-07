package com.murtazarizvi.retrowave_music

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import java.io.File
import kotlin.math.floor

/**
 * Real-time scratch engine for the DJ Disc.
 *
 * The phone's normal media player cannot play audio backwards, so
 * real scratching needs the song as raw samples in memory and an
 * engine whose playhead the finger can drag in ANY direction.
 * This decodes the current song to mono PCM at 22,050 Hz (a 4-minute
 * song is about 10 MB — small, and slightly lo-fi is exactly what
 * real scratching sounds like anyway) and renders it through an
 * AudioTrack with the playhead advancing by a signed ratio:
 * +1.0 = normal speed, 0.0 = held record, negative = backspin —
 * with the actual sound, in real time.
 */
class ScratchEngine(private val context: Context) {

    companion object {
        const val SAMPLE_RATE = 22050
        private const val MAX_SECONDS = 480 // decode at most 8 minutes
    }

    @Volatile
    private var pcm: ShortArray? = null

    @Volatile
    var durationMs: Long = 0
        private set

    @Volatile
    private var playhead = 0.0 // in samples

    @Volatile
    private var targetRatio = 1.0

    @Volatile
    private var ratio = 1.0 // smoothed toward targetRatio

    @Volatile
    private var running = false

    private var track: AudioTrack? = null
    private var thread: Thread? = null

    /**
     * Decode [path] (or [uriString]) to the in-memory buffer.
     * Blocking — call off the main thread. Returns true on success.
     */
    fun prepare(path: String?, uriString: String?): Boolean {
        stopInternal()
        pcm = null
        durationMs = 0
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            val f = if (path != null) File(path) else null
            if (f != null && f.canRead()) {
                extractor.setDataSource(f.absolutePath)
            } else if (uriString != null) {
                extractor.setDataSource(context, Uri.parse(uriString), null)
            } else {
                return false
            }
            var trackIndex = -1
            var mime = ""
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val m = fmt.getString(MediaFormat.KEY_MIME) ?: ""
                if (m.startsWith("audio/")) {
                    trackIndex = i
                    mime = m
                    break
                }
            }
            if (trackIndex < 0) return false
            extractor.selectTrack(trackIndex)
            val format = extractor.getTrackFormat(trackIndex)
            val inRate =
                if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE))
                    format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                else 44100
            val channels =
                if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT))
                    format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                else 1
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            // Mono samples at the source rate, grown as needed.
            var mono = ShortArray(1 shl 20)
            var monoLen = 0
            fun pushMono(s: Short) {
                if (monoLen >= mono.size) mono = mono.copyOf(mono.size * 2)
                mono[monoLen++] = s
            }

            val info = MediaCodec.BufferInfo()
            var sawInputEos = false
            var sawOutputEos = false
            val maxFrames = MAX_SECONDS * inRate
            while (!sawOutputEos && monoLen < maxFrames) {
                if (!sawInputEos) {
                    val inIdx = codec.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) {
                        val inBuf = codec.getInputBuffer(inIdx)!!
                        val sz = extractor.readSampleData(inBuf, 0)
                        if (sz < 0) {
                            codec.queueInputBuffer(
                                inIdx, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            sawInputEos = true
                        } else {
                            codec.queueInputBuffer(
                                inIdx, 0, sz, extractor.sampleTime, 0
                            )
                            extractor.advance()
                        }
                    }
                }
                val outIdx = codec.dequeueOutputBuffer(info, 10_000)
                if (outIdx >= 0) {
                    val outBuf = codec.getOutputBuffer(outIdx)!!
                    outBuf.position(info.offset)
                    outBuf.limit(info.offset + info.size)
                    val outFmt = codec.outputFormat
                    val enc =
                        if (outFmt.containsKey(MediaFormat.KEY_PCM_ENCODING))
                            outFmt.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        else AudioFormat.ENCODING_PCM_16BIT
                    if (enc == AudioFormat.ENCODING_PCM_FLOAT) {
                        val fb = outBuf.asFloatBuffer()
                        while (fb.remaining() >= channels) {
                            var sum = 0f
                            for (c in 0 until channels) sum += fb.get()
                            val v = (sum / channels * 32767f).toInt()
                                .coerceIn(-32768, 32767)
                            pushMono(v.toShort())
                        }
                    } else {
                        val sb = outBuf.asShortBuffer()
                        while (sb.remaining() >= channels) {
                            var sum = 0
                            for (c in 0 until channels) sum += sb.get().toInt()
                            pushMono((sum / channels).toShort())
                        }
                    }
                    codec.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        sawOutputEos = true
                    }
                }
            }
            codec.stop()
            codec.release()
            codec = null
            extractor.release()
            if (monoLen == 0) return false

            val out: ShortArray
            if (inRate == SAMPLE_RATE) {
                out = mono.copyOf(monoLen)
            } else {
                val outLen = (monoLen.toLong() * SAMPLE_RATE / inRate).toInt()
                out = ShortArray(outLen)
                val step = inRate.toDouble() / SAMPLE_RATE
                for (i in 0 until outLen) {
                    val src = i * step
                    val i0 = floor(src).toInt()
                    val frac = src - i0
                    val a = mono[i0.coerceAtMost(monoLen - 1)].toDouble()
                    val b = mono[(i0 + 1).coerceAtMost(monoLen - 1)].toDouble()
                    out[i] = (a + (b - a) * frac).toInt().toShort()
                }
            }
            pcm = out
            durationMs = out.size * 1000L / SAMPLE_RATE
            return true
        } catch (e: Exception) {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            try {
                codec?.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
            pcm = null
            durationMs = 0
            return false
        }
    }

    /** Start rendering from [startMs]. Returns false if unprepared. */
    fun start(startMs: Long): Boolean {
        val buf = pcm ?: return false
        stopInternal()
        playhead = (startMs.coerceIn(0, durationMs) * SAMPLE_RATE / 1000.0)
            .coerceIn(0.0, (buf.size - 2).toDouble())
        ratio = 1.0
        targetRatio = 1.0
        val minBuf = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val t = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(minBuf, SAMPLE_RATE))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track = t
        running = true
        t.play()
        thread = Thread { renderLoop(t, buf) }.apply {
            name = "RetroWaveScratch"
            isDaemon = true
            start()
        }
        return true
    }

    private fun renderLoop(t: AudioTrack, buf: ShortArray) {
        val chunk = ShortArray(512)
        val last = buf.size - 2
        while (running) {
            ratio += (targetRatio - ratio) * 0.35
            ratio = ratio.coerceIn(-3.0, 3.0)
            for (i in chunk.indices) {
                val p = playhead
                val pinned =
                    (p >= last && ratio > 0) || (p <= 0.0 && ratio < 0)
                if (pinned) {
                    chunk[i] = 0
                } else {
                    val i0 = floor(p).toInt().coerceIn(0, last)
                    val frac = p - floor(p)
                    val a = buf[i0].toInt()
                    val b = buf[i0 + 1].toInt()
                    chunk[i] = (a + (b - a) * frac).toInt().toShort()
                }
                playhead += ratio
                if (playhead < 0) playhead = 0.0
                if (playhead > last) playhead = last.toDouble()
            }
            val written = t.write(chunk, 0, chunk.size, AudioTrack.WRITE_BLOCKING)
            if (written < 0) break
        }
    }

    fun setRatio(r: Double) {
        targetRatio = r.coerceIn(-3.0, 3.0)
    }

    fun playheadMs(): Long =
        if (pcm == null) 0 else (playhead * 1000 / SAMPLE_RATE).toLong()

    /** Stop rendering; returns the final playhead in ms. */
    fun stop(): Long {
        val ms = playheadMs()
        stopInternal()
        return ms
    }

    private fun stopInternal() {
        running = false
        try {
            thread?.join(400)
        } catch (_: Exception) {
        }
        thread = null
        try {
            track?.stop()
        } catch (_: Exception) {
        }
        try {
            track?.release()
        } catch (_: Exception) {
        }
        track = null
    }

    fun releaseAll() {
        stopInternal()
        pcm = null
        durationMs = 0
    }
}
