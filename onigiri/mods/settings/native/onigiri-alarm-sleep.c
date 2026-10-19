// onigiri-alarm-sleep [-p] SECONDS [INPUT_DEVICE...]: sleep like sleep(1), but on an alarm clock
// that wakes the phone from suspend, or until one of the input devices (e.g. the power key)
// reports an event, or until external power comes back (ac, usb, wireless or pogo online, as the
// standby script's powered()), or with -p until something is on USB-C (at once if it already is).
// The caller may hold the "onigiri-standby" wakelock: it is released only once the alarm is
// armed, so the phone can't suspend before it, and held again on wake so the caller can act before
// the phone sleeps (release it with: echo onigiri-standby > /sys/power/wake_unlock).
//
// Build: aarch64-linux-android30-clang -O2 -s -o ../system/bin/onigiri-alarm-sleep onigiri-alarm-sleep.c
#include <errno.h>
#include <fcntl.h>
#include <linux/netlink.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/timerfd.h>
#include <unistd.h>

#define WAKELOCK "onigiri-standby"

static int wakelock(const char *node) {
    int fd = open(node, O_WRONLY | O_CLOEXEC);
    int ok = fd >= 0 && write(fd, WAKELOCK, sizeof(WAKELOCK) - 1) == sizeof(WAKELOCK) - 1;
    if (fd >= 0)
        close(fd);
    return ok;
}

static int powered(void) {
    static const char *const supplies[] = {"ac", "usb", "wireless", "pogo"};
    for (size_t i = 0; i < sizeof(supplies) / sizeof(*supplies); i++) {
        char path[64], online[4] = "";
        snprintf(path, sizeof(path), "/sys/class/power_supply/%s/online", supplies[i]);
        int fd = open(path, O_RDONLY | O_CLOEXEC);
        if (fd >= 0) {
            read(fd, online, sizeof(online) - 1);
            close(fd);
        }
        if (!strcmp(online, "1\n"))
            return 1;
    }
    return 0;
}

static int plugged(void) { return access("/sys/class/typec/port0-partner", F_OK) == 0; }

int main(int argc, char **argv) {
    int wait_plug = argc > 1 && !strcmp(argv[1], "-p");
    argc -= wait_plug;
    argv += wait_plug;
    if (argc < 2 || atoi(argv[1]) <= 0) {
        fprintf(stderr, "usage: onigiri-alarm-sleep [-p] SECONDS [INPUT_DEVICE...]\n");
        return 2;
    }
    struct itimerspec when = {.it_value = {.tv_sec = atoi(argv[1])}};
    // EPOLLWAKEUP keeps the phone awake from the event until we hold the wakelock ourselves.
    struct epoll_event event = {.events = EPOLLIN | EPOLLWAKEUP};  // data.u32 1: uevents
    int timer = timerfd_create(CLOCK_BOOTTIME_ALARM, TFD_CLOEXEC);
    int poll = epoll_create1(EPOLL_CLOEXEC);
    if (timer < 0 || poll < 0 || timerfd_settime(timer, 0, &when, NULL) ||
        epoll_ctl(poll, EPOLL_CTL_ADD, timer, &event)) {
        perror("onigiri-alarm-sleep");
        return 1;
    }
    for (int i = 2; i < argc; i++) {
        int input = open(argv[i], O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (input < 0 || epoll_ctl(poll, EPOLL_CTL_ADD, input, &event))
            perror(argv[i]);  // still sleep on the alarm
    }
    // Kernel uevents: power coming back and a USB-C attach send some, so recheck on each.
    struct sockaddr_nl uevents = {.nl_family = AF_NETLINK, .nl_groups = 1};
    int uevent = socket(AF_NETLINK, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, NETLINK_KOBJECT_UEVENT);
    event.data.u32 = 1;
    if (uevent < 0 || bind(uevent, (struct sockaddr *)&uevents, sizeof(uevents)) ||
        epoll_ctl(poll, EPOLL_CTL_ADD, uevent, &event))
        perror("onigiri-alarm-sleep: uevents");  // still sleep on the alarm
    wakelock("/sys/power/wake_unlock");  // fails harmlessly when the caller held none
    // Checked once the socket is open, so power that came back before it isn't missed.
    while (!powered() && !(wait_plug && plugged())) {
        if (epoll_wait(poll, &event, 1, -1) < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        if (event.data.u32 != 1)
            break;
        char buf[4096];
        while (recv(uevent, buf, sizeof(buf), 0) >= 0 || errno == ENOBUFS) {
        }
    }
    if (!wakelock("/sys/power/wake_lock")) {
        perror("onigiri-alarm-sleep: wake_lock");
        return 1;
    }
    return 0;
}
