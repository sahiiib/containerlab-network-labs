# Addressing Plan

## Point-to-Point Links

| Link | Network | Side A | Side B |
|---|---|---|---|
| R1-R2 | `10.0.12.0/30` | R1: `10.0.12.1` | R2: `10.0.12.2` |
| R1-R3 | `10.0.13.0/30` | R1: `10.0.13.1` | R3: `10.0.13.2` |
| R2-R4 | `10.0.24.0/30` | R2: `10.0.24.1` | R4: `10.0.24.2` |
| R3-R4 | `10.0.34.0/30` | R3: `10.0.34.1` | R4: `10.0.34.2` |

## Loopbacks and Routed Test Prefixes

| Router | Address / Prefix | Purpose |
|---|---|---|
| R1 | `1.1.1.1/32` | Router ID / loopback |
| R1 | `192.0.2.1/24` | Customer prefix origin (`192.0.2.0/24`) |
| R2 | `2.2.2.2/32` | Router ID / loopback |
| R3 | `3.3.3.3/32` | Router ID / loopback |
| R4 | `4.4.4.4/32` | Router ID / loopback |
| R4 | `203.0.113.1/24` | Upstream production prefix origin (`203.0.113.0/24`) |
| R4 | `198.51.100.1/32` | End-to-end health target |

## Autonomous Systems

| Router | Local AS | Router ID |
|---|---:|---|
| R1 | 65010 | `1.1.1.1` |
| R2 | 65001 | `2.2.2.2` |
| R3 | 65002 | `3.3.3.3` |
| R4 | 65003 | `4.4.4.4` |

## BGP Neighbors

### R1 — AS65010

```text
10.0.12.2 -> AS65001 (R2)
10.0.13.2 -> AS65002 (R3)
```

### R2 — AS65001

```text
10.0.12.1 -> AS65010 (R1)
10.0.24.2 -> AS65003 (R4)
```

### R3 — AS65002

```text
10.0.13.1 -> AS65010 (R1)
10.0.34.2 -> AS65003 (R4)
```

### R4 — AS65003

```text
10.0.24.1 -> AS65001 (R2)
10.0.34.1 -> AS65002 (R3)
```

## BFD Session

BFD is configured only between R2 and R4:

```text
R2: 10.0.24.1 / eth2
R4: 10.0.24.2 / eth1
```

Profile:

```text
Transmit interval: 300 ms
Receive interval:  300 ms
Detect multiplier: 3
```

## Static Routes Used by the Lab

### R1

Health target pinned through R2:

```text
198.51.100.1/32 via 10.0.12.2 dev eth1
```

### R2

Health-target reachability toward R4:

```text
198.51.100.1/32 via 10.0.24.2 dev eth2
```

### R4

Transit return routes:

```text
10.0.12.0/30 via 10.0.24.1 dev eth1
10.0.13.0/30 via 10.0.34.1 dev eth2
```

Health-target covering route:

```text
blackhole 198.51.100.0/24
```

The host route for `198.51.100.1/32` on R4 remains more specific than the covering blackhole.

## Temporary Test Prefixes

The following prefixes were used only during failure/security testing and are not part of the permanent addressing plan:

```text
198.18.0.0/24
198.19.0.0/24
10.10.10.0/24
```

They must not remain in the final saved configuration.
