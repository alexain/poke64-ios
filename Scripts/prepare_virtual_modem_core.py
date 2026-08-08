#!/usr/bin/env python3
"""Enable VICE RS-232-over-TCP support in POKE64's iOS libretro core."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1))



def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    args = parser.parse_args()

    source = args.source.resolve()
    if not (source / ".git").is_dir():
        raise SystemExit(f"Not a vice-libretro checkout: {source}")

    # vice-libretro disables HAVE_NETWORK globally near the end of config.h.
    # Keep the general VICE networking/netplay feature disabled and enable only
    # the RS-232-over-TCP backend on Apple targets. This avoids pulling the
    # binary monitor/netplay objects into the iOS libretro link.
    config = source / "include/config.h"
    replace_once(
        config,
        "#undef HAVE_NETWORK\n"
        "\n"
        "#define HAVE_U_SHORT 1\n",
        "#undef HAVE_NETWORK\n"
        "\n"
        "#if defined(__APPLE__) && defined(__MACH__)\n"
        "#define HAVE_RS232NET 1\n"
        "#define HAVE_HTONS 1\n"
        "#define HAVE_HTONL 1\n"
        "#define HAVE_NETDB_H 1\n"
        "#define HAVE_NETINET_IN_H 1\n"
        "#define HAVE_NETINET_TCP_H 1\n"
        "#define HAVE_ARPA_INET_H 1\n"
        "#define HAVE_SYS_SOCKET_H 1\n"
        "#define HAVE_SYS_SELECT_H 1\n"
        "#define HAVE_SOCKET 1\n"
        "#define HAVE_SOCKLEN_T 1\n"
        "#define HAVE_IN_ADDR_T 1\n"
        "#endif\n"
        "\n"
        "#define HAVE_U_SHORT 1\n",
        "Apple VICE RS232NET feature flags",
    )

    # socket.c normally compiles only with HAVE_NETWORK. RS232NET needs the same
    # vicesocket implementation, so compile it for either the full networking
    # feature or the modem-only backend without globally defining HAVE_NETWORK.
    socket_source = source / "vice/src/socket.c"
    replace_once(
        socket_source,
        "#ifdef HAVE_NETWORK\n",
        "#if defined(HAVE_NETWORK) || defined(HAVE_RS232NET)\n",
        "VICE socket implementation for RS232NET",
    )


    # POKE64/iOS: the pinned VICE IPv4 resolver uses legacy gethostbyname().
    # Keep the existing VICE IPv4 address structure and parsing, but resolve
    # hostnames through getaddrinfo(AF_INET). This is deliberately minimal:
    # it fixes DNS on Apple networks without changing VICE's socket ABI or
    # enabling the rest of HAVE_NETWORK.
    replace_once(
        socket_source,
        "#include <string.h>\n",
        "#include <string.h>\n"
        "\n"
        "#if defined(HAVE_RS232NET) && defined(__APPLE__) && defined(__MACH__)\n"
        "#include <netdb.h>\n"
        "#endif\n",
        "POKE64 Apple getaddrinfo declarations",
    )
    replace_once(
        socket_source,
        "            host_entry = gethostbyname(address_part);\n",
        """#if defined(HAVE_RS232NET) && defined(__APPLE__) && defined(__MACH__)
            {
                struct addrinfo hints;
                struct addrinfo *results = NULL;
                struct sockaddr_in *resolved_ipv4;

                memset(&hints, 0, sizeof hints);
                hints.ai_family = AF_INET;
                hints.ai_socktype = SOCK_STREAM;
                hints.ai_protocol = IPPROTO_TCP;

                if (getaddrinfo(address_part, NULL, &hints, &results) == 0
                        && results != NULL
                        && results->ai_addr != NULL
                        && results->ai_addrlen >= sizeof(struct sockaddr_in)) {
                    resolved_ipv4 = (struct sockaddr_in *)results->ai_addr;
                    socket_address->address.ipv4.sin_addr = resolved_ipv4->sin_addr;
                    freeaddrinfo(results);
                    error = 0;
                    break;
                }

                if (results != NULL) {
                    freeaddrinfo(results);
                }
            }
#endif
            host_entry = gethostbyname(address_part);
""",
        "POKE64 Apple IPv4 DNS resolver",
    )

    # libretro snapshot_stream.c provides fallback ACIA stubs because the
    # cartridge ACIA implementation is normally compiled without RS-232 support.
    # Once RS232NET is enabled, c64acia1.c provides the real implementations;
    # keep the fallbacks only for builds where no RS-232 backend is available.
    snapshot_stream = source / "retrodep/snapshot_stream.c"
    replace_once(
        snapshot_stream,
        "#ifndef acia1_snapshot_read_module\n"
        "int acia1_snapshot_read_module(struct snapshot_s *p) { return 0; };\n"
        "#endif\n"
        "\n"
        "#ifndef _acia_snapshot_read_module\n"
        "int _acia_snapshot_read_module(struct snapshot_s *p) { return 0; };\n"
        "#endif\n"
        "\n"
        "#ifndef acia1_store\n"
        "void acia1_store(uint16_t a, uint8_t b) {};\n"
        "#endif\n"
        "\n"
        "#ifndef acia_store\n"
        "void acia_store(uint16_t a, uint8_t b) {};\n"
        "#endif\n",
        "#if !defined(HAVE_RS232DEV) && !defined(HAVE_RS232NET)\n"
        "#ifndef acia1_snapshot_read_module\n"
        "int acia1_snapshot_read_module(struct snapshot_s *p) { return 0; };\n"
        "#endif\n"
        "#endif\n"
        "\n"
        "#ifndef _acia_snapshot_read_module\n"
        "int _acia_snapshot_read_module(struct snapshot_s *p) { return 0; };\n"
        "#endif\n"
        "\n"
        "#if !defined(HAVE_RS232DEV) && !defined(HAVE_RS232NET)\n"
        "#ifndef acia1_store\n"
        "void acia1_store(uint16_t a, uint8_t b) {};\n"
        "#endif\n"
        "#endif\n"
        "\n"
        "#ifndef acia_store\n"
        "void acia_store(uint16_t a, uint8_t b) {};\n"
        "#endif\n",
        "libretro ACIA fallback stubs for RS232NET",
    )

    # socket.c is already part of Makefile.common, but the libretro include path
    # does not expose arch/shared/socketdrv/socketimpl.h. Add a tiny libretro
    # adapter that reuses VICE's own Unix implementation instead of duplicating
    # the BSD socket definitions. The file is untracked in the fetched checkout,
    # so accept an identical copy on subsequent core rebuilds.
    socketimpl = source / "retrodep/socketimpl.h"
    socketimpl_text = """/* POKE64 iOS libretro socket adapter. Part of the patched VICE core. */
#ifndef POKE64_LIBRETRO_SOCKETIMPL_H
#define POKE64_LIBRETRO_SOCKETIMPL_H

/* VICE's Unix socket implementation is historically guarded by HAVE_NETWORK.
 * For POKE64's modem-only build expose it while parsing this header, then
 * immediately restore the real feature state so netplay/binary monitor stay off. */
#if defined(HAVE_RS232NET) && !defined(HAVE_NETWORK)
#define POKE64_SOCKETIMPL_RS232NET_ONLY 1
#define HAVE_NETWORK 1
#endif

#include "arch/shared/socketdrv/socket-unix-impl.h"

#ifdef POKE64_SOCKETIMPL_RS232NET_ONLY
#undef HAVE_NETWORK
#undef POKE64_SOCKETIMPL_RS232NET_ONLY
#endif

#endif /* POKE64_LIBRETRO_SOCKETIMPL_H */
"""
    if socketimpl.exists():
        existing_socketimpl = socketimpl.read_text()
        if existing_socketimpl != socketimpl_text:
            # Older POKE64 modem preparation passes may have left a previous
            # generated adapter behind. git reset --hard does not remove
            # untracked files, so safely replace only adapters carrying our
            # own signature; still fail closed for any unrelated local file.
            poke64_signature = "/* POKE64 iOS libretro socket adapter. Part of the patched VICE core. */\n"
            if not existing_socketimpl.startswith(poke64_signature):
                raise SystemExit(f"Unexpected existing libretro socket adapter: {socketimpl}")
            socketimpl.write_text(socketimpl_text)
    else:
        socketimpl.write_text(socketimpl_text)

    # Replace the pinned VICE rs232net backend with POKE64's small Hayes layer.
    # The replacement keeps VICE's socket implementation and adds AT command
    # parsing plus the existing frontend telemetry. Fail closed if the pinned
    # upstream source changes so we never overwrite an unexpected revision.
    rs232net = source / "vice/src/rs232drv/rs232net.c"
    expected_rs232net_sha256 = "d4415daae8b029edc48bb83370e21f12ccfa1fc8aff514722f5ef8b0d192f907"
    actual_rs232net_sha256 = hashlib.sha256(rs232net.read_bytes()).hexdigest()
    if actual_rs232net_sha256 != expected_rs232net_sha256:
        raise SystemExit(
            "Unexpected VICE rs232net.c revision: "
            f"expected {expected_rs232net_sha256}, found {actual_rs232net_sha256}"
        )

    hayes_source = Path(__file__).resolve().parent / "vice-patches/rs232net-poke64-hayes.c"
    if not hayes_source.is_file():
        raise SystemExit(f"Missing POKE64 Hayes source: {hayes_source}")
    rs232net.write_bytes(hayes_source.read_bytes())

    # VICE decides whether an RsDevice is a physical serial port or rs232net
    # by asking the socket layer to parse the resource string as an address.
    # POKE64's private command-mode marker is intentionally not a host:port,
    # so route it explicitly to rs232net; otherwise rs232_open() classifies it
    # as RS232DEV and returns -1 on iOS, preventing C64 TX from reaching Hayes.
    rs232_dispatch = source / "vice/src/rs232drv/rs232.c"
    replace_once(
        rs232_dispatch,
        '    vice_network_socket_address_t *ad = NULL;\n'
        '\n'
        '    ad = vice_network_address_generate(rs232_devfile[device], 0);\n',
        '    vice_network_socket_address_t *ad = NULL;\n'
        '\n'
        '    if (rs232_devfile[device] && !strcmp(rs232_devfile[device], "poke64-hayes")) {\n'
        '        DBG(("rs232_is_physical_device: no (POKE64 Hayes rs232net)"));\n'
        '        return 0;\n'
        '    }\n'
        '\n'
        '    ad = vice_network_address_generate(rs232_devfile[device], 0);\n',
        "POKE64 Hayes rs232net dispatch",
    )

    # The printer preparation pass has already switched Apple ld from `-s` to
    # `-Wl,-x`. Root the modem-only entry points as well because POKE64 reaches
    # them through dlsym(), so the static linker sees no normal references.
    root_makefile = source / "Makefile"
    replace_once(
        root_makefile,
        "   LDFLAGS     += -Wl,-u,_poke64_printer_configure_raw_capture\n",
        "   LDFLAGS     += -Wl,-u,_poke64_printer_configure_raw_capture\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_connected\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_tx_bytes\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_rx_bytes\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_ready\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_command_mode\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_telnet_enabled\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_endpoint\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_last_result\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_dial\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_hangup\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_trace_snapshot\n"
        "   LDFLAGS     += -Wl,-u,_poke64_modem_trace_clear\n",
        "Darwin modem runtime symbol preservation",
    )

    print("Enabled POKE64 VICE RS-232/TCP networking, Hayes modem, and telemetry.")


if __name__ == "__main__":
    main()
