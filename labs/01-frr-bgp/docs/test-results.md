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

---

# Comparison

| Test | Interface | BGP initially | Data Plane | Detection | Result |
|---|---|---|---|---|---|
| 3A | Down | Fails | Fails | Link/BGP | Failover to R3 |
| 3B | Up | Up | Failed | Not detected by BGP | Blackhole |
| 3C | Up | Up | Failed | BFD | Failover to R3 |

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
