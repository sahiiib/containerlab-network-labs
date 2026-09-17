# Containerlab Network Labs

Hands-on network architecture labs built with Containerlab, Docker and FRRouting.

## Labs

### 01 - eBGP Triangle

Three FRRouting routers running in a Containerlab topology.

```text
                 R1
              AS 65001
             /        \
            /          \
     10.0.12.0/30   10.0.13.0/30
          /              \
         R2--------------R3
      AS 65002        AS 65003
              10.0.23.0/30
