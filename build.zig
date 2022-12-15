const std = @import("std");
const Pkg = std.build.Pkg;
const Builder = @import("std").build.Builder;
const freetype = @import("libs/mach/libs/freetype/build.zig");

const mbedtls = @import("libs/zig-mbedtls/mbedtls.zig");
const libssh2 = @import("libs/zig-libssh2/libssh2.zig");
const libcurl = @import("libs/zig-libcurl/libcurl.zig");
const libzlib = @import("libs/zig-zlib/zlib.zig");
const libxml2 = @import("libs/zig-libxml2/libxml2.zig");

const Packages = struct {
    // Declared here because submodule may not be cloned at the time build.zig runs.
    const zmath = std.build.Pkg{
        .name = "zmath",
        .source = .{ .path = "libs/zmath/src/zmath.zig" },
    };
};

pub fn build(b: *Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // mach example
    {
        const name = "mach-test";
        const mach = @import("libs/mach/build.zig");
        const example_app = try mach.App.init(
            b,
            .{
                .name = "mach-test",
                .src = "mach-test.zig",
                .target = target,
                .deps = &[_]Pkg{ Packages.zmath, freetype.pkg },
            },
        );
        example_app.setBuildMode(mode);
        freetype.link(example_app.b, example_app.step, .{});
        try example_app.link(.{});

        const compile_step = b.step("compile-" ++ name, "Compile " ++ name);
        compile_step.dependOn(&b.addInstallArtifact(example_app.step).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = try example_app.run();
        run_cmd.dependOn(compile_step);

        const run_step = b.step(name, "Run " ++ name);
        run_step.dependOn(run_cmd);
    }

    // sdl test
    {
        const exe = b.addExecutable("sdl-test", "sdl-test" ++ ".zig");

        exe.addPackage(freetype.pkg);
        freetype.link(b, exe, .{});

        exe.linkSystemLibrary("SDL2");
        //exe.addIncludePath("/home/dvanderson/SDL/build/include");
        //exe.addObjectFile("/home/dvanderson/SDL/build/lib/libSDL2.a");

        if (target.isDarwin()) {
            exe.linkSystemLibrary("z");
            exe.linkSystemLibrary("bz2");
            exe.linkSystemLibrary("iconv");
            exe.linkFramework("AppKit");
            exe.linkFramework("AudioToolbox");
            exe.linkFramework("Carbon");
            exe.linkFramework("Cocoa");
            exe.linkFramework("CoreAudio");
            exe.linkFramework("CoreFoundation");
            exe.linkFramework("CoreGraphics");
            exe.linkFramework("CoreHaptics");
            exe.linkFramework("CoreVideo");
            exe.linkFramework("ForceFeedback");
            exe.linkFramework("GameController");
            exe.linkFramework("IOKit");
            exe.linkFramework("Metal");
        }

        exe.setTarget(target);
        exe.setBuildMode(mode);

        const compile_step = b.step("compile-" ++ "sdl-test", "Compile " ++ "sdl-test");
        compile_step.dependOn(&b.addInstallArtifact(exe).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = exe.run();
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step("sdl-test", "Run " ++ "sdl-test");
        run_step.dependOn(&run_cmd.step);
    }

    // podcast example application
    {
        const exe = b.addExecutable("podcast", "podcast" ++ ".zig");
        exe.linkSystemLibrary("SDL2");

        exe.addPackage(freetype.pkg);
        freetype.link(b, exe, .{ .freetype = .{ .use_system_zlib = true } });

        const sqlite = b.addStaticLibrary("sqlite", null);
        sqlite.addCSourceFile("libs/zig-sqlite/c/sqlite3.c", &[_][]const u8{"-std=c99"});
        sqlite.linkLibC();

        exe.linkLibrary(sqlite);
        exe.addPackagePath("sqlite", "libs/zig-sqlite/sqlite.zig");
        exe.addIncludePath("libs/zig-sqlite/c");

        const tls = mbedtls.create(b, target, mode);
        tls.link(exe);

        const ssh2 = libssh2.create(b, target, mode);
        tls.link(ssh2.step);
        ssh2.link(exe);

        const zlib = libzlib.create(b, target, mode);
        zlib.link(exe, .{});

        const curl = try libcurl.create(b, target, mode);
        tls.link(curl.step);
        ssh2.link(curl.step);
        curl.link(exe, .{ .import_name = "curl" });

        const libxml = try libxml2.create(b, target, mode, .{
            .iconv = false,
            .lzma = false,
            .zlib = true,
        });

        libxml.link(exe);

        {
            var ffmpeg = b.addStaticLibrary("ffmpeg", null);
            ffmpeg.setTarget(target);
            ffmpeg.setBuildMode(mode);
            ffmpeg.linkLibC();
            ffmpeg.addIncludePath(root_path);
            ffmpeg.addIncludePath(extra_include);
            ffmpeg.addCSourceFiles(srcs, flags);

            exe.addIncludePath(root_path);
            exe.linkLibrary(ffmpeg);
        }

        if (target.isDarwin()) {
            exe.linkSystemLibrary("z");
            exe.linkSystemLibrary("bz2");
            exe.linkSystemLibrary("iconv");
            exe.linkFramework("AppKit");
            exe.linkFramework("AudioToolbox");
            exe.linkFramework("Carbon");
            exe.linkFramework("Cocoa");
            exe.linkFramework("CoreAudio");
            exe.linkFramework("CoreFoundation");
            exe.linkFramework("CoreGraphics");
            exe.linkFramework("CoreHaptics");
            exe.linkFramework("CoreVideo");
            exe.linkFramework("ForceFeedback");
            exe.linkFramework("GameController");
            exe.linkFramework("IOKit");
            exe.linkFramework("Metal");
        }

        exe.setTarget(target);
        exe.setBuildMode(mode);

        const compile_step = b.step("compile-" ++ "podcast", "Compile " ++ "podcast");
        compile_step.dependOn(&b.addInstallArtifact(exe).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = exe.run();
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step("podcast", "Run " ++ "podcast");
        run_step.dependOn(&run_cmd.step);
    }
}

fn root() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const root_path = root() ++ "/libs/ffmpeg/";
const extra_include = root() ++ "/libs/ffmpeg_include/";

// ffmpeg stuff configured like this: ../configure --disable-encoders --disable-decoders --disable-parsers --disable-demuxers --disable-muxers --disable-bsfs --disable-indevs --disable-outdevs --disable-filters --enable-decoder=mp3 --enable-demuxer=mp3,pcm* --enable-parser=mpegaudio --enable-muxer=pcm* --enable-filter=atempo --disable-v4l2_m2m --disable-iconv --disable-libxcb --disable-lzma --disable-sdl2 --disable-zlib --disable-x86asm

const flags = &[_][]const u8{
    "-std=c11",
    "-D_XOPEN_SOURCE=600",

    // HAVE_AV_CONFIG_H is necessary, even though that file avconfig.h only has
    // the following 2 things in it
    "-DHAVE_AV_CONFIG_H",
    "-DHAVE_BIGENDIAN=0",
    "-DAV_HAVE_FAST_UNALIGNED=1",
};

const srcs = &.{
    root_path ++ "libavutil/x86/cpu.c",
    root_path ++ "libavutil/x86/imgutils_init.c",
    root_path ++ "libavcodec/x86/mpegaudiodsp.c",
    root_path ++ "libavcodec/x86/dct_init.c",
    root_path ++ "libavcodec/x86/fft_init.c",
    root_path ++ "libswresample/x86/audio_convert_init.c",
    root_path ++ "libswresample/x86/rematrix_init.c",
    root_path ++ "libswresample/x86/resample_init.c",

    root_path ++ "libavutil/adler32.c",
    root_path ++ "libavutil/aes_ctr.c",
    root_path ++ "libavutil/aes.c",
    root_path ++ "libavutil/audio_fifo.c",
    root_path ++ "libavutil/avsscanf.c",
    root_path ++ "libavutil/avstring.c",
    root_path ++ "libavutil/base64.c",
    root_path ++ "libavutil/blowfish.c",
    root_path ++ "libavutil/bprint.c",
    root_path ++ "libavutil/buffer.c",
    root_path ++ "libavutil/camellia.c",
    root_path ++ "libavutil/cast5.c",
    root_path ++ "libavutil/channel_layout.c",
    root_path ++ "libavutil/color_utils.c",
    root_path ++ "libavutil/cpu.c",
    root_path ++ "libavutil/crc.c",
    root_path ++ "libavutil/csp.c",
    root_path ++ "libavutil/des.c",
    root_path ++ "libavutil/detection_bbox.c",
    root_path ++ "libavutil/dict.c",
    root_path ++ "libavutil/display.c",
    root_path ++ "libavutil/dovi_meta.c",
    root_path ++ "libavutil/downmix_info.c",
    root_path ++ "libavutil/encryption_info.c",
    root_path ++ "libavutil/error.c",
    root_path ++ "libavutil/eval.c",
    root_path ++ "libavutil/fifo.c",
    root_path ++ "libavutil/file.c",
    root_path ++ "libavutil/file_open.c",
    root_path ++ "libavutil/film_grain_params.c",
    root_path ++ "libavutil/fixed_dsp.c",
    root_path ++ "libavutil/float_dsp.c",
    root_path ++ "libavutil/frame.c",
    root_path ++ "libavutil/hash.c",
    root_path ++ "libavutil/hdr_dynamic_metadata.c",
    root_path ++ "libavutil/hdr_dynamic_vivid_metadata.c",
    root_path ++ "libavutil/hmac.c",
    root_path ++ "libavutil/hwcontext.c",
    root_path ++ "libavutil/hwcontext_stub.c",
    root_path ++ "libavutil/imgutils.c",
    root_path ++ "libavutil/integer.c",
    root_path ++ "libavutil/intmath.c",
    root_path ++ "libavutil/lfg.c",
    root_path ++ "libavutil/lls.c",
    root_path ++ "libavutil/log2_tab.c",
    root_path ++ "libavutil/log.c",
    root_path ++ "libavutil/lzo.c",
    root_path ++ "libavutil/mastering_display_metadata.c",
    root_path ++ "libavutil/mathematics.c",
    root_path ++ "libavutil/md5.c",
    root_path ++ "libavutil/mem.c",
    root_path ++ "libavutil/murmur3.c",
    root_path ++ "libavutil/opt.c",
    root_path ++ "libavutil/parseutils.c",
    root_path ++ "libavutil/pixdesc.c",
    root_path ++ "libavutil/pixelutils.c",
    root_path ++ "libavutil/random_seed.c",
    root_path ++ "libavutil/rational.c",
    root_path ++ "libavutil/rc4.c",
    root_path ++ "libavutil/reverse.c",
    root_path ++ "libavutil/ripemd.c",
    root_path ++ "libavutil/samplefmt.c",
    root_path ++ "libavutil/sha512.c",
    root_path ++ "libavutil/sha.c",
    root_path ++ "libavutil/slicethread.c",
    root_path ++ "libavutil/spherical.c",
    root_path ++ "libavutil/stereo3d.c",
    root_path ++ "libavutil/tea.c",
    root_path ++ "libavutil/threadmessage.c",
    root_path ++ "libavutil/timecode.c",
    root_path ++ "libavutil/time.c",
    root_path ++ "libavutil/tree.c",
    root_path ++ "libavutil/twofish.c",
    root_path ++ "libavutil/tx_double.c",
    root_path ++ "libavutil/tx_float.c",
    root_path ++ "libavutil/tx_int32.c",
    root_path ++ "libavutil/tx.c",
    root_path ++ "libavutil/utils.c",
    root_path ++ "libavutil/uuid.c",
    root_path ++ "libavutil/version.c",
    root_path ++ "libavutil/video_enc_params.c",
    root_path ++ "libavutil/xga_font_data.c",
    root_path ++ "libavutil/xtea.c",

    root_path ++ "libavdevice/alldevices.c",
    root_path ++ "libavdevice/avdevice.c",
    root_path ++ "libavdevice/utils.c",
    root_path ++ "libavdevice/version.c",

    root_path ++ "libavfilter/af_atempo.c",
    root_path ++ "libavfilter/allfilters.c",
    root_path ++ "libavfilter/audio.c",
    root_path ++ "libavfilter/avfilter.c",
    root_path ++ "libavfilter/avfiltergraph.c",
    root_path ++ "libavfilter/buffersink.c",
    root_path ++ "libavfilter/buffersrc.c",
    root_path ++ "libavfilter/colorspace.c",
    root_path ++ "libavfilter/drawutils.c",
    root_path ++ "libavfilter/fifo.c",
    root_path ++ "libavfilter/formats.c",
    root_path ++ "libavfilter/framepool.c",
    root_path ++ "libavfilter/framequeue.c",
    root_path ++ "libavfilter/graphdump.c",
    root_path ++ "libavfilter/graphparser.c",
    root_path ++ "libavfilter/pthread.c",
    root_path ++ "libavfilter/version.c",
    root_path ++ "libavfilter/video.c",

    root_path ++ "libavformat/allformats.c",
    root_path ++ "libavformat/asf_tags.c",
    root_path ++ "libavformat/async.c",
    root_path ++ "libavformat/avformat.c",
    root_path ++ "libavformat/aviobuf.c",
    root_path ++ "libavformat/avio.c",
    root_path ++ "libavformat/cache.c",
    root_path ++ "libavformat/concat.c",
    root_path ++ "libavformat/crypto.c",
    root_path ++ "libavformat/data_uri.c",
    root_path ++ "libavformat/demux.c",
    root_path ++ "libavformat/demux_utils.c",
    root_path ++ "libavformat/dump.c",
    root_path ++ "libavformat/dv.c",
    root_path ++ "libavformat/file.c",
    root_path ++ "libavformat/format.c",
    root_path ++ "libavformat/ftp.c",
    root_path ++ "libavformat/gopher.c",
    root_path ++ "libavformat/hlsproto.c",
    root_path ++ "libavformat/httpauth.c",
    root_path ++ "libavformat/http.c",
    root_path ++ "libavformat/icecast.c",
    root_path ++ "libavformat/id3v1.c",
    root_path ++ "libavformat/id3v2.c",
    root_path ++ "libavformat/ip.c",
    root_path ++ "libavformat/isom_tags.c",
    root_path ++ "libavformat/md5proto.c",
    root_path ++ "libavformat/metadata.c",
    root_path ++ "libavformat/mmsh.c",
    root_path ++ "libavformat/mms.c",
    root_path ++ "libavformat/mmst.c",
    root_path ++ "libavformat/mp3dec.c",
    root_path ++ "libavformat/mux.c",
    root_path ++ "libavformat/mux_utils.c",
    root_path ++ "libavformat/network.c",
    root_path ++ "libavformat/options.c",
    root_path ++ "libavformat/os_support.c",
    root_path ++ "libavformat/pcmdec.c",
    root_path ++ "libavformat/pcmenc.c",
    root_path ++ "libavformat/pcm.c",
    root_path ++ "libavformat/prompeg.c",
    root_path ++ "libavformat/protocols.c",
    root_path ++ "libavformat/rawenc.c",
    root_path ++ "libavformat/replaygain.c",
    root_path ++ "libavformat/riff.c",
    root_path ++ "libavformat/rtmpdigest.c",
    root_path ++ "libavformat/rtmphttp.c",
    root_path ++ "libavformat/rtmppkt.c",
    root_path ++ "libavformat/rtmpproto.c",
    root_path ++ "libavformat/rtpproto.c",
    root_path ++ "libavformat/sdp.c",
    root_path ++ "libavformat/seek.c",
    root_path ++ "libavformat/srtp.c",
    root_path ++ "libavformat/srtpproto.c",
    root_path ++ "libavformat/subfile.c",
    root_path ++ "libavformat/tcp.c",
    root_path ++ "libavformat/tee_common.c",
    root_path ++ "libavformat/teeproto.c",
    root_path ++ "libavformat/udp.c",
    root_path ++ "libavformat/unix.c",
    root_path ++ "libavformat/urldecode.c",
    root_path ++ "libavformat/url.c",
    root_path ++ "libavformat/utils.c",
    root_path ++ "libavformat/version.c",

    root_path ++ "libavcodec/ac3_parser.c",
    root_path ++ "libavcodec/adts_parser.c",
    root_path ++ "libavcodec/allcodecs.c",
    root_path ++ "libavcodec/avcodec.c",
    root_path ++ "libavcodec/avdct.c",
    root_path ++ "libavcodec/avfft.c",
    root_path ++ "libavcodec/avpacket.c",
    root_path ++ "libavcodec/bitstream_filters.c",
    root_path ++ "libavcodec/bitstream.c",
    root_path ++ "libavcodec/bsf.c",
    root_path ++ "libavcodec/codec_desc.c",
    root_path ++ "libavcodec/codec_par.c",
    root_path ++ "libavcodec/d3d11va.c",
    root_path ++ "libavcodec/dct32_fixed.c",
    root_path ++ "libavcodec/dct32_float.c",
    root_path ++ "libavcodec/dct.c",
    root_path ++ "libavcodec/decode.c",
    root_path ++ "libavcodec/dirac.c",
    root_path ++ "libavcodec/dv_profile.c",
    root_path ++ "libavcodec/encode.c",
    root_path ++ "libavcodec/faandct.c",
    root_path ++ "libavcodec/faanidct.c",
    root_path ++ "libavcodec/fdctdsp.c",
    root_path ++ "libavcodec/fft_fixed_32.c",
    root_path ++ "libavcodec/fft_float.c",
    root_path ++ "libavcodec/fft_init_table.c",
    root_path ++ "libavcodec/get_buffer.c",
    root_path ++ "libavcodec/idctdsp.c",
    root_path ++ "libavcodec/imgconvert.c",
    root_path ++ "libavcodec/jfdctfst.c",
    root_path ++ "libavcodec/jfdctint.c",
    root_path ++ "libavcodec/jni.c",
    root_path ++ "libavcodec/jrevdct.c",
    root_path ++ "libavcodec/mathtables.c",
    root_path ++ "libavcodec/mediacodec.c",
    root_path ++ "libavcodec/mpeg12framerate.c",
    root_path ++ "libavcodec/mpegaudiodata.c",
    root_path ++ "libavcodec/mpegaudiodec_common.c",
    root_path ++ "libavcodec/mpegaudiodec_fixed.c",
    root_path ++ "libavcodec/mpegaudiodecheader.c",
    root_path ++ "libavcodec/mpegaudiodsp_data.c",
    root_path ++ "libavcodec/mpegaudiodsp_fixed.c",
    root_path ++ "libavcodec/mpegaudiodsp_float.c",
    root_path ++ "libavcodec/mpegaudiodsp.c",
    root_path ++ "libavcodec/mpegaudio.c",
    root_path ++ "libavcodec/mpegaudio_parser.c",
    root_path ++ "libavcodec/mpegaudiotabs.c",
    root_path ++ "libavcodec/options.c",
    root_path ++ "libavcodec/parser.c",
    root_path ++ "libavcodec/parsers.c",
    root_path ++ "libavcodec/profiles.c",
    root_path ++ "libavcodec/pthread_frame.c",
    root_path ++ "libavcodec/pthread.c",
    root_path ++ "libavcodec/pthread_slice.c",
    root_path ++ "libavcodec/qsv_api.c",
    root_path ++ "libavcodec/raw.c",
    root_path ++ "libavcodec/rdft.c",
    root_path ++ "libavcodec/simple_idct.c",
    root_path ++ "libavcodec/to_upper4.c",
    root_path ++ "libavcodec/utils.c",
    root_path ++ "libavcodec/version.c",
    root_path ++ "libavcodec/vlc.c",
    root_path ++ "libavcodec/vorbis_parser.c",
    root_path ++ "libavcodec/xiph.c",

    root_path ++ "libswresample/audioconvert.c",
    root_path ++ "libswresample/dither.c",
    root_path ++ "libswresample/options.c",
    root_path ++ "libswresample/rematrix.c",
    root_path ++ "libswresample/resample_dsp.c",
    root_path ++ "libswresample/resample.c",
    root_path ++ "libswresample/swresample_frame.c",
    root_path ++ "libswresample/swresample.c",
    root_path ++ "libswresample/version.c",
};
