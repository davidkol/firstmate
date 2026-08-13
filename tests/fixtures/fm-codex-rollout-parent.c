#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

/*
 * Test-only Codex-shaped parent: hold one or more rollout files open while a
 * child runs the away entry checker, matching the OS identity the production
 * guard inspects without adding a caller-controlled seam to that guard.
 */
int main(int argc, char **argv) {
    int separator = 1;
    pid_t child;
    int status;

    while (separator < argc && argv[separator][0] != '-') {
        if (open(argv[separator], O_RDONLY) < 0) {
            perror(argv[separator]);
            return 125;
        }
        separator++;
    }
    if (separator >= argc || separator + 1 >= argc || argv[separator][0] != '-' || argv[separator][1] != '\0') {
        fprintf(stderr, "usage: codex <rollout>... - <command> [args...]\n");
        return 125;
    }

    child = fork();
    if (child < 0) {
        perror("fork");
        return 125;
    }
    if (child == 0) {
        execv(argv[separator + 1], &argv[separator + 1]);
        perror(argv[separator + 1]);
        _exit(125);
    }
    if (waitpid(child, &status, 0) < 0) {
        perror("waitpid");
        return 125;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return 125;
}
