# Design — FRR BGP Multi-Homing, Failover, Traffic Engineering, and Route Security

## 1. Overview

This lab models a multi-homed customer edge using FRRouting and Containerlab.

R1 represents the customer network. It connects to two independent providers, R2 and R3. Both providers connect to the upstream network R4.

The design is intentionally small enough to run locally while still supporting realistic experiments with:

- eBGP multi-homing
- primary and backup upstream selection
- BFD-assisted failure detection
- end-to-end health tracking
- inbound and outbound traffic engineering
- BGP communities
- prefix and AS-path validation
- maximum-prefix protection
- route-leak prevention
- bogon/private-prefix filtering

## 2. Topology

```text
                      R4
                   AS65003
                  /       \
                 /         \
                /           \
          R2                     R3
       AS65001                AS65002
          \                     /
           \                   /
            \                 /
                 R1
              AS65010
```

Point-to-point links:

```text
R1 <-> R2   10.0.12.0/30
R1 <-> R3   10.0.13.0/30
R2 <-> R4   10.0.24.0/30
R3 <-> R4   10.0.34.0/30
```

## 3. Router Roles

| Router | ASN | Role |
|---|---:|---|
| R1 | 65010 | Customer / multi-homed edge |
| R2 | 65001 | Primary provider |
| R3 | 65002 | Backup provider |
| R4 | 65003 | Upstream network |

## 4. Routing Intent

### Upstream production prefix

R4 originates:

```text
203.0.113.0/24
```

R1 learns two paths:

```text
R4 -> R2 -> R1
R4 -> R3 -> R1
```

Normal outbound preference on R1:

```text
R2 LocalPref = 200
R3 LocalPref = 100
```

Therefore R2 is normally selected as the primary exit.

### Customer prefix

R1 originates:

```text
192.0.2.0/24
```

The prefix is advertised toward both R2 and R3 and is used for inbound traffic-engineering tests.

## 5. Failure-Detection Design

### BFD

BFD is enabled only on the R2-R4 path:

```text
R2 10.0.24.1 <---- BFD ----> 10.0.24.2 R4
```

Timers:

```text
Transmit: 300 ms
Receive:  300 ms
Multiplier: 3
```

Nominal detection target:

```text
~900 ms
```

BGP on the R2-R4 adjacency is associated with BFD.

### End-to-End Health Tracking

A dedicated health target exists on R4:

```text
198.51.100.1/32
```

R1 pins the health probe through R2:

```text
198.51.100.1/32 via 10.0.12.2
```

The health tracker changes the Local Preference of the R2-learned production route after repeated probe failures:

```text
Healthy:  R2 = 200, R3 = 100
Degraded: R2 = 50,  R3 = 100
```

This allows path failover without tearing down BGP.

## 6. Traffic-Engineering Design

The lab validates:

- Local Preference for outbound path selection
- AS-path prepending for inbound influence
- MED behavior across different neighboring ASes
- `NO_EXPORT` for propagation control
- provider-defined custom communities

The lab-specific provider community is:

```text
65002:200
```

Meaning:

```text
When R3 receives 65002:200 from the customer,
prepend AS65002 twice when advertising the route upstream.
```

## 7. Route-Security Design

The customer-facing session on R2 is hardened with several independent controls.

### Authorized customer prefix

```text
192.0.2.0/24
```

Prefix allowlist:

```text
CUSTOMER-R1
```

### Authorized customer AS path

Only a directly originated customer route is accepted:

```text
^65010$
```

AS-path access-list:

```text
CUSTOMER-AS
```

### Maximum-prefix protection

R2 applies:

```text
neighbor 10.0.12.1 soft-reconfiguration inbound
neighbor 10.0.12.1 maximum-prefix 2 force
```

The `force` behavior allows the received-prefix count to protect the session even when some received routes are later rejected by inbound policy.

### Bogon/private-prefix filtering

R2 explicitly rejects RFC1918 address space:

```text
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
```

### Inbound policy order

Conceptually:

```text
1. Reject bogon/private prefixes
2. Permit the authorized customer prefix with the expected AS path
3. Deny everything else
```

This creates defense in depth against unauthorized advertisements, route leaks, and excessive prefix announcements.

## 8. Policy Philosophy

The lab keeps FRR's explicit eBGP policy behavior and uses route-maps and prefix-lists rather than disabling policy enforcement.

Important design principles:

- A BGP session being Established does not prove that routes are exchanged.
- A valid BGP route does not prove that the data plane is healthy.
- BFD validates forwarding reachability only between its endpoints.
- Active health probes can detect failures beyond the BFD adjacency.
- Customer/provider boundaries should validate both prefix ownership and AS-path intent.
- Export policy and import policy should both protect against route leaks.

## 9. Reproducibility

After the Test 5 security milestone, temporary failure-injection configuration was removed and the lab was destroyed and deployed again.

The saved configuration reproduced:

- established BGP adjacencies
- normal primary/backup routing
- customer prefix propagation
- maximum-prefix protection
- AS-path filtering
- bogon/private-prefix filtering

Result:

```text
PASS
```
