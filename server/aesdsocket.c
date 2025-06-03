#define _POSIX_C_SOURCE 200112L
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syslog.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>


#define PORT        "9000"
#define BACKLOG     10
#define BUF_SIZE    1024
#define DATAFILE    "/var/tmp/aesdsocketdata"

/* ---------- globals for signal handling ---------- */
static volatile sig_atomic_t exit_requested = 0;
static int listenfd_global = -1;          /* let handler close it */

static void signal_handler(int sig)
{
    (void)sig;
    exit_requested = 1;
    if (listenfd_global != -1) {
        close(listenfd_global);           /* unblock accept() */
        listenfd_global = -1;
    }
    syslog(LOG_INFO, "Caught signal, exiting");
}

/* ---------- helper: create+listen socket ---------- */
static int make_listen_socket(void)
{
    struct addrinfo hints = {0}, *res = NULL, *rp;
    int sfd = -1, yes = 1, rv;

    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags    = AI_PASSIVE;

    if ((rv = getaddrinfo(NULL, PORT, &hints, &res)) != 0) {
        syslog(LOG_ERR, "getaddrinfo: %s", gai_strerror(rv));
        return -1;
    }

    for (rp = res; rp; rp = rp->ai_next) {
        sfd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (sfd == -1)
            continue;

        if (setsockopt(sfd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes) == -1) {
            close(sfd);
            sfd = -1;
            continue;
        }
        if (bind(sfd, rp->ai_addr, rp->ai_addrlen) == 0)
            break;

        close(sfd);
        sfd = -1;
    }
    freeaddrinfo(res);

    if ((sfd != -1) && (listen(sfd, BACKLOG) == -1)) {
        syslog(LOG_ERR, "listen: %s", strerror(errno));
        close(sfd);
        sfd = -1;
    }
    return sfd;
}

static void sockaddr_to_ip(const struct sockaddr *sa, char *ip, size_t len)
{
    void *addr = sa->sa_family == AF_INET
                     ? (void *)&((struct sockaddr_in *)sa)->sin_addr
                     : (void *)&((struct sockaddr_in6 *)sa)->sin6_addr;
    inet_ntop(sa->sa_family, addr, ip, len);
}

static void handle_client(int cfd, const struct sockaddr_storage *caddr)
{
    char ip[INET6_ADDRSTRLEN] = {};
    sockaddr_to_ip((const struct sockaddr *)caddr, ip, sizeof ip);
    syslog(LOG_INFO, "Accepted connection from %s", ip);

    int datafd = open(DATAFILE, O_RDWR | O_CREAT | O_APPEND, 0644);
    if (datafd == -1) {
        syslog(LOG_ERR, "open %s: %s", DATAFILE, strerror(errno));
        close(cfd);
        return;
    }

    char recvbuf[BUF_SIZE];
    char *packet = NULL;
    size_t psize = 0;

    ssize_t n;
    while (!exit_requested &&
           (n = recv(cfd, recvbuf, sizeof recvbuf, 0)) > 0) {
        char *tmp = realloc(packet, psize + n);
        if (!tmp) {
            syslog(LOG_ERR, "realloc failed");
            break;
        }
        packet = tmp;
        memcpy(packet + psize, recvbuf, n);
        psize += n;

        size_t start = 0;
        while (true) {
            void *nl = memchr(packet + start, '\n', psize - start);
            if (!nl)
                break;
            size_t pkt_len = (char *)nl - (packet + start) + 1;

            if (write(datafd, packet + start, pkt_len) != (ssize_t)pkt_len)
                syslog(LOG_ERR, "write datafile: %s", strerror(errno));

            if (lseek(datafd, 0, SEEK_SET) == (off_t)-1)
                syslog(LOG_ERR, "lseek: %s", strerror(errno));
            else {
                char sendbuf[BUF_SIZE];
                ssize_t r;
                while ((r = read(datafd, sendbuf, sizeof sendbuf)) > 0) {
                    if (send(cfd, sendbuf, r, 0) != r) {
                        syslog(LOG_ERR, "send: %s", strerror(errno));
                        break;
                    }
                }
            }
            start += pkt_len;
        }
        if (start) {
            size_t remain = psize - start;
            memmove(packet, packet + start, remain);
            psize = remain;
            packet = realloc(packet, psize);
        }
    }
    free(packet);
    close(datafd);
    close(cfd);
    syslog(LOG_INFO, "Closed connection from %s", ip);
}

int main(int argc, char *argv[])
{
    bool daemon_mode = (argc == 2) && (strcmp(argv[1], "-d") == 0);

    openlog("aesdsocket", LOG_PID, LOG_USER);

    /* turn into daemon early so that later failures still log to syslog */
    if (daemon_mode) {
        pid_t pid = fork();
        if (pid < 0) {
            syslog(LOG_ERR, "fork failed: %s", strerror(errno));
            closelog();
            return EXIT_FAILURE;
        }
        if (pid > 0) {
            /* parent exits */
            return EXIT_SUCCESS;
        }
        /* child continues */
        if (setsid() == -1) {
            syslog(LOG_ERR, "setsid failed: %s", strerror(errno));
            return EXIT_FAILURE;
        }
        chdir("/");
        close(STDIN_FILENO);
        close(STDOUT_FILENO);
        close(STDERR_FILENO);
        open("/dev/null", O_RDWR); /* stdin */
        dup(0);                    /* stdout */
        dup(0);                    /* stderr */
    }

    /* install SIGINT/SIGTERM handlers */
    struct sigaction sa = {.sa_handler = signal_handler};
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    int listenfd = make_listen_socket();
    if (listenfd == -1) {
        closelog();
        return EXIT_FAILURE;
    }
    listenfd_global = listenfd;

    syslog(LOG_INFO, "Server listening on port %s%s", PORT,
           daemon_mode ? " (daemon)" : "");

    while (!exit_requested) {
        struct sockaddr_storage caddr;
        socklen_t clen = sizeof caddr;
        int cfd = accept(listenfd, (struct sockaddr *)&caddr, &clen);
        if (cfd == -1) {
            if (exit_requested)
                break;
            syslog(LOG_ERR, "accept: %s", strerror(errno));
            continue;
        }
        handle_client(cfd, &caddr);
    }

    if (listenfd != -1)
        close(listenfd);
    unlink(DATAFILE);
    closelog();
    return EXIT_SUCCESS;
}
