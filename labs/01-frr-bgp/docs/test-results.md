# Lab 01 — Test Results

This document records the failure scenarios tested in the FRR BGP multi-homing lab.

---

# Baseline

Under normal conditions, R1 learns two paths to:

```text
203.0.113.0/24
```

Primary:

```text
AS_PATH: 65001 65003
Next-Hop: 10.0.12.2
LocalPref: 200
```

Backup:

```text
AS_PATH: 65002 65003
Next-Hop: 10.0.13.2
LocalPref: 100
```

R1 selects R2 because of the higher Local Preference.

Kernel route:

```text
203.0.113.0/24 via 10.0.12.2 dev eth1
```

---

# Test 3A — Upstream BGP Failure

## Objective

Verify that R1 can fail over to R3 when R2 loses its upstream route while the BGP session between R1 and R2 remains established.

## Failure Injection

The R2 interface toward R4 was disabled:

```bash
docker exec -it clab-frr-bgp-R2 \
ip link set eth2 down
```

This produced:

```text
R1 <---- BGP UP ----> R2

                       X
                       |
                       X

                       R4
```

## Observed Behavior

The R2-R4 BGP session moved out of the Established state.

R2 no longer had the prefix:

```text
% Network not in table
```

However, the R1-R2 BGP session remained established.

R1 received:

```text
R2 -> 0 prefixes
R3 -> 1 prefix
```

The remaining route was:

```text
AS_PATH: 65002 65003
Next-Hop: 10.0.13.2
LocalPref: 100
```

The Linux kernel route changed to:

```text
203.0.113.0/24 via 10.0.13.2 dev eth2
```

## Result

```text
PASS
```

## Lesson

R1 did not fail over because R2 itself disappeared.

R1 failed over because R2 withdrew the route.

```text
Upstream route disappears
        |
        v
R2 removes prefix
        |
        v
BGP withdrawal
        |
        v
R1 removes primary path
        |
        v
R3 becomes best
```

A healthy BGP neighbor and route availability are separate concepts.

---

# Test 3B — Control Plane UP, Data Plane DOWN

## Objective

Demonstrate that BGP can remain fully operational even when actual packet forwarding is broken.

## Failure Injection

A dedicated policy-routing table was configured on R2 with a blackhole route:

```bash
ip route add blackhole 203.0.113.0/24 table 100
```

A policy rule redirected traffic toward that table:

```bash
ip rule add priority 100 \
to 203.0.113.0/24 lookup 100
```

## Control Plane State

The R2-R4 BGP session remained established.

R2 still had the route:

```text
203.0.113.0/24
via 10.0.24.2
AS_PATH: 65003
```

R1 still had both paths.

Primary:

```text
65001 65003
via 10.0.12.2
LocalPref 200
BEST
```

Backup:

```text
65002 65003
via 10.0.13.2
LocalPref 100
```

The Linux kernel still used:

```text
203.0.113.0/24 via 10.0.12.2 dev eth1
```

## Data Plane Result

Ping from R1 to `203.0.113.1` failed:

```text
5 packets transmitted
0 packets received
100% packet loss
```

## Result

```text
PASS
```

## Lesson

The test demonstrated:

```text
BGP       = HEALTHY
Route     = PRESENT
Best Path = R2

Data Plane = FAILED
```

Therefore:

> Route availability is not the same as end-to-end reachability.

BGP had no reason to fail over because no routing information had changed.

---

# Test 3C — BFD Fast Failure Detection

## Objective

Verify that BFD can detect a forwarding-path failure while the physical interface remains operational.

## BFD Configuration

The R2-R4 BFD session used:

```text
Transmit interval: 300 ms
Receive interval:  300 ms
Detect multiplier: 3
```

Nominal detection target:

```text
~900 ms
```

Before the failure:

```text
R2 BFD peer 10.0.24.2 = UP
R4 BFD peer 10.0.24.1 = UP
```

BGP was also established.

---

## Failure Injection

A silent outbound forwarding failure was created on R2:

```bash
tc qdisc replace dev eth2 root netem loss 100%
```

The interface itself remained operational:

```text
state UP
LOWER_UP
qdisc netem
```

Therefore, the test did not depend on interface-down detection.

---

## Observed Behavior

Immediately before the failure:

```text
BFD R2-R4 = UP
BGP R2-R4 = Established

R1:
203.0.113.0/24 via 10.0.12.2 dev eth1
```

Failure injection timestamp:

```text
11:05:30.115
```

Shortly afterward, BFD reported:

```text
Status: down
Diagnostics: control detection time expired
```

The R2-R4 BGP session left the Established state.

R2 removed the prefix:

```text
% Network not in table
```

R1 then had only the R3 path:

```text
AS_PATH: 65002 65003
Next-Hop: 10.0.13.2
LocalPref: 100
BEST
```

The Linux routing table changed to:

```text
203.0.113.0/24 via 10.0.13.2 dev eth2
```

## Observed Convergence

The monitoring loop showed the first observed failover roughly within:

```text
1-2 seconds
```

after failure injection.

This is an observed value rather than a precise BFD benchmark because the monitoring loop itself executed several Docker and VTY commands between samples.

The configured BFD timer target remained approximately:

```text
300 ms x 3 = 900 ms
```

---

## One-Way Failure Observation

The `netem` impairment was applied only to the outbound direction of R2's `eth2`.

Therefore:

```text
R2 -> R4 = broken
R4 -> R2 = still available
```

The monitoring output showed BGP transitioning before R2 locally displayed the BFD state as down.

A plausible sequence is:

```text
R4 stops receiving BFD packets from R2
        |
        v
R4 detects BFD failure
        |
        v
R4 tears down BGP
        |
        v
R2 receives BGP session closure
        |
        v
R2 BGP becomes Idle
        |
        v
R2's local BFD timer also expires
```

The experiment demonstrates that failure direction matters when interpreting control-plane logs.

---

## Result

```text
PASS
```

## Lesson

Test 3C demonstrates the role of BFD:

```text
Interface remains UP
        |
        v
Forwarding path fails
        |
        v
BFD detects failure
        |
        v
BGP reacts
        |
        v
Route withdrawn
        |
        v
R1 selects backup path
```

BFD improves fast failure detection between its endpoints.

It does not, by itself, verify end-to-end service or application availability.

# Test 3D — End-to-End Health Tracking

## Objective

Demonstrate a failure scenario where:

```text
Interface = UP
BFD       = UP
BGP       = UP
Route     = PRESENT
```

but an end-to-end health target becomes unreachable.

The goal is to detect the failure using an active probe and dynamically influence BGP path selection without tearing down the BGP session.

---

## Health Target

A dedicated loopback was configured on R4:

```text
198.51.100.1/32
```

R1 uses a static host route to force the health probe through the primary path:

```text
198.51.100.1/32 via 10.0.12.2
```

Therefore, the health-check path is:

```text
R1 -> R2 -> R4 -> 198.51.100.1
```

The production route being influenced remains:

```text
203.0.113.0/24
```

---

## Baseline

The health target was reachable:

```text
5 packets transmitted
5 packets received
0% packet loss
```

The production prefix had two BGP paths.

Primary:

```text
AS_PATH:   65001 65003
Next-Hop:  10.0.12.2
LocalPref: 200
BEST
```

Backup:

```text
AS_PATH:   65002 65003
Next-Hop:  10.0.13.2
LocalPref: 100
```

---

## Health Tracking Logic

The health tracker uses:

```text
Failure threshold:  3
Recovery threshold: 3
```

The primary inbound BGP policy normally assigns:

```text
LocalPref = 200
```

A degraded policy assigns:

```text
LocalPref = 50
```

Therefore:

```text
Healthy:

R2 = 200
R3 = 100
R2 wins
```

and:

```text
Degraded:

R2 = 50
R3 = 100
R3 wins
```

---

## Failure Injection

The health target was removed from R4:

```bash
docker exec -it clab-frr-bgp-R4 \
ip addr del 198.51.100.1/32 dev lo
```

No BGP or BFD configuration was changed.

---

## Observed Health Failure

The tracker observed three consecutive failed probes:

```text
probe=DOWN state=healthy failure=1
probe=DOWN state=healthy failure=2
probe=DOWN state=healthy failure=3

HEALTH FAILURE DETECTED
Degrading primary path...
R2 Local Preference changed to 50
```

The health target became unreachable:

```text
3 packets transmitted
0 packets received
100% packet loss
```

---

## Control Plane During Failure

The R2-R4 BGP session remained established.

R2 continued receiving:

```text
203.0.113.0/24
```

from R4.

The BFD session also remained healthy:

```text
Status: up
Diagnostics: ok
Remote diagnostics: ok
```

Therefore:

```text
BGP = UP
BFD = UP
Production route = PRESENT
Health target = DOWN
```

---

## BGP Policy Change

R1 continued to have both BGP paths.

The primary R2 path was degraded to:

```text
AS_PATH:   65001 65003
Next-Hop:  10.0.12.2
LocalPref: 50
```

The R3 path remained:

```text
AS_PATH:   65002 65003
Next-Hop:  10.0.13.2
LocalPref: 100
BEST
```

Unlike Tests 3A and 3C, the R2 path was not withdrawn.

Instead, routing policy made the path less desirable.

---

## Recovery

The health target was restored on R4.

The tracker observed:

```text
probe=UP state=degraded success=1
probe=UP state=degraded success=2
probe=UP state=degraded success=3

HEALTH RECOVERED
Restoring primary policy...
R2 Local Preference restored to 200
```

R1 returned to:

```text
AS_PATH:   65001 65003
Next-Hop:  10.0.12.2
LocalPref: 200
BEST
```

The Linux kernel route returned to:

```text
203.0.113.0/24 via 10.0.12.2 dev eth1
```

BFD remained UP throughout the test.

---

## Result

```text
PASS
```

## Lesson

Test 3D demonstrates a different failure domain from BFD.

```text
BFD
  |
  +-- verifies forwarding reachability between BFD endpoints
```

while:

```text
Active Health Probe
  |
  +-- verifies reachability of a selected remote target
```

This produces four distinct failure models in the lab:

```text
Test 3A
Upstream routing failure
        ->
Route withdrawal
```

```text
Test 3B
Data-plane failure not detected by routing protocols
        ->
Blackhole
```

```text
Test 3C
Forwarding failure between BFD peers
        ->
BFD-triggered convergence
```

```text
Test 3D
Remote health failure beyond a healthy BGP/BFD adjacency
        ->
Active probe
        ->
Policy change
        ->
Path failover
```
---

# Comparison

| Test | Interface | BGP | BFD | Remote Health | Detection | Action |
|---|---|---|---|---|---|---|
| 3A | Down | Fails upstream | N/A | N/A | Link/BGP | Route withdrawal |
| 3B | Up | Up | N/A | Failed | None | Blackhole |
| 3C | Up | Fails after BFD | Down | N/A | BFD | Route withdrawal |
| 3D | Up | Up | Up | Failed | Active probe | LocalPref change |

---

# Recovery Validation

After removing the injected failure:

```bash
tc qdisc del dev eth2 root
```

BFD recovered:

```text
Status: up
```

BGP re-established between R2 and R4.

R1 again learned both paths and selected:

```text
65001 65003
LocalPref 200
BEST
```

The kernel route returned to:

```text
203.0.113.0/24 via 10.0.12.2 dev eth1
```

# Test 4 — BGP Traffic Engineering

This group of tests explores how BGP policy can influence outbound traffic, inbound traffic, route propagation, and provider behavior.

The customer prefix used for these tests is:

```text
192.0.2.0/24
```

R1 originates the prefix toward both providers.

---

## Test 4A — Local Preference

R1 receives the upstream production prefix through both R2 and R3.

Policy:

```text
R2 LocalPref = 200
R3 LocalPref = 100
```

R1 selects R2.

This demonstrates outbound traffic engineering because Local Preference controls which exit path the local AS prefers.

Result:

```text
PASS
```

---

## Test 4B — AS-Path Prepending

R1 advertised `192.0.2.0/24` normally through R2 and prepended AS65010 twice toward R3.

R2 received:

```text
65010
```

R3 received:

```text
65010 65010 65010
```

R4 received:

```text
via R2:
65001 65010

via R3:
65002 65010 65010 65010
```

R4 selected R2:

```text
best (AS Path)
```

Kernel route:

```text
192.0.2.0/24 via 10.0.24.1 dev eth1
```

Result:

```text
PASS
```

---

## Test 4C — Reverse AS-Path Prepending

The prepend policy was moved from R3 to R2.

R2 received:

```text
65010 65010 65010
```

R3 received:

```text
65010
```

R4 received:

```text
via R2:
65001 65010 65010 65010

via R3:
65002 65010
```

R4 selected R3:

```text
best (AS Path)
```

Kernel route:

```text
192.0.2.0/24 via 10.0.34.1 dev eth2
```

A normal ping sourced from R4's transit address initially failed because R1 had no return route to `10.0.34.0/30`.

Using the routed production address as the source:

```text
203.0.113.1 -> 192.0.2.1
```

succeeded with zero packet loss.

The resulting path was asymmetric:

```text
Request:
R4 -> R3 -> R1

Reply:
R1 -> R2 -> R4
```

Result:

```text
PASS
```

---

## Test 4D — MED

### Default Behavior

R3 advertised:

```text
MED = 200
```

R2 advertised:

```text
MED = 50
```

The paths were learned from different neighboring ASes:

```text
R2 = AS65001
R3 = AS65002
```

R4 selected:

```text
R3
best (Older Path)
```

despite R2 having the lower MED.

This demonstrated that the MED values were not being used to compare these paths under the default behavior.

### always-compare-med

The following was enabled on R4:

```text
bgp always-compare-med
```

R4 then selected:

```text
R2
MED = 50
best (MED)
```

The kernel route changed to:

```text
192.0.2.0/24 via 10.0.24.1 dev eth1
```

Result:

```text
PASS
```

---

## Test 4E-A — NO_EXPORT

R1 attached the well-known community:

```text
no-export
```

when advertising the customer prefix to R3.

R3 received:

```text
65010
Community: no-export
```

FRR reported:

```text
not advertised to EBGP peer
```

R3 retained the route locally but did not advertise it to R4.

R4 therefore received only:

```text
65001 65010
```

through R2.

Result:

```text
PASS
```

---

## Test 4E-B — Custom Provider Community

A custom provider community was defined for the lab:

```text
65002:200
```

Its provider-defined meaning was:

```text
Prepend AS65002 twice when advertising the customer's prefix upstream.
```

R1 attached the community when sending `192.0.2.0/24` to R3.

R3 received:

```text
65010
Community: 65002:200
```

R3 matched the community with:

```text
CUST-PREPEND-2
```

and applied:

```text
set as-path prepend 65002 65002
```

R4 received:

```text
via R3:
65002 65002 65002 65010
Community: 65002:200
```

while the R2 path remained:

```text
65001 65010
```

R2 therefore became best due to the shorter AS path.

### Causality Test

The community was removed from the R1 advertisement without changing the BGP session or topology.

R3 continued to receive the route:

```text
65010
```

but no longer displayed:

```text
Community: 65002:200
```

The provider route map fell through to its normal-export sequence.

R4 then received:

```text
65002 65010
```

instead of:

```text
65002 65002 65002 65010
```

This demonstrated that the custom community directly triggered the provider's prepend policy.

Result:

```text
PASS
```

---

# Traffic Engineering Test Matrix

| Test | Mechanism | Policy Effect | Result |
|---|---|---|---|
| 4A | Local Preference | Prefer R2 for outbound traffic | PASS |
| 4B | AS-Path Prepend | Prefer R2 for inbound traffic | PASS |
| 4C | Reverse Prepend | Move inbound traffic to R3 | PASS |
| 4D | MED | Demonstrate MED comparison behavior | PASS |
| 4E-A | NO_EXPORT | Prevent eBGP propagation through R3 | PASS |
| 4E-B | Custom Community | Trigger provider-side AS prepend | PASS |
