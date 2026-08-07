/*
 * rs232net.c - RS232 over network emulation.
 *
 * Written by
 *  Tim Newsham
 *  Spiro Trikaliotis <spiro.trikaliotis@gmx.de>
 *  Marco van den Heuvel <blackystardust68@yahoo.com>
 *
 * This file is part of VICE, the Versatile Commodore Emulator.
 * See README for copyright notice.
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
 *  02111-1307  USA.
 *
 */

/*
 * The RS232 emulation captures the bytes sent to the RS232 interfaces
 * available (currently ACIA 6551, std C64 and Daniel Dallmanns fast RS232
 * with 9600 Baud).
 *
 * I/O is done to a socket.  If the socket isnt connected, no data
 * is read and written data is discarded.
 */

#undef DEBUG
/* #define DEBUG */

#include "vice.h"

#ifdef HAVE_RS232NET

#include <ctype.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

#ifdef HAVE_IO_H
#include <io.h>
#endif

#include "lib.h"
#include "log.h"
#include "rs232.h"
#include "rs232net.h"
#include "vicesocket.h"
#include "types.h"
#include "util.h"
#ifdef DEBUG
#include "ctype.h"
#endif

/* #define LOG_MODEM_STATUS */

#ifdef DEBUG
# define DEBUG_LOG_MESSAGE(_xxx) log_message _xxx
#else
# define DEBUG_LOG_MESSAGE(_xxx)
#endif

/* ------------------------------------------------------------------------- */

int rs232net_resources_init(void)
{
    return 0;
}

void rs232net_resources_shutdown(void)
{
}

int rs232net_cmdline_options_init(void)
{
    return 0;
}

/* ------------------------------------------------------------------------- */

typedef struct rs232net {
    int inuse; /*!< 0 if the connection has not been opened, 1 otherwise. */
    vice_network_socket_t * fd; /*!< the vice_network_socket_t for the connection.
                                     If fd is 0
                    although inuse == 1, then the socket has been closed
                    because of a previous error. This prevents the error
                    log from being flooded with error messages. */
    int useip232; /*!< 1 to use the ip232 protocol for tcpser */
    int dcd_in;   /*!< ip232 status of DCD line */
    int ri_in;    /*!< ip232 status of RI line */
    int dtr_out;  /*!< ip232 status of DTR line */

    /* POKE64 virtual Hayes modem state. The logical RS-232 device remains
     * open in command mode while fd is NULL; ATDT creates the TCP socket. */
    int poke64_hayes;
    int hayes_command_mode;
    int hayes_echo;
    int hayes_quiet;
    int hayes_verbose;
    int hayes_telnet;
    unsigned int hayes_plus_count;
    unsigned int telnet_state;
    uint8_t telnet_command;
    char hayes_command[256];
    size_t hayes_command_len;
    uint8_t hayes_response[1024];
    size_t hayes_response_head;
    size_t hayes_response_tail;
} rs232net_t;

/* C99 standard guarantees all members of an object of static storage are
 * initialized to their '0' value, see 6.7.8.10 */
static rs232net_t fds[RS232_NUM_DEVICES];

static log_t rs232net_log = LOG_DEFAULT;

#define POKE64_HAYES_DEVICE "poke64-hayes"
#define POKE64_HAYES_COMMAND_MAX 255
#define POKE64_HAYES_RESPONSE_MAX 1024

#define POKE64_TELNET_IAC 255
#define POKE64_TELNET_DONT 254
#define POKE64_TELNET_DO 253
#define POKE64_TELNET_WONT 252
#define POKE64_TELNET_WILL 251
#define POKE64_TELNET_SB 250
#define POKE64_TELNET_SE 240

#define POKE64_TELNET_OPT_BINARY 0
#define POKE64_TELNET_OPT_ECHO 1
#define POKE64_TELNET_OPT_SGA 3

enum poke64_telnet_state {
    POKE64_TELNET_DATA = 0,
    POKE64_TELNET_IAC_STATE,
    POKE64_TELNET_OPTION,
    POKE64_TELNET_SUBNEG,
    POKE64_TELNET_SUBNEG_IAC
};

/* POKE64 frontend telemetry. These counters describe bytes transferred on
 * the TCP socket, including IP232 control bytes when that mode is enabled. */
static unsigned long long poke64_modem_tx_count = 0;
static unsigned long long poke64_modem_rx_count = 0;

int poke64_modem_connected(void)
{
    int i;

    for (i = 0; i < RS232_NUM_DEVICES; i++) {
        if (fds[i].inuse && fds[i].fd) {
            return 1;
        }
    }
    return 0;
}

unsigned long long poke64_modem_tx_bytes(void)
{
    return poke64_modem_tx_count;
}

unsigned long long poke64_modem_rx_bytes(void)
{
    return poke64_modem_rx_count;
}

/* ------------------------------------------------------------------------- */

void rs232net_close(int fd);
static void rs232net_closesocket(int index);
static int _rs232net_putc(int fd, uint8_t b);

static void poke64_hayes_queue_byte(int fd, uint8_t b)
{
    size_t next = (fds[fd].hayes_response_tail + 1) % POKE64_HAYES_RESPONSE_MAX;

    if (next == fds[fd].hayes_response_head) {
        return;
    }

    fds[fd].hayes_response[fds[fd].hayes_response_tail] = b;
    fds[fd].hayes_response_tail = next;
}

static void poke64_hayes_queue_text(int fd, const char *text)
{
    while (*text) {
        poke64_hayes_queue_byte(fd, (uint8_t)*text++);
    }
}

static int poke64_hayes_dequeue_byte(int fd, uint8_t *b)
{
    if (fds[fd].hayes_response_head == fds[fd].hayes_response_tail) {
        return 0;
    }

    *b = fds[fd].hayes_response[fds[fd].hayes_response_head];
    fds[fd].hayes_response_head =
        (fds[fd].hayes_response_head + 1) % POKE64_HAYES_RESPONSE_MAX;
    return 1;
}

static void poke64_hayes_result(int fd, const char *verbose, const char *numeric)
{
    if (fds[fd].hayes_quiet) {
        return;
    }

    poke64_hayes_queue_text(fd, "\r\n");
    poke64_hayes_queue_text(fd, fds[fd].hayes_verbose ? verbose : numeric);
    poke64_hayes_queue_text(fd, "\r\n");
}

static int poke64_hayes_prefix(const char *value, const char *prefix)
{
    while (*prefix) {
        if (!*value
            || toupper((unsigned char)*value) != toupper((unsigned char)*prefix)) {
            return 0;
        }
        value++;
        prefix++;
    }
    return 1;
}

static void poke64_hayes_reset_profile(int fd)
{
    fds[fd].hayes_echo = 1;
    fds[fd].hayes_quiet = 0;
    fds[fd].hayes_verbose = 1;
    fds[fd].hayes_telnet = 1;
    fds[fd].hayes_plus_count = 0;
    fds[fd].telnet_state = POKE64_TELNET_DATA;
    fds[fd].telnet_command = 0;
    fds[fd].hayes_command_len = 0;
}

static void poke64_hayes_disconnect(int fd, int report)
{
    if (fds[fd].fd) {
        rs232net_closesocket(fd);
    }
    fds[fd].hayes_command_mode = 1;
    fds[fd].hayes_plus_count = 0;
    if (report) {
        poke64_hayes_result(fd, "NO CARRIER", "3");
    }
}

static void poke64_hayes_dial(int fd, const char *target)
{
    vice_network_socket_address_t *ad;
    char dial_target[256];
    size_t length;

    while (*target && isspace((unsigned char)*target)) {
        target++;
    }
    length = strlen(target);
    while (length > 0 && isspace((unsigned char)target[length - 1])) {
        length--;
    }
    if (length == 0 || length >= sizeof(dial_target)) {
        poke64_hayes_result(fd, "ERROR", "4");
        return;
    }
    memcpy(dial_target, target, length);
    dial_target[length] = '\0';

    if (fds[fd].fd) {
        rs232net_closesocket(fd);
    }

    ad = vice_network_address_generate(dial_target, 0);
    if (!ad) {
        poke64_hayes_result(fd, "NO CARRIER", "3");
        return;
    }

    fds[fd].fd = vice_network_client(ad);
    vice_network_address_close(ad);

    if (!fds[fd].fd) {
        poke64_hayes_result(fd, "NO CARRIER", "3");
        return;
    }

    fds[fd].hayes_command_mode = 0;
    fds[fd].hayes_plus_count = 0;
    fds[fd].telnet_state = POKE64_TELNET_DATA;
    fds[fd].telnet_command = 0;
    poke64_hayes_result(fd, "CONNECT", "1");
}

static void poke64_hayes_execute_command(int fd)
{
    char compact[256];
    char *command = fds[fd].hayes_command;
    const char *body;
    size_t i;
    size_t out = 0;

    command[fds[fd].hayes_command_len] = '\0';
    fds[fd].hayes_command_len = 0;

    while (*command && isspace((unsigned char)*command)) {
        command++;
    }
    if (!poke64_hayes_prefix(command, "AT")) {
        poke64_hayes_result(fd, "ERROR", "4");
        return;
    }

    body = command + 2;
    while (*body && isspace((unsigned char)*body)) {
        body++;
    }

    if (poke64_hayes_prefix(body, "DT") || poke64_hayes_prefix(body, "DP")) {
        poke64_hayes_dial(fd, body + 2);
        return;
    }

    for (i = 0; body[i] && out < sizeof(compact) - 1; i++) {
        if (!isspace((unsigned char)body[i])) {
            compact[out++] = (char)toupper((unsigned char)body[i]);
        }
    }
    compact[out] = '\0';

    if (compact[0] == '\0') {
        poke64_hayes_result(fd, "OK", "0");
        return;
    }

    if (!strcmp(compact, "Z") || !strcmp(compact, "&F")) {
        if (fds[fd].fd) {
            rs232net_closesocket(fd);
        }
        fds[fd].hayes_command_mode = 1;
        poke64_hayes_reset_profile(fd);
        poke64_hayes_result(fd, "OK", "0");
        return;
    }
    if (!strcmp(compact, "E0") || !strcmp(compact, "E1")) {
        fds[fd].hayes_echo = compact[1] == '1';
        poke64_hayes_result(fd, "OK", "0");
        return;
    }
    if (!strcmp(compact, "V0") || !strcmp(compact, "V1")) {
        fds[fd].hayes_verbose = compact[1] == '1';
        poke64_hayes_result(fd, "OK", "0");
        return;
    }
    if (!strcmp(compact, "Q0") || !strcmp(compact, "Q1")) {
        fds[fd].hayes_quiet = compact[1] == '1';
        poke64_hayes_result(fd, "OK", "0");
        return;
    }
    if (!strcmp(compact, "H") || !strcmp(compact, "H0")) {
        poke64_hayes_disconnect(fd, 0);
        poke64_hayes_result(fd, "OK", "0");
        return;
    }
    if (!strcmp(compact, "O")) {
        if (fds[fd].fd) {
            fds[fd].hayes_command_mode = 0;
            fds[fd].hayes_plus_count = 0;
            poke64_hayes_result(fd, "CONNECT", "1");
        } else {
            poke64_hayes_result(fd, "NO CARRIER", "3");
        }
        return;
    }
    if (!strcmp(compact, "I") || !strcmp(compact, "I0")) {
        poke64_hayes_queue_text(fd, "\r\nPOKE64 VIRTUAL MODEM\r\n");
        poke64_hayes_result(fd, "OK", "0");
        return;
    }
    if (!strcmp(compact, "NET0") || !strcmp(compact, "NET1")) {
        fds[fd].hayes_telnet = compact[3] == '1';
        fds[fd].telnet_state = POKE64_TELNET_DATA;
        fds[fd].telnet_command = 0;
        poke64_hayes_result(fd, "OK", "0");
        return;
    }

    /* Common initialization commands used by C64 terminal software. They do
     * not change POKE64 transport behavior, but accepting them makes the
     * virtual modem compatible with conventional Hayes init strings. */
    if ((compact[0] == 'X' && compact[1] >= '0' && compact[1] <= '4' && compact[2] == '\0')
        || !strcmp(compact, "&C0") || !strcmp(compact, "&C1")
        || !strcmp(compact, "&D0") || !strcmp(compact, "&D1")
        || !strcmp(compact, "&D2") || !strcmp(compact, "&D3")
        || !strcmp(compact, "&K0") || !strcmp(compact, "&K1")
        || !strcmp(compact, "&K2") || !strcmp(compact, "&K3")
        || !strcmp(compact, "S0=0")) {
        poke64_hayes_result(fd, "OK", "0");
        return;
    }

    poke64_hayes_result(fd, "ERROR", "4");
}

static int poke64_hayes_command_putc(int fd, uint8_t b)
{
    if (fds[fd].hayes_echo) {
        poke64_hayes_queue_byte(fd, b);
    }

    if (b == '\r') {
        poke64_hayes_execute_command(fd);
        return 0;
    }
    if (b == '\n') {
        return 0;
    }
    if (b == 8 || b == 127) {
        if (fds[fd].hayes_command_len > 0) {
            fds[fd].hayes_command_len--;
        }
        return 0;
    }
    if (fds[fd].hayes_command_len >= POKE64_HAYES_COMMAND_MAX) {
        fds[fd].hayes_command_len = 0;
        poke64_hayes_result(fd, "ERROR", "4");
        return 0;
    }

    fds[fd].hayes_command[fds[fd].hayes_command_len++] = (char)b;
    return 0;
}

/* initializes all RS232 stuff */
void rs232net_init(void)
{
    rs232net_log = log_open("RS232NET");
}

/* reset RS232 stuff */
void rs232net_reset(void)
{
    int i;

    for (i = 0; i < RS232_NUM_DEVICES; i++) {
        if (fds[i].inuse) {
            rs232net_close(i);
        }
    }
}

/* opens a rs232 window, returns handle to give to functions below. */
int rs232net_open(int device)
{
    vice_network_socket_address_t *ad = NULL;
    int index = -1;
    int i;

    for (i = 0; i < RS232_NUM_DEVICES; i++) {
        if (!fds[i].inuse) {
            break;
        }
    }
    if (i >= RS232_NUM_DEVICES) {
        log_error(rs232net_log, "No more devices available.");
        return -1;
    }

    DEBUG_LOG_MESSAGE((rs232net_log, "rs232net_open(device=%d).", device));

    memset(&fds[i], 0, sizeof(fds[i]));
    fds[i].inuse = 1;
    fds[i].useip232 = rs232_useip232[device];

    if (rs232_devfile[device] && !strcmp(rs232_devfile[device], POKE64_HAYES_DEVICE)) {
        fds[i].poke64_hayes = 1;
        fds[i].hayes_command_mode = 1;
        poke64_hayes_reset_profile(i);
        return i;
    }

    ad = vice_network_address_generate(rs232_devfile[device], 0);
    if (!ad) {
        log_error(rs232net_log, "Bad device name.  Should be ipaddr:port, but is '%s'.", rs232_devfile[device]);
        fds[i].inuse = 0;
        return -1;
    }

    fds[i].fd = vice_network_client(ad);
    vice_network_address_close(ad);
    if (!fds[i].fd) {
        log_error(rs232net_log, "Cant open connection.");
        fds[i].inuse = 0;
        return -1;
    }

    index = i;
    return index;
}

static void rs232net_closesocket(int index)
{
    if (fds[index].fd) {
        vice_network_socket_close(fds[index].fd);
        fds[index].fd = 0;
    }
}

/* closes the rs232 window again */
void rs232net_close(int fd)
{
    do {

        DEBUG_LOG_MESSAGE((rs232net_log, "close(fd=%d).", fd));

        if (fd < 0 || fd >= RS232_NUM_DEVICES) {
            log_error(rs232net_log, "Attempt to close invalid fd %d.", fd);
            break;
        }
        if (!fds[fd].inuse) {
            log_error(rs232net_log, "Attempt to close non-open fd %d.", fd);
            break;
        }

        if (fds[fd].useip232) {
            _rs232net_putc(fd, IP232MAGIC);
            _rs232net_putc(fd, IP232DTRLO);
        }

        rs232net_closesocket(fd);
        memset(&fds[fd], 0, sizeof(fds[fd]));

    } while (0);
}

/* sends a byte to the RS232 line */
static int _rs232net_putc(int fd, uint8_t b)
{
    ssize_t n;

    if (fd < 0 || fd >= RS232_NUM_DEVICES) {
        log_error(rs232net_log, "Attempt to write to invalid fd %d.", fd);
        return -1;
    }
    if (!fds[fd].inuse) {
        log_error(rs232net_log, "Attempt to write to non-open fd %d.", fd);
        return -1;
    }

    /* silently drop if socket is shut because of a previous error */
    if (!fds[fd].fd) {
        return 0;
    }

    /* for the beginning... */
    DEBUG_LOG_MESSAGE((rs232net_log, "Output 0x%02x '%c'.", b, isgraph((unsigned char)b) ? b : '.'));

    n = vice_network_send(fds[fd].fd, &b, 1, 0);
    if (n < 0) {
        log_error(rs232net_log, "Error writing: %d.", vice_network_get_errorcode());
        rs232net_closesocket(fd);
        return -1;
    }
    return 0;
}

/* gets a byte to the RS232 line, returns !=0 if byte received, byte in *b. */
static int _rs232net_getc(int fd, uint8_t * b)
{
    int ret;
    ssize_t no_of_read_byte = -1;

    do {
        if (fd < 0 || fd >= RS232_NUM_DEVICES) {
            log_error(rs232net_log, "Attempt to read from invalid fd %d.", fd);
            break;
        }

        if (!fds[fd].inuse) {
            log_error(rs232net_log, "Attempt to read from non-open fd %d.", fd);
            break;
        }

        /* from now on, assume everything is ok,
           but we have not received any bytes */
        no_of_read_byte = 0;

        /* silently drop if socket is shut because of a previous error  */
        if (!fds[fd].fd) {
            break;
        }

        ret = vice_network_select_poll_one(fds[fd].fd);

        if (ret > 0) {

            no_of_read_byte = vice_network_receive(fds[fd].fd, b, 1, 0);
            DEBUG_LOG_MESSAGE((rs232net_log, "Input 0x%02x '%c'.", *b, isgraph((unsigned char)*b) ? *b : '.'));

            if ( no_of_read_byte != 1 ) {
                if ( no_of_read_byte < 0 ) {
                    log_error(rs232net_log, "Error reading: %d.",
                            vice_network_get_errorcode());
                } else {
                    log_error(rs232net_log, "EOF");
                }
                rs232net_closesocket(fd);
                no_of_read_byte = -1;
            }
        }
    } while (0);

    return (int)no_of_read_byte;
}

static int poke64_telnet_send_command(int fd, uint8_t command, uint8_t option)
{
    if (_rs232net_putc(fd, POKE64_TELNET_IAC) < 0
        || _rs232net_putc(fd, command) < 0
        || _rs232net_putc(fd, option) < 0) {
        return -1;
    }
    return 0;
}

static int poke64_telnet_handle_option(int fd, uint8_t command, uint8_t option)
{
    uint8_t reply;

    /* Keep the transport 8-bit clean and accept the two conventional terminal
     * options useful to a C64 BBS. Refuse everything else so TELNET control
     * traffic never leaks into the PETSCII data stream. */
    if (option == POKE64_TELNET_OPT_BINARY) {
        reply = (command == POKE64_TELNET_WILL || command == POKE64_TELNET_WONT)
            ? (command == POKE64_TELNET_WILL ? POKE64_TELNET_DO : POKE64_TELNET_DONT)
            : (command == POKE64_TELNET_DO ? POKE64_TELNET_WILL : POKE64_TELNET_WONT);
    } else if (option == POKE64_TELNET_OPT_ECHO || option == POKE64_TELNET_OPT_SGA) {
        if (command == POKE64_TELNET_WILL) {
            reply = POKE64_TELNET_DO;
        } else if (command == POKE64_TELNET_DO && option == POKE64_TELNET_OPT_SGA) {
            reply = POKE64_TELNET_WILL;
        } else if (command == POKE64_TELNET_WONT) {
            reply = POKE64_TELNET_DONT;
        } else {
            reply = POKE64_TELNET_WONT;
        }
    } else {
        reply = (command == POKE64_TELNET_WILL || command == POKE64_TELNET_WONT)
            ? POKE64_TELNET_DONT : POKE64_TELNET_WONT;
    }

    return poke64_telnet_send_command(fd, reply, option);
}

static int poke64_telnet_getc(int fd, uint8_t *b)
{
    int ret;
    uint8_t c;

    for (;;) {
        ret = _rs232net_getc(fd, &c);
        if (ret <= 0) {
            return ret;
        }

        switch (fds[fd].telnet_state) {
            case POKE64_TELNET_DATA:
                if (c == POKE64_TELNET_IAC) {
                    fds[fd].telnet_state = POKE64_TELNET_IAC_STATE;
                    continue;
                }
                *b = c;
                return 1;

            case POKE64_TELNET_IAC_STATE:
                if (c == POKE64_TELNET_IAC) {
                    fds[fd].telnet_state = POKE64_TELNET_DATA;
                    *b = POKE64_TELNET_IAC;
                    return 1;
                }
                if (c == POKE64_TELNET_DO || c == POKE64_TELNET_DONT
                    || c == POKE64_TELNET_WILL || c == POKE64_TELNET_WONT) {
                    fds[fd].telnet_command = c;
                    fds[fd].telnet_state = POKE64_TELNET_OPTION;
                    continue;
                }
                if (c == POKE64_TELNET_SB) {
                    fds[fd].telnet_state = POKE64_TELNET_SUBNEG;
                    continue;
                }
                fds[fd].telnet_state = POKE64_TELNET_DATA;
                continue;

            case POKE64_TELNET_OPTION:
                ret = poke64_telnet_handle_option(fd, fds[fd].telnet_command, c);
                fds[fd].telnet_state = POKE64_TELNET_DATA;
                fds[fd].telnet_command = 0;
                if (ret < 0) {
                    return ret;
                }
                continue;

            case POKE64_TELNET_SUBNEG:
                if (c == POKE64_TELNET_IAC) {
                    fds[fd].telnet_state = POKE64_TELNET_SUBNEG_IAC;
                }
                continue;

            case POKE64_TELNET_SUBNEG_IAC:
                fds[fd].telnet_state = (c == POKE64_TELNET_SE)
                    ? POKE64_TELNET_DATA : POKE64_TELNET_SUBNEG;
                continue;

            default:
                fds[fd].telnet_state = POKE64_TELNET_DATA;
                continue;
        }
    }
}

/* sends a byte to the RS232 line */
int rs232net_putc(int fd, uint8_t b)
{
    int ret;

    if (fd < 0 || fd >= RS232_NUM_DEVICES || !fds[fd].inuse) {
        return -1;
    }

    /* Frontend TX telemetry is serial-side activity: count every byte the C64
     * hands to the virtual modem, including Hayes command-mode traffic. */
    poke64_modem_tx_count += 1;

    if (fds[fd].poke64_hayes) {
        if (fds[fd].hayes_command_mode) {
            return poke64_hayes_command_putc(fd, b);
        }

        /* A compact first-pass Hayes escape sequence. Guard-time semantics can
         * be added later; for now three consecutive plus characters switch to
         * command mode without tearing down the carrier. */
        if (b == '+') {
            fds[fd].hayes_plus_count++;
            if (fds[fd].hayes_plus_count == 3) {
                fds[fd].hayes_plus_count = 0;
                fds[fd].hayes_command_mode = 1;
                poke64_hayes_result(fd, "OK", "0");
            }
            return 0;
        }
        while (fds[fd].hayes_plus_count > 0) {
            ret = _rs232net_putc(fd, '+');
            fds[fd].hayes_plus_count--;
            if (ret < 0) {
                poke64_hayes_disconnect(fd, 1);
                return ret;
            }
        }

        if (fds[fd].hayes_telnet && b == POKE64_TELNET_IAC) {
            ret = _rs232net_putc(fd, POKE64_TELNET_IAC);
            if (ret >= 0) {
                ret = _rs232net_putc(fd, POKE64_TELNET_IAC);
            }
        } else {
            ret = _rs232net_putc(fd, b);
        }
        if (ret < 0) {
            poke64_hayes_disconnect(fd, 1);
        }
        return ret;
    }

    if (fds[fd].useip232) {
        if (b == IP232MAGIC) {
            if (_rs232net_putc(fd, IP232MAGIC) == -1) {
                return -1;
            }
        }
    }

    return _rs232net_putc(fd, b);
}

/* gets a byte to the RS232 line, returns !=0 if byte received, byte in *b. */
int rs232net_getc(int fd, uint8_t * b)
{
    int ret = -1;

    if (fd < 0 || fd >= RS232_NUM_DEVICES) {
        log_error(rs232net_log, "Attempt to read from invalid fd %d.", fd);
        return -1;
    }

    if (fds[fd].poke64_hayes) {
        if (poke64_hayes_dequeue_byte(fd, b)) {
            /* Frontend RX telemetry is serial-side activity: this includes
             * Hayes echo/result bytes as well as online TCP payload. */
            poke64_modem_rx_count += 1;
            return 1;
        }
        if (fds[fd].hayes_command_mode) {
            return 0;
        }
    }

tryagain:

    ret = (fds[fd].poke64_hayes && fds[fd].hayes_telnet)
        ? poke64_telnet_getc(fd, b)
        : _rs232net_getc(fd, b);

    if (fds[fd].poke64_hayes) {
        if (ret < 0) {
            poke64_hayes_disconnect(fd, 1);
            return 0;
        }
        if (ret > 0) {
            poke64_modem_rx_count += (unsigned long long)ret;
        }
        return ret;
    }

    if (fds[fd].useip232) {
        if (*b == IP232MAGIC) {
            if ((ret = _rs232net_getc(fd, b)) < 1) {
                return ret;
            }
            if (*b == IP232MAGIC) {
                /* literal 0xff */
            } else {
                fds[fd].dcd_in = (*b & IP232DCDMASK) == IP232DCDHI ? 1 : 0;
                fds[fd].ri_in = (*b & IP232RIMASK) == IP232RIHI ? 1 : 0;
                goto tryagain;
            }
        }
    }

    if (ret > 0) {
        poke64_modem_rx_count += (unsigned long long)ret;
    }
    return ret;
}

/* set the status lines of the RS232 device */
int rs232net_set_status(int fd, enum rs232handshake_out status)
{
    int dtr = (status & RS232_HSO_DTR) ? 1 : 0; /* is this correct? */
#ifdef LOG_MODEM_STATUS
    if (dtr != fds[fd].dtr_out) {
        DEBUG_LOG_MESSAGE((rs232net_log, "rs232net_set_status(fd:%d) status:%02x dtr:%d rts:%d",
            fd, status, dtr, status & RS232_HSO_RTS ? 1 : 0
        ));
    }
#endif
    if (fds[fd].useip232) {
        if (dtr != fds[fd].dtr_out) {
            /* original patch never sends a 0 */
            if (dtr) {
                _rs232net_putc(fd, IP232MAGIC);
                _rs232net_putc(fd, IP232DTRHI);
            }
            if (!dtr) {
                _rs232net_putc(fd, IP232MAGIC);
                _rs232net_putc(fd, IP232DTRLO);
            }
        }
    }
    fds[fd].dtr_out = dtr;
    return 0;
}

/* get the status lines of the RS232 device */
enum rs232handshake_in rs232net_get_status(int fd)
{
    enum rs232handshake_in status = 0;
#ifdef LOG_MODEM_STATUS
    static enum rs232handshake_in oldstatus = 0;
#endif

    if (fds[fd].poke64_hayes) {
        /* CCGMS and several C64 terminal programs gate command-mode TX on
         * carrier detect.  A physical Hayes modem normally drops DCD until
         * carrier is present, but that creates a chicken-and-egg condition
         * for these user-port drivers: ATDT never reaches the virtual modem.
         * Keep DCD asserted while the virtual modem is in command mode; once
         * online the live TCP socket keeps it asserted.  CONNECT/NO CARRIER
         * result codes remain the authoritative carrier indication. */
        if (fds[fd].hayes_command_mode || fds[fd].fd) {
            status |= RS232_HSI_DCD;
        }
    } else if (fds[fd].useip232) {
#if 0   /* this doesnt work right, eg local echo wont work anymore */
        /* if DTR is low, read from the socket to update it's status */
        uint8_t dummy;
        if (fds[fd].dcd_in == 0) {
            if (rs232net_getc(fd, &dummy) > 0) {
                if (fds[fd].dcd_in == 0) {
                    log_error(rs232net_log, "Incoming byte with DTR inactive: 0x%02x '%c'.", dummy, dummy);
                }
            }
        }
#endif
        if (fds[fd].dcd_in && fds[fd].dtr_out) {
            status |= RS232_HSI_DCD;
        }
        if (fds[fd].ri_in) {
            status |= RS232_HSI_RI;
        }
    } else {
        status |= RS232_HSI_DCD;
    }
    /* CTS and DSR are always set */
    /* ideally these two lines (along with RI) should also be handled by ip232 in the future */
    status |= RS232_HSI_CTS | RS232_HSI_DSR;

#ifdef LOG_MODEM_STATUS
    if (status != oldstatus) {
        printf("rs232net_get_status(fd:%d): DCD:%d modem_status:%02x cts:%d dsr:%d dcd:%d ri:%d\n",
               fd, fds[fd].dcd_in, status,
               status & RS232_HSI_CTS ? 1 : 0,
               status & RS232_HSI_DSR ? 1 : 0,
               status & RS232_HSI_DCD ? 1 : 0,
               status & RS232_HSI_RI ? 1 : 0
              );
        oldstatus = status;
    }
#endif
    return status;
/*    return RS232_HSI_CTS | RS232_HSI_DSR; */
}
#endif
