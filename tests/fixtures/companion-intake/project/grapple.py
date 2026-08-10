"""Small executable grapple behavior owned by the fixture project."""

RELEASE_CARRY_MULTIPLIER = 1.15


def release_grapple(tangential_velocity: float) -> tuple[bool, float]:
    """Clear the tether and return the carried tangential velocity."""
    tether_cleared = True
    return tether_cleared, tangential_velocity * RELEASE_CARRY_MULTIPLIER


def can_attach(target_kind: str) -> bool:
    """Keep attachment restricted to explicit anchors."""
    return target_kind == "anchor"
