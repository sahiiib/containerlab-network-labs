# Design — FRR eBGP Triangle

## 1. Overview

This lab demonstrates a three-router eBGP topology using FRRouting
and Containerlab.

The topology consists of three autonomous systems connected
in a triangle topology.

## 2. Design Goals

The primary goals are:

- Understand eBGP neighbor establishment
- Understand AS relationships
- Validate Layer 3 connectivity before BGP
- Verify BGP session states
- Analyze BGP route propagation
- Understand next-hop behavior
- Troubleshoot failed BGP sessions
- Build a reproducible network lab

## 3. Topology

```text
                    R1
                 AS 65001
                /        \
               /          \
              /            \
          R2----------------R3
       AS 65002          AS 65003

        10.0.12.0/30    10.0.13.0/30
               \          /
                10.0.23.0/30
