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

### Test 3D — End-to-End Health Tracking

BGP and BFD remain healthy while a remote health target becomes unreachable.

A dedicated probe address is used:

```text
198.51.100.1/32
```

The health-check route is pinned through the primary R2 path:

```text
R1 -> R2 -> R4 -> 198.51.100.1
```

The production prefix remains:

```text
203.0.113.0/24
```

A health-tracking script continuously probes the health target.

Normal state:

```text
R2 LocalPref = 200
R3 LocalPref = 100

Best Path = R2
```

After three consecutive probe failures:

```text
R2 LocalPref = 50
R3 LocalPref = 100

Best Path = R3
```

The BGP sessions and the R2-R4 BFD session remain established during the failure.

After three successful recovery probes, the primary policy is restored:

```text
R2 LocalPref = 200
```

Result:

```text
PASS
```

This test demonstrates that BGP and BFD alone do not guarantee end-to-end service reachability.

An active health probe can be combined with routing policy to influence path selection based on remote reachability.

---

## BGP Traffic Engineering

The lab also demonstrates several BGP traffic-engineering techniques using the customer prefix:

```text
192.0.2.0/24
```

R1 originates the prefix toward two upstream providers:

```text
R2 — AS65001
R3 — AS65002
```

### Test 4A — Outbound Traffic Engineering with Local Preference

R1 prefers R2 for outbound traffic:

```text
R2 LocalPref = 200
R3 LocalPref = 100
```

Result:

```text
R1 -> R2 -> R4
```

Local Preference provides direct policy control inside the local AS.

---

### Test 4B — Inbound Traffic Engineering with AS-Path Prepending

R1 prepends its ASN when advertising through R3.

R4 receives:

```text
via R2:
65001 65010

via R3:
65002 65010 65010 65010
```

R4 selects the shorter path through R2.

Result:

```text
PASS
```

---

### Test 4C — Moving Inbound Traffic to R3

The prepend policy is reversed.

R4 receives:

```text
via R2:
65001 65010 65010 65010

via R3:
65002 65010
```

R4 selects R3.

The resulting forwarding behavior demonstrates asymmetric routing:

```text
Inbound:
R4 -> R3 -> R1

Return:
R1 -> R2 -> R4
```

Result:

```text
PASS
```

---

### Test 4D — MED Behavior

Different MED values were advertised through R2 and R3.

Without `bgp always-compare-med`, R4 did not use MED to compare paths learned from different neighboring autonomous systems.

Observed:

```text
R3:
MED 200
BEST (Older Path)

R2:
MED 50
```

After enabling:

```text
bgp always-compare-med
```

R4 selected:

```text
R2
MED 50
BEST (MED)
```

Result:

```text
PASS
```

This demonstrates that MED comparison behavior depends on BGP policy and neighboring-AS context.

---

### Test 4E-A — NO_EXPORT Community

R1 advertised `192.0.2.0/24` to R3 with:

```text
Community: no-export
```

R3 installed the route locally but did not advertise it to its eBGP upstream R4.

R4 therefore learned the prefix only through R2.

Result:

```text
PASS
```

---

### Test 4E-B — Custom Provider Community

A lab-specific provider community was defined:

```text
65002:200
```

Meaning:

```text
When R3 receives this community from a customer,
prepend AS65002 twice when advertising the route upstream.
```

R1 attached:

```text
Community: 65002:200
```

R3 matched the community and applied:

```text
set as-path prepend 65002 65002
```

R4 received:

```text
via R2:
65001 65010

via R3:
65002 65002 65002 65010
```

Removing the community caused R3 to fall back to normal advertisement:

```text
65002 65010
```

This proved that the community itself triggered the provider policy.

Result:

```text
PASS
```

---

## Traffic Engineering Summary

| Mechanism | Primary Use |
|---|---|
| Local Preference | Control outbound path inside the local AS |
| AS-Path Prepending | Influence inbound path selection in remote ASes |
| MED | Suggest preferred ingress to a neighboring AS |
| BGP Community | Signal policy intent between networks |
| NO_EXPORT | Restrict route propagation outside an AS |
| Custom Community | Trigger provider-specific routing policy |


---

## BGP Route Security and Policy Hardening

This milestone validates defensive BGP controls on the customer-provider edge.

Implemented controls:

- Prefix allowlisting for customer advertisements
- Maximum-prefix protection
- AS-path validation
- Route-leak prevention
- Bogon/private prefix filtering

### Security Policy on R2

The customer-facing BGP session from R1 is protected using multiple independent controls:

- `CUSTOMER-R1` permits only the authorized customer prefix `192.0.2.0/24`
- `CUSTOMER-AS` permits only the direct customer AS path `^65010$`
- `BOGON-V4` rejects RFC1918/private address space
- `maximum-prefix 2 force` protects against excessive prefix advertisements
- `soft-reconfiguration inbound` allows verification of rejected received routes

The inbound policy follows this order:

1. Reject bogon/private prefixes
2. Permit the authorized customer prefix with the expected AS path
3. Deny everything else

This provides defense in depth against accidental leaks, unauthorized announcements, and malformed routing policy.

### Route Security Test Matrix

| Test | Control | Expected Protection | Result |
|---|---|---|---|
| 5A | Prefix filtering | Reject unauthorized customer prefixes | PASS |
| 5B | Maximum-prefix | Tear down the session when the configured prefix limit is exceeded | PASS |
| 5C | AS-path filtering | Reject an authorized prefix with an unexpected AS path | PASS |
| 5D | Route-leak prevention | Reject an upstream-learned route leaked back toward a provider | PASS |
| 5E | Bogon/private filtering | Reject RFC1918/private advertisements while keeping the legitimate customer prefix | PASS |

After cleanup, the lab was destroyed and deployed again from the saved configuration. BGP sessions, normal route exchange, maximum-prefix protection, AS-path validation, and bogon filtering all returned correctly.

**Reproducibility:** PASS

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

Future extensions of this lab may include:

- RPKI origin validation
- More complete IPv4 bogon/reserved-prefix filtering
- IPv6 BGP policy and filtering
- Graceful restart and additional convergence experiments
- Route-policy scaling with peer-groups and reusable policy objects
- Automated validation of BGP policy with test scripts
