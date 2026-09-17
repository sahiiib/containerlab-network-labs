# Containerlab Network Labs

Hands-on network engineering and architecture labs built with:

- Containerlab
- FRRouting
- Linux networking
- Docker
- BGP / OSPF
- EVPN / VXLAN
- VRF
- Network Automation
- Ansible
- Go

This repository documents practical networking scenarios designed to build
and demonstrate Network Engineer → Network Architect skills.

---

## Architecture Domains

The labs are organized around several core networking domains:

```text
                    Network Architecture
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
     Routing          Architecture        Automation
        │                  │                  │
   BGP / OSPF        EVPN / VXLAN         Ansible
   Policy            VRF                  Go
   RR                Multihoming          APIs
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │
                    Troubleshooting
