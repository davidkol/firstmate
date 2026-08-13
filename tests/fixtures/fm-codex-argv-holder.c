#include <signal.h>
#include <unistd.h>

/*
 * Test-only process whose kernel argv stays available until the test stops it.
 * Compile it as "codex" so the production argv oracle sees the same argv[0]
 * shape as a PATH-resolved Codex launch.
 */
int main(void) {
    for (;;) {
        pause();
    }
}
