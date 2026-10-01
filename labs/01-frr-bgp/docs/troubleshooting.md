# Lab 01 — Troubleshooting Notes

This document records issues encountered while building and testing the lab.

The goal is to preserve real troubleshooting experience rather than only documenting the final working state.

---

# 1. BGP Sessions Established but No Routes Exchanged

## Symptom

BGP sessions were established, but the summary showed:

```text
(Policy)
```

and no prefixes were exchanged.

Example:

```text
State/PfxRcd
0 (Policy)
```

## Cause

FRR was running with:

```text
frr defaults traditional
```

and eBGP policy enforcement required explicit inbound and outbound policies.

Establishing an eBGP session alone was not enough to exchange routes.

## Resolution

Explicit route-maps were applied to all eBGP neighbors.

The policy model was:

```text
R4 -> ISP      PERMIT
ISP -> R4      DENY

ISP -> R1      PERMIT
R1 -> ISP      DENY
```

## Lesson

Do not treat:

```text
BGP Established
```

as proof that routes are being exchanged.

Always inspect:

```bash
show bgp ipv4 unicast summary
```

and the actual BGP table.

---

# 2. R3 BGP Sessions Temporarily Idle

## Symptom

R3 showed both BGP peers in:

```text
Idle
```

even though IP connectivity was working.

Ping tests were successful:

```text
R3 -> R1 = reachable
R3 -> R4 = reachable
```

The BGP configuration was also correct.

## Logs

FRR logs showed:

```text
startup did not complete within timeout
```

followed by daemon restarts:

```text
bgpd state -> down
staticd state -> down
watchfrr.sh restart all
```

Later:

```text
zebra state -> up
bgpd state -> up
staticd state -> up
```

## Resolution

No topology change was required.

After FRR completed its daemon restart, both BGP sessions recovered.

## Lesson

Layer-3 connectivity, BGP configuration, and routing-daemon health are three separate troubleshooting layers.

```text
Ping works
!=
BGP process healthy
```

---

# 3. Missing `/etc/frr/frr.conf`

## Observed Message

FRR logs included:

```text
/etc/frr/frr.conf does not exist; skipping config apply
```

## Explanation

This lab uses per-daemon configuration files such as:

```text
/etc/frr/bgpd.conf
/etc/frr/bfdd.conf
```

instead of relying on a single integrated:

```text
/etc/frr/frr.conf
```

The message did not prevent BGP or BFD from operating correctly in the lab.

---

# 4. Missing `/etc/frr/vtysh.conf`

## Symptom

Most `vtysh` commands display:

```text
% Can't open configuration file /etc/frr/vtysh.conf due to 'No such file or directory'.
```

## Impact

The warning has not prevented:

```text
vtysh
BGP
BFD
```

from functioning.

Commands still return valid operational output.

## Future Cleanup

A `vtysh.conf` file can be added later to remove the warning and make the lab output cleaner.

This is cosmetic for the current lab and not a routing failure.

---

# 5. Incorrect BFD Peer Appearing on R4

## Symptom

R4 unexpectedly showed two BFD peers.

Correct dynamic session:

```text
peer 10.0.24.1
interface eth1
```

Incorrect configured session:

```text
peer 10.0.24.2
interface eth2
```

The incorrect peer remained down.

## Initial Investigation

The host-side configuration files were correct.

R2:

```text
peer 10.0.24.2 interface eth2
```

R4:

```text
peer 10.0.24.1 interface eth1
```

Destroying and redeploying the lab did not solve the problem.

## Root Cause

The BFD bind in:

```text
topology.clab.yml
```

was incorrect.

The R4 container was mistakenly mounting the R2 BFD configuration.

Conceptually:

```text
configs/R2/bfdd.conf -> R4 /etc/frr/bfdd.conf
```

instead of:

```text
configs/R4/bfdd.conf -> R4 /etc/frr/bfdd.conf
```

## Resolution

The Containerlab bind was corrected.

After destroy/deploy, R4 showed only:

```text
peer 10.0.24.1
interface eth1
Status: up
```

and R2 showed:

```text
peer 10.0.24.2
interface eth2
Status: up
```

## Lesson

When configuration on the host looks correct but runtime behavior does not match, inspect what is actually mounted inside the container.

Useful commands:

```bash
docker exec -it clab-frr-bgp-R4 \
cat /etc/frr/bfdd.conf
```

and:

```bash
docker inspect clab-frr-bgp-R4 \
--format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
```

Do not assume the source file is the same file the container is actually consuming.

---

# 6. BGP Healthy While Traffic Is Broken

## Symptom

During Test 3B:

```text
BGP = Established
Route = Present
Best Path = R2
```

but:

```text
ping = 100% packet loss
```

## Cause

The data plane was deliberately blackholed without changing BGP state.

## Lesson

A control-plane route proves that routing information exists.

It does not prove that:

```text
remote service is healthy
application is healthy
forwarding is healthy
end-to-end connectivity works
```

Troubleshooting must validate both:

```text
Control Plane
and
Data Plane
```

---

# 7. Interpreting BFD During a One-Way Failure

## Scenario

Test 3C applied:

```bash
tc qdisc replace dev eth2 root netem loss 100%
```

only on R2.

This produced an asymmetric failure:

```text
R2 -> R4 = broken
R4 -> R2 = available
```

## Observation

The monitoring output showed BGP moving to Idle before R2 locally displayed BFD as Down.

## Explanation

R4 could independently detect that BFD packets from R2 had stopped arriving.

R4 could then tear down the BGP session.

Because the reverse direction was still functional, R2 could observe the BGP session closing before its own local BFD timer visibly transitioned to Down.

## Lesson

When troubleshooting BFD:

- Check both sides.
- Consider packet direction.
- Do not assume failure detection occurs at exactly the same instant on both peers.
- Capture timestamps when investigating convergence.
- Distinguish the configured detection timer from end-to-end observed convergence.

---

# Troubleshooting Workflow

A useful workflow for this lab is:

```text
1. Interface state
2. IP addressing
3. Ping / L3 connectivity
4. FRR daemon state
5. BFD state
6. BGP neighbor state
7. BGP route
8. Linux kernel route
9. Actual data-plane test
```

Useful commands include:

```bash
ip addr show
ip route show
ping
ps aux
docker logs
```

FRR:

```bash
vtysh -c "show bfd peers"
vtysh -c "show bgp ipv4 unicast summary"
vtysh -c "show bgp ipv4 unicast"
```

This sequence helps avoid jumping directly to BGP configuration when the real problem may exist at another layer.

# Missing ISP-B Outbound Route Map

## Symptom

R1 originated:

```text
192.0.2.0/24
```

and successfully advertised it to R2, but R3 did not receive the prefix.

R1 showed:

```text
Advertised to:
10.0.12.2
```

but no advertisement to:

```text
10.0.13.2
```

R3 reported:

```text
% Network not in table
```

## Root Cause

The neighbor referenced:

```text
route-map ISP-B-OUT out
```

but the `ISP-B-OUT` route map itself had not been defined.

Operational verification showed:

```text
BGP: 'route-map ISP-B-OUT' not found
```

## Resolution

The missing route map was created:

```text
route-map ISP-B-OUT permit 10
 match ip address prefix-list OUR-PREFIX
 set as-path prepend 65010 65010
!
route-map ISP-B-OUT deny 100
!
```

After a soft outbound refresh, R3 received the prefix.

## Lesson

A route map referenced by a BGP neighbor must also exist as a valid policy definition.

Always verify both:

```text
neighbor configuration
```

and:

```text
show route-map
```

---

# Community Configured but Not Received

## Symptom

R3 received `192.0.2.0/24`, but the expected custom community:

```text
65002:200
```

was not visible.

R4 therefore received a normal path:

```text
65002 65010
```

instead of the expected provider-prepended path.

## Investigation

The R1 outbound route map was inspected using:

```text
show route-map ISP-B-OUT
```

The required community set operation was then confirmed in the runtime configuration:

```text
community 65002:200
```

Community transmission to the R3 neighbor was also explicitly enabled.

## Resolution

R1 applied:

```text
set community 65002:200
```

and the R3 neighbor was configured to send community attributes.

After a soft outbound BGP refresh, R3 displayed:

```text
Community: 65002:200
```

and R4 received:

```text
65002 65002 65002 65010
```
# Transient FRR bgpd Startup Crash

During a fresh Containerlab deployment, R4 initially reported:

```text
bgpd crashed in startup, signal 11
Failed to start bgpd!

## Lesson

When troubleshooting community-based routing policy, validate the entire chain:

```text
1. Community is set by the sender
2. Community transmission is enabled
3. Receiver actually sees the community
4. Community-list matches it
5. Route-map applies the expected action
6. Downstream advertisement reflects the policy
```
