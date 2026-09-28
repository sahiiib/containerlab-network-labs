# Lab 01 — FRR BGP Multi-Homing, Failover, and BFD

## Overview

This lab builds a multi-homed BGP environment using FRRouting and Containerlab.

The goal is not only to establish BGP sessions, but to study:

- BGP best-path selection
- Local Preference
- Primary and backup upstream design
- BGP route withdrawal
- Upstream failures
- Control-plane vs data-plane failures
- Fast failure detection with BFD
- Linux kernel route changes during convergence

The lab is designed to evolve incrementally as part of a broader network architecture learning path.

---

## Topology

```text
                       R4
                    AS65003
                   /       \
                  /         \
                R2           R3
             AS65001      AS65002
                 \           /
                  \         /
                       R1
                    AS65010
```

### Links

```text
R1 <-> R2
10.0.12.0/30

R1 <-> R3
10.0.13.0/30

R2 <-> R4
10.0.24.0/30

R3 <-> R4
10.0.34.0/30
```

### Loopbacks

| Router | Loopback |
|---|---|
| R1 | `1.1.1.1/32` |
| R2 | `2.2.2.2/32` |
| R3 | `3.3.3.3/32` |
| R4 | `4.4.4.4/32` |

---

## Autonomous Systems

| Router | Role | ASN |
|---|---|---:|
| R1 | Customer / Multi-homed edge | 65010 |
| R2 | Primary ISP | 65001 |
| R3 | Backup ISP | 65002 |
| R4 | Upstream network | 65003 |

---

## Advertised Prefix

`R4` originates:

```text
203.0.113.0/24
```

The prefix is learned by both upstream paths:

```text
R4 -> R2 -> R1
R4 -> R3 -> R1
```

---

## BGP Policy

R1 prefers R2 over R3 using Local Preference.

### Primary path

```text
R1 -> R2 -> R4

Local Preference: 200
```

### Backup path

```text
R1 -> R3 -> R4

Local Preference: 100
```

Therefore, under normal conditions:

```text
R2 wins because:

200 > 100
```

The expected Linux kernel route on R1 is:

```text
203.0.113.0/24 via 10.0.12.2 dev eth1
```

---

## Routing Policy Design

Explicit import and export policies are used instead of disabling FRR's eBGP policy enforcement.

The intended policy model is:

```text
R4 -> ISP      PERMIT
ISP -> R4      DENY

ISP -> R1      PERMIT
R1 -> ISP      DENY
```

This prevents unintended route propagation and provides a safer foundation for later route-policy labs.

---

## BFD

BFD is enabled between R2 and R4.

```text
R2
10.0.24.1
   |
   | BFD
   |
10.0.24.2
R4
```

Configured timers:

```text
Transmit interval: 300 ms
Receive interval:  300 ms
Detect multiplier: 3
```

The nominal detection target is approximately:

```text
300 ms x 3 = 900 ms
```

BGP is linked to the BFD session so a forwarding-path failure can trigger fast BGP convergence.

---

## Directory Structure

```text
labs/01-frr-bgp/
├── README.md
├── topology.clab.yml
├── configs/
│   ├── R1/
│   │   ├── bgpd.conf
│   │   └── daemons
│   ├── R2/
│   │   ├── bgpd.conf
│   │   ├── bfdd.conf
│   │   └── daemons
│   ├── R3/
│   │   ├── bgpd.conf
│   │   └── daemons
│   └── R4/
│       ├── bgpd.conf
│       ├── bfdd.conf
│       └── daemons
└── docs/
    ├── test-results.md
    └── troubleshooting.md
```

---

## Deploy the Lab

From the lab directory:

```bash
sudo containerlab deploy -t topology.clab.yml
```

Inspect the topology:

```bash
sudo containerlab inspect -t topology.clab.yml
```

Destroy the lab:

```bash
sudo containerlab destroy -t topology.clab.yml
```

---

## Basic Validation

Check BGP on R1:

```bash
docker exec -it clab-frr-bgp-R1 \
vtysh -c "show bgp ipv4 unicast summary"
```

Check the advertised prefix:

```bash
docker exec -it clab-frr-bgp-R1 \
vtysh -c "show bgp ipv4 unicast 203.0.113.0/24"
```

Check the installed kernel route:

```bash
docker exec -it clab-frr-bgp-R1 \
ip route show 203.0.113.0/24
```

Check BFD on R2:

```bash
docker exec -it clab-frr-bgp-R2 \
vtysh -c "show bfd peers"
```

---

## Failure Tests

The lab currently includes the following scenarios.

### Test 3A — Upstream BGP Failure

The R2-R4 path is disconnected while the R1-R2 BGP session remains established.

Expected result:

```text
R2 loses the route from R4
-> R2 withdraws the prefix
-> R1 removes the R2 path
-> R3 becomes the best path
```

Result:

```text
PASS
```

---

### Test 3B — Control Plane UP, Data Plane DOWN

BGP remains completely healthy while forwarding of traffic toward `203.0.113.0/24` is deliberately blackholed on R2.

Expected result:

```text
BGP remains UP
Route remains installed
R1 continues preferring R2
Actual traffic fails
```

Result:

```text
PASS
```

This demonstrates an important principle:

> A valid route does not guarantee a healthy data plane.

---

### Test 3C — BFD Fast Failure Detection

The R2-R4 interfaces remain operational while outbound traffic is silently dropped using Linux `tc netem`.

Expected result:

```text
Interface remains UP
-> BFD detects forwarding failure
-> BGP session is removed
-> Prefix is withdrawn
-> R1 fails over to R3
```

Result:

```text
PASS
```

Detailed results are documented in:

```text
docs/test-results.md
```

---

## Key Lessons

This lab demonstrates several important routing concepts:

1. BGP best-path selection is policy-driven.
2. Local Preference can define primary and backup paths.
3. A BGP neighbor can stay established even when a specific route disappears.
4. A healthy BGP session does not guarantee end-to-end reachability.
5. BFD can detect forwarding-path failures faster than standard BGP timers.
6. BFD only verifies the path between its endpoints; it does not guarantee application or remote-service health.
7. The BGP RIB and Linux kernel routing table should both be inspected during troubleshooting.

---

## Next Steps

Future extensions of this lab will include:

- End-to-end health tracking
- Conditional routing based on probe results
- Additional BFD experiments
- Prefix filtering
- Controlled route advertisement
- More detailed convergence measurement
