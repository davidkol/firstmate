#!/usr/bin/env python3
"""Run the fixture project's observable grapple-release acceptance check."""

from grapple import can_attach, release_grapple


def main() -> None:
    tether_cleared, velocity = release_grapple(20.0)
    assert tether_cleared is True
    assert velocity == 23.0
    assert can_attach("anchor") is True
    assert can_attach("enemy") is False
    print(
        "grapple-release acceptance: "
        "velocity=23.00 tether_cleared=true enemy_attach=false"
    )


if __name__ == "__main__":
    main()
