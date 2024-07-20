const std = @import("std");
const mach = @import("mach");
const gobject_build = @import("gobject");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_dep = b.dependency("sqlite", .{ .SQLITE_ENABLE_RTREE = true });
    const sqlite = sqlite_dep.module("sqlite");

    const mbedtls_dep = b.dependency("mbedtls", .{});
    const nng_dep = b.dependency("nng", .{});

    const nng = b.addModule("nng", .{
        .root_source_file = b.path("nng/lib.zig"),
    });

    nng.addIncludePath(mbedtls_dep.path("include"));
    nng.addCSourceFiles(.{
        .root = mbedtls_dep.path("library"),
        .files = &.{
            "x509_create.c",
            "x509_crt.c",
            "psa_crypto_client.c",
            "aes.c",
            "psa_crypto_slot_management.c",
            "md4.c",
            "ssl_srv.c",
            "camellia.c",
            "constant_time.c",
            "pk_wrap.c",
            "pk.c",
            "psa_crypto_driver_wrappers.c",
            "ecdh.c",
            "ssl_tls.c",
            "x509_crl.c",
            "cipher_wrap.c",
            "chacha20.c",
            "psa_crypto_rsa.c",
            "des.c",
            "ssl_cookie.c",
            "ctr_drbg.c",
            "psa_crypto_mac.c",
            "aesni.c",
            "dhm.c",
            "ssl_cache.c",
            "ssl_ciphersuites.c",
            "hmac_drbg.c",
            "rsa.c",
            "ssl_ticket.c",
            "asn1parse.c",
            "mps_trace.c",
            "certs.c",
            "pkwrite.c",
            "gcm.c",
            "sha1.c",
            "asn1write.c",
            "havege.c",
            "ccm.c",
            "version_features.c",
            "aria.c",
            "psa_crypto_cipher.c",
            "entropy_poll.c",
            "x509write_csr.c",
            "platform.c",
            "cmac.c",
            "bignum.c",
            "pkparse.c",
            "ssl_msg.c",
            "debug.c",
            "ripemd160.c",
            "ssl_cli.c",
            "blowfish.c",
            "rsa_internal.c",
            "pkcs5.c",
            "pem.c",
            "oid.c",
            "error.c",
            "md2.c",
            "x509_csr.c",
            "psa_its_file.c",
            "psa_crypto.c",
            "platform_util.c",
            "psa_crypto_se.c",
            "pkcs11.c",
            "base64.c",
            "memory_buffer_alloc.c",
            "mps_reader.c",
            "psa_crypto_aead.c",
            "ecp.c",
            "version.c",
            "x509.c",
            "chachapoly.c",
            "ssl_tls13_keys.c",
            "sha256.c",
            "ecp_curves.c",
            "md5.c",
            "arc4.c",
            "timing.c",
            "psa_crypto_ecp.c",
            "psa_crypto_storage.c",
            "poly1305.c",
            "xtea.c",
            "x509write_crt.c",
            "hkdf.c",
            "threading.c",
            "padlock.c",
            "psa_crypto_hash.c",
            "pkcs12.c",
            "entropy.c",
            "net_sockets.c",
            "sha512.c",
            "md.c",
            "ecjpake.c",
            "cipher.c",
            "ecdsa.c",
            "nist_kw.c",
        },
    });

    nng.addSystemIncludePath(nng_dep.path("include"));
    nng.addIncludePath(nng_dep.path("src"));
    nng.addCSourceFiles(.{
        .root = nng_dep.path("src"),
        .flags = &.{"-DNNG_PLATFORM_POSIX", "-DNNG_SUPP_TLS", "-DNNG_TRANSPORT_IPC"},
        .files = &.{
            "nng.c",
            "core/aio.c",
            "core/device.c",
            "core/dialer.c",
            "core/file.c",
            "core/idhash.c",
            "core/init.c",
            "core/list.c",
            "core/listener.c",
            "core/lmq.c",
            "core/log.c",
            "core/message.c",
            "core/msgqueue.c",
            "core/options.c",
            "core/panic.c",
            "core/pipe.c",
            "core/pollable.c",
            "core/reap.c",
            "core/sockaddr.c",
            "core/socket.c",
            "core/sockfd.c",
            "core/stats.c",
            "core/stream.c",
            "core/strs.c",
            "core/taskq.c",
            "core/tcp.c",
            "core/thread.c",
            "core/url.c",

            "platform/posix/posix_alloc.c",
            "platform/posix/posix_atomic.c",
            "platform/posix/posix_clock.c",
            "platform/posix/posix_debug.c",
            "platform/posix/posix_file.c",
            "platform/posix/posix_ipcconn.c",
            "platform/posix/posix_ipcdial.c",
            "platform/posix/posix_ipclisten.c",
            "platform/posix/posix_peerid.c",
            "platform/posix/posix_pipe.c",
            "platform/posix/posix_pollq_epoll.c",
            "platform/posix/posix_pollq_kqueue.c",
            "platform/posix/posix_pollq_poll.c",
            "platform/posix/posix_pollq_port.c",
            "platform/posix/posix_rand_arc4random.c",
            "platform/posix/posix_rand_getrandom.c",
            "platform/posix/posix_rand_urandom.c",
            "platform/posix/posix_resolv_gai.c",
            "platform/posix/posix_sockaddr.c",
            "platform/posix/posix_socketpair.c",
            "platform/posix/posix_sockfd.c",
            "platform/posix/posix_tcpconn.c",
            "platform/posix/posix_tcpdial.c",
            "platform/posix/posix_tcplisten.c",
            "platform/posix/posix_thread.c",
            "platform/posix/posix_udp.c",

            // "supplemental/websocket/stub.c",
            "supplemental/websocket/websocket.c",
            "supplemental/util/idhash.c",
            "supplemental/util/options.c",
            "supplemental/base64/base64.c",
            "supplemental/tls/tls_common.c",
            "supplemental/tls/mbedtls/tls.c",
            "supplemental/http/http_schemes.c",
            "supplemental/http/http_server.c",
            "supplemental/http/http_msg.c",
            "supplemental/http/http_client.c",
            "supplemental/http/http_conn.c",
            "supplemental/http/http_chunk.c",
            "supplemental/http/http_public.c",
            "supplemental/sha1/sha1.c",

            "sp/transport.c",
            "sp/transport/inproc/inproc.c",
            "sp/transport/tls/tls.c",
            "sp/transport/tcp/tcp.c",
            "sp/transport/ipc/ipc.c",
            // "sp/transport/zerotier/zthash.c",
            // "sp/transport/zerotier/zerotier.c",
            "sp/transport/ws/websocket.c",
            "sp/transport/socket/sockfd.c",
            "sp/protocol/pair1/pair.c",
            "sp/protocol/pair1/pair1_poly.c",
            "sp/protocol/reqrep0/xreq.c",
            "sp/protocol/reqrep0/rep.c",
            "sp/protocol/reqrep0/xrep.c",
            "sp/protocol/reqrep0/req.c",
            "sp/protocol/pair0/pair.c",
            "sp/protocol/pubsub0/xsub.c",
            "sp/protocol/pubsub0/sub.c",
            "sp/protocol/pubsub0/pub.c",
            "sp/protocol/pipeline0/push.c",
            "sp/protocol/pipeline0/pull.c",
            "sp/protocol/survey0/xrespond.c",
            "sp/protocol/survey0/survey.c",
            "sp/protocol/survey0/xsurvey.c",
            "sp/protocol/survey0/respond.c",
            "sp/protocol/bus0/bus.c",
            "sp/protocol.c",
        },
    });

    // const engine = b.createModule(.{
    //     .root_source_file = b.path("engine/lib.zig"),
    //     .imports = &.{.{ .name = "sqlite", .module = sqlite }},
    // });

    const shm = b.createModule(.{
        .root_source_file = b.path("shm/lib.zig"),
    });

    const shared_object = b.createModule(.{
        .root_source_file = b.path("shared-object/lib.zig"),
        .imports = &.{.{ .name = "shm", .module = shm }},
    });

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
        .core = true,
    });

    const atlas = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "andromeda-atlas",
        .src = "atlas/App.zig",
        .target = target,
        .optimize = optimize,
        .deps = &.{
            .{ .name = "sqlite", .module = sqlite },
            .{ .name = "shared-object", .module = shared_object },
            .{ .name = "nng", .module = nng },
        },
    });

    if (b.args) |args| atlas.run.addArgs(args);

    const run_atlas = b.step("run-atlas", "Run the atlas");
    run_atlas.dependOn(&atlas.run.step);

    b.getInstallStep().dependOn(&atlas.install.step);

    // const control_panel = b.addExecutable(.{
    //     .name = "andromeda",
    //     .root_source_file = b.path("./src/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // control_panel.root_module.addImport("sqlite", sqlite);
    // control_panel.root_module.addImport("shared-object", shared_object);
    // control_panel.linkSystemLibrary("gtk4");
    // b.installArtifact(control_panel);

    // const control_panel_artifact = b.addRunArtifact(control_panel);
    // control_panel_artifact.step.dependOn(&atlas.install.step);

    // const run_control_panel = b.step("run", "Run the control panel");
    // run_control_panel.dependOn(&control_panel_artifact.step);

    const locale_dir: std.Build.InstallDir = .{ .custom = "share/locale" };
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "locale_dir", b.getInstallPath(locale_dir, ""));

    const control_panel = b.addExecutable(.{
        .name = "andromeda-control-panel",
        .root_source_file = b.path("./control-panel/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    control_panel.linkLibC();
    control_panel.root_module.addOptions("build_options", build_options);

    control_panel.root_module.addImport("sqlite", sqlite);
    control_panel.root_module.addImport("shared-object", shared_object);
    control_panel.root_module.addImport("nng", nng);
    control_panel.linkSystemLibrary("gtk4");

    const xml = b.dependency("xml", .{}).module("xml");
    const gobject = b.dependency("gobject", .{});
    const libintl = b.dependency("libintl", .{});

    control_panel.root_module.addImport("xml", xml);
    control_panel.root_module.addImport("glib", gobject.module("glib2"));
    control_panel.root_module.addImport("gobject", gobject.module("gobject2"));
    control_panel.root_module.addImport("gio", gobject.module("gio2"));
    control_panel.root_module.addImport("gdk", gobject.module("gdk4"));
    control_panel.root_module.addImport("gtk", gobject.module("gtk4"));
    control_panel.root_module.addImport("cairo", gobject.module("cairo1"));
    control_panel.root_module.addImport("pango", gobject.module("pango1"));
    control_panel.root_module.addImport("pangocairo", gobject.module("pangocairo1"));
    control_panel.root_module.addImport("adw", gobject.module("adw1"));
    control_panel.root_module.addImport("libintl", libintl.module("libintl"));

    const gresources = gobject_build.addCompileResources(b, target, b.path("control-panel/data/gresources.xml"));
    control_panel.root_module.addImport("gresources", gresources);

    b.installArtifact(control_panel);

    const control_panel_artifact = b.addRunArtifact(control_panel);
    control_panel_artifact.step.dependOn(&atlas.install.step);

    const run_control_panel = b.step("run", "Run the control panel");
    run_control_panel.dependOn(&control_panel_artifact.step);

    // Multi-threaded SQLite test
    const db_test = b.addExecutable(.{
        .name = "db-test",
        .root_source_file = b.path("./main.zig"),
        .target = target,
        .optimize = optimize,
    });

    db_test.root_module.addImport("glib", gobject.module("glib2"));
    db_test.root_module.addImport("gobject", gobject.module("gobject2"));
    db_test.root_module.addImport("gio", gobject.module("gio2"));
    db_test.root_module.addImport("gdk", gobject.module("gdk4"));
    db_test.root_module.addImport("gtk", gobject.module("gtk4"));

    db_test.root_module.addImport("sqlite", sqlite);
    db_test.root_module.addImport("shared-object", shared_object);

    const db_test_artifact = b.addRunArtifact(db_test);
    const run_db_test = b.step("db-test", "Run the SQLite database test");
    run_db_test.dependOn(&db_test_artifact.step);

}
