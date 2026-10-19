// onigiri-alarm-sleep SECONDS [INPUT_DEVICE...]: sleep like sleep(1), but on an alarm clock that
// wakes the phone from suspend, or until one of the input devices (e.g. the power key) reports an
// event. Then hold the "onigiri-standby" wakelock so the caller can act before the phone sleeps
// again (release it with: echo onigiri-standby > /sys/power/wake_unlock).
//
// Build: aarch64-linux-android30-clang -O2 -s -o ../system/bin/onigiri-alarm-sleep onigiri-alarm-sleep.c
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/epoll.h>
#include <sys/timerfd.h>
#include <unistd.h>

#define WAKELOCK "onigiri-standby"

int main(int argc, char **argv) {
    if (argc < 2 || atoi(argv[1]) <= 0) {
        fprintf(stderr, "usage: %s SECONDS [INPUT_DEVICE...]\n", argv[0]);
        return 2;
    }
    struct itimerspec when = {.it_value = {.tv_sec = atoi(argv[1])}};
    // EPOLLWAKEUP keeps the phone awake from the event until we hold the wakelock ourselves.
    struct epoll_event event = {.events = EPOLLIN | EPOLLWAKEUP};
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
    while (epoll_wait(poll, &event, 1, -1) < 0 && errno == EINTR) {
    }
    int lock = open("/sys/power/wake_lock", O_WRONLY | O_CLOEXEC);
    if (lock < 0 || write(lock, WAKELOCK, sizeof(WAKELOCK) - 1) < 0) {
        perror("onigiri-alarm-sleep: wake_lock");
        return 1;
    }
    return 0;
}
